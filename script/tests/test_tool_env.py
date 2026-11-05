#!/usr/bin/env python3
"""工具在每個環境的狀態(可裝／不建議／裝不了,spec #271、#272):
選單每台列全部工具、標出原因,預設組合扣掉不建議與裝不了的,裝不了的勾了就略過、apply 最後列出原因。

環境用 --override-data 模擬(WSL、ARM、非 Debian 系、macOS),在 Linux 上直接渲染樣板,不用容器。
真的 init --apply 一台裝不了的工具、看 exit code 與彙整由 e2e 的 ubuntu 目標驗。
"""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG_TEMPLATE = "home/.chezmoi.toml.tmpl"
SCRIPTS = "home/.chezmoiscripts"
RECORDER = "run_onchange_after_record-env-skipped.sh.tmpl"
SUMMARY = "run_after_zz-root-skipped-summary.sh.tmpl"
# 提示文字(要跟 config 樣板一字不差,同 e2e.sh 的 USE_PROMPT、TOOLS_PROMPT)
USE_PROMPT = "用途：按一個字母（full 完整／minimal 精簡：只要 shell 體驗／custom 自訂）"
# 精簡的預設組合(#273,獨立的期望值):只放 shell 體驗
LEAN = ["zsh", "starship", "eza", "fzf", "bat", "ripgrep", "vim", "fastfetch"]
TOOLS_PROMPT = "選裝工具（空白鍵勾選、Enter 確定；用途選錯按 Ctrl+C 重來）"
SECRETS = ["--promptString", "git user.name=e2e", "--promptString", "git user.email=e2e@example.com",
           "--promptString", "code-server 密碼=x", "--promptString", "codex-lb API key=x",
           "--promptString", "Context7 API key（可留空）=", "--promptString", "WakaTime API key（可留空）="]

WSL = {"chezmoi": {"kernel": {"osrelease": "5.15.167.4-microsoft-standard-WSL2"}}}
ARM = {"chezmoi": {"arch": "arm64"}}
FEDORA = {"chezmoi": {"osRelease": {"id": "fedora", "idLike": ""}}}
MAC = {"chezmoi": {"os": "darwin"}}
# proot Ubuntu:userland 是 Ubuntu,kernel 是 Android 的(proot-distro 不假 /proc/sys/kernel/osrelease)
PROOT = {"chezmoi": {"arch": "arm64", "kernel": {"osrelease": "5.15.123-android14-11-g0a1b2c3d4e5f"}}}
ANDROID = {"chezmoi": {"os": "android"}}
# 這台(跑測試的主機)可能是 WSL 或 ARM:對照組把環境釘成 amd64 的 Ubuntu
UBUNTU = {"chezmoi": {"os": "linux", "arch": "amd64", "kernel": {"osrelease": "6.8.0-1-generic"},
                      "osRelease": {"id": "ubuntu", "idLike": "debian"}}}

# 選單上 headless-chrome 那一行(獨立的期望值,不從樣板算)
HEADLESS_LABEL = "headless-chrome  沒有畫面的 Chrome,給 agent 開網頁"


def merge(a, b):
    out = dict(a)
    for k, v in b.items():
        out[k] = merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out


def menu_tools():
    text = (ROOT / "home/.chezmoitemplates/tool-menu").read_text(encoding="utf-8")
    return [l.split(" ")[0] for l in text.splitlines() if l[:1].isalpha()]


class ToolEnvTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.source = ROOT

    def tearDown(self):
        self.tmp.cleanup()

    def chezmoi(self, env, *args, data=None, stdin=None, check=True):
        override = merge(merge(UBUNTU, env), data or {})
        return subprocess.run([
            "chezmoi", "--no-tty", "--source", str(self.source),
            "--config", str(self.dir / "none.toml"), "--persistent-state", str(self.dir / "state.boltdb"),
            "--override-data", json.dumps(override), *args,
        ], input=stdin, capture_output=True, text=True, check=check)

    def init(self, env, use, picked=None, check=True):
        """全新機器跑 config 樣板:用途選 use,picked 給選單文字(None = 選單直接 Enter)。"""
        flags = [*SECRETS, "--promptChoice", f"{USE_PROMPT}={use[0]}"]
        if picked is not None:
            flags += ["--promptMultichoice", f"{TOOLS_PROMPT}={'/'.join(picked)}"]
        template = (self.source / CONFIG_TEMPLATE).read_text(encoding="utf-8")
        return self.chezmoi(env, "execute-template", "--init", *flags, stdin=template, check=check)

    def render(self, env, path, tools):
        template = (self.source / path).read_text(encoding="utf-8")
        return self.chezmoi(env, "execute-template", data={"tools": tools}, stdin=template).stdout

    def tools_line(self, names):
        return "    tools = [" + ", ".join(f'"{n}"' for n in names) + "]"

    # ===============================================================
    # 選單:每台列全部工具,不建議／裝不了的標原因
    # ===============================================================
    def test_wsl_menu_lists_headless_chrome_with_reason(self):
        label = HEADLESS_LABEL + "（裝不了：WSL 不裝 Linux 的 Chrome，查原因到遠端主機做）"
        out = self.init(WSL, "custom", [label]).stdout
        self.assertIn(self.tools_line(["headless-chrome"]), out)

    def test_rules_name_menu_tools_and_reasons_are_menu_safe(self):
        # 原因接在選單文字後面:半形 / 會被 e2e 的 --promptMultichoice 切開,' 會弄壞略過腳本的引號
        rules = json.loads(self.chezmoi({}, "execute-template",
                                        stdin='{{ includeTemplate "tool-env" . | fromYaml | toJson }}').stdout)
        self.assertTrue(rules)
        for tool, rows in rules.items():
            self.assertIn(tool, menu_tools())
            for row in rows:
                with self.subTest(tool=tool, when=row["when"]):
                    self.assertIn(row["state"], ("discouraged", "unsupported"))
                    self.assertTrue(row["reason"])
                    self.assertFalse(set(row["reason"]) & set("/'="))

    def test_every_environment_lists_every_tool(self):
        names = menu_tools()
        for name, env in {"ubuntu": {}, "wsl": WSL, "arm": ARM, "fedora": FEDORA, "mac": MAC, "android": ANDROID}.items():
            with self.subTest(env=name):
                out = self.chezmoi(env, "execute-template", stdin='{{ includeTemplate "tool-menu-labels" . }}').stdout
                self.assertEqual([l.split(" ")[0] for l in out.splitlines()], names)

    def test_annotations_per_environment(self):
        # 哪幾項帶標註、標的是哪一種(原因文字由上一個測試與 e2e 對)
        expected = {
            "ubuntu": ({}, {}),
            "wsl": (WSL, {"headless-chrome": "裝不了", "playwright-cli": "裝不了", "tailscale": "不建議"}),
            "proot": (PROOT, {"headless-chrome": "裝不了", "playwright-cli": "裝不了", "tailscale": "不建議"}),
            "arm": (ARM, {"headless-chrome": "裝不了", "playwright-cli": "裝不了"}),
            "fedora": (FEDORA, {"headless-chrome": "裝不了", "playwright-cli": "裝不了"}),
            "mac": (MAC, {"headless-chrome": "裝不了", "playwright-cli": "裝不了"}),
        }
        for name, (env, marks) in expected.items():
            with self.subTest(env=name):
                out = self.chezmoi(env, "execute-template", stdin='{{ includeTemplate "tool-menu-labels" . }}').stdout
                got = {}
                for line in out.splitlines():
                    for word in ("不建議", "裝不了"):
                        if f"（{word}：" in line:
                            got[line.split(" ")[0]] = word
                self.assertEqual(got, marks)

    # ===============================================================
    # 預設組合扣掉不建議與裝不了的;沒改勾選照樣存用途
    # ===============================================================
    def test_full_skips_unsupported_and_stays_full(self):
        for name, env, dropped in (("wsl", WSL, {"headless-chrome", "playwright-cli", "tailscale"}),
                                   ("proot", PROOT, {"headless-chrome", "playwright-cli", "tailscale"}),
                                   ("arm", ARM, {"headless-chrome", "playwright-cli"}),
                                   ("fedora", FEDORA, {"headless-chrome", "playwright-cli"}),
                                   ("mac", MAC, {"headless-chrome", "playwright-cli"})):
            with self.subTest(env=name):
                out = self.init(env, "full").stdout
                self.assertIn('    machineUse = "full"', out)
                self.assertIn(self.tools_line([t for t in menu_tools() if t not in dropped]), out)

    def test_ticking_unsupported_on_top_of_full_saves_custom(self):
        labels = self.chezmoi(WSL, "execute-template", stdin='{{ includeTemplate "tool-menu-labels" . }}').stdout.splitlines()
        out = self.init(WSL, "full", labels).stdout
        self.assertIn('    machineUse = "custom"', out)
        self.assertIn(self.tools_line(menu_tools()), out)

    def test_discouraged_is_labelled_unticked_and_still_installed(self):
        # WSL 的網路借 Windows 那份 Tailscale:選單標不建議、完整不勾,勾了照裝、不記略過
        labels = self.chezmoi(WSL, "execute-template", stdin='{{ includeTemplate "tool-menu-labels" . }}').stdout
        self.assertIn("tailscale        私人 VPN,連自己的機器（不建議：網路借 Windows 那份 Tailscale（mirrored），"
                      "再裝一份會變成 tailnet 上兩個節點）", labels.splitlines())
        installing = self.chezmoi(WSL, "execute-template", data={"tools": ["tailscale"]},
                                  stdin='{{ includeTemplate "tools-to-install" . }}').stdout
        self.assertEqual(installing, "tailscale")
        self.assertNotIn("skip_env", self.render(WSL, f"{SCRIPTS}/{RECORDER}", ["tailscale"]))
        self.assertIn("tailscale.com/install.sh",
                      self.render(WSL, f"{SCRIPTS}/run_onchange_after_install-tailscale.sh.tmpl", ["tailscale"]))

    def test_proot_detection(self):
        detect = '{{ includeTemplate "is-proot" . }}'
        self.assertEqual(self.chezmoi(PROOT, "execute-template", stdin=detect).stdout, "true")
        self.assertEqual(self.chezmoi({}, "execute-template", stdin=detect).stdout, "")
        # 平板的 kernel 字串不一定帶 android:data 的 isProot 可以直接指定(也給測試用)
        self.assertEqual(self.chezmoi({}, "execute-template", data={"isProot": True}, stdin=detect).stdout, "true")
        self.assertEqual(self.chezmoi(PROOT, "execute-template", data={"isProot": False}, stdin=detect).stdout, "")
        # 原生 Termux 的 kernel 也是 Android 的,但它不是 proot
        android = {"chezmoi": {"os": "android", "kernel": {"osrelease": "5.15.123-android14-11-g0a1b2c3d4e5f"}}}
        self.assertEqual(self.chezmoi(android, "execute-template", stdin=detect).stdout, "")

    def test_mac_installs_tailscale_app_with_brew_cask(self):
        darwin = f"{SCRIPTS}/run_onchange_before_install-packages-darwin.sh.tmpl"
        brew = self.render(MAC, darwin, ["tailscale", "eza"])
        self.assert_sh(brew)
        self.assertIn('brew "eza"', brew.splitlines())
        self.assertNotIn('brew "tailscale', brew)
        self.assertIn("tailscale-app", brew)
        self.assertNotIn("tailscale-app", self.render(MAC, darwin, ["eza"]))
        # Linux 的 installer 不在 mac 跑,也不記略過
        self.assertEqual(self.render(MAC, f"{SCRIPTS}/run_onchange_after_install-tailscale.sh.tmpl", ["tailscale"]).strip(), "")
        self.assertNotIn("skip_env", self.render(MAC, f"{SCRIPTS}/{RECORDER}", ["tailscale"]))

    def run_darwin_packages(self, tools, failing_cask):
        """在 Linux 上跑 mac 的套件腳本:假的 brew 記下收到的參數,裝 failing_cask 時失敗(像 app 已經從官網裝過)。"""
        bindir = self.dir / "bin"
        bindir.mkdir(exist_ok=True)
        log = self.dir / "brew.log"
        fake = bindir / "brew"
        fake.write_text(f"""#!/bin/sh
echo "$*" >> {log}
fail() {{ echo "Error: It seems there is already an App at '/Applications/Tailscale.app'." >&2; exit 1; }}
if [ "$1" = bundle ]; then
  in=$(cat); echo "$in" >> {log}
  case "$in" in *'cask "{failing_cask}"'*) fail;; esac
fi
case "$*" in *"--cask {failing_cask}"*) fail;; esac
exit 0
""", encoding="utf-8")
        fake.chmod(0o755)
        script = self.dir / "darwin.sh"
        script.write_text(self.render(MAC, f"{SCRIPTS}/run_onchange_before_install-packages-darwin.sh.tmpl", tools),
                          encoding="utf-8")
        env = {"PATH": f"{bindir}:/usr/bin:/bin", "HOME": str(self.dir)}
        run = subprocess.run(["sh", str(script)], env=env, capture_output=True, text=True)
        return run, log.read_text(encoding="utf-8")

    def test_mac_cask_failure_is_skipped_and_apply_keeps_going(self):
        # spec #271 user story 5:Tailscale.app 已經從官網或 App Store 裝過,brew 裝 cask 失敗,apply 照樣跑完
        run, log = self.run_darwin_packages(["tailscale", "eza"], "tailscale-app")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('brew "eza"', log)
        self.assertIn("tailscale-app", log)
        self.assertIn("略過 tailscale-app", run.stdout)
        self.assertIn("/Applications", run.stdout)

    # ===============================================================
    # 裝不了的勾了:不裝、記進略過彙整,彙整分得出兩種原因
    # ===============================================================
    def assert_sh(self, text):
        path = self.dir / "s.sh"
        path.write_text(text, encoding="utf-8")
        subprocess.run(["sh", "-n", str(path)], check=True)

    def test_unsupported_tool_is_not_installed_but_recorded_with_reason(self):
        cases = (
            ("wsl", WSL, "headless-chrome", "run_onchange_after_install-headless-chrome.sh.tmpl",
             "WSL 不裝 Linux 的 Chrome，查原因到遠端主機做"),
            ("wsl", WSL, "playwright-cli", "run_onchange_after_npm-install-playwright-cli.sh.tmpl",
             "它用 headless-chrome，這台裝不了 headless-chrome"),
            ("arm", ARM, "headless-chrome", "run_onchange_after_install-headless-chrome.sh.tmpl",
             "Google 只出 amd64 的 .deb"),
        )
        for name, env, tool, script, reason in cases:
            with self.subTest(env=name, tool=tool):
                self.assertEqual(self.render(env, f"{SCRIPTS}/{script}", [tool, "fzf"]).strip(), "")
                rec = self.render(env, f"{SCRIPTS}/{RECORDER}", [tool, "fzf"])
                self.assert_sh(rec)
                self.assertIn(f"skip_env '{tool}' '{reason}'", rec)
                self.assertNotIn("'fzf'", rec)
                summary = self.render(env, f"{SCRIPTS}/{SUMMARY}", [tool])
                self.assert_sh(summary)
                self.assertIn("== 這台裝不了,以下選裝工具已略過", summary)

    def test_installable_tool_is_installed_and_not_recorded(self):
        self.assertNotEqual(self.render({}, f"{SCRIPTS}/run_onchange_after_install-headless-chrome.sh.tmpl",
                                        ["headless-chrome"]).strip(), "")
        self.assertEqual(self.render({}, f"{SCRIPTS}/{RECORDER}", ["headless-chrome"]).strip(), "")

    def test_wsl_skips_headless_chrome_fonts(self):
        pkgs = self.render(WSL, f"{SCRIPTS}/run_onchange_before_install-packages.sh.tmpl", ["headless-chrome", "vim"])
        self.assertIn("vim", pkgs)
        self.assertNotIn("fonts-noto-cjk", pkgs)

    def test_summary_tells_no_root_from_unsupported(self):
        summary = self.render(WSL, f"{SCRIPTS}/{SUMMARY}", ["headless-chrome"])
        self.assertIn("env-skipped", summary)
        self.assertIn("root-skipped", summary)
        self.assertIn("== 沒有 root,以下步驟已略過", summary)

    def test_minimal_is_shell_experience_only(self):
        out = self.init({}, "minimal").stdout
        self.assertIn('    machineUse = "minimal"', out)
        self.assertIn(self.tools_line(LEAN), out)

    def test_cloudflared_is_in_full_not_lean_and_installed_by_mise_or_brew(self):
        labels = self.chezmoi({}, "execute-template", stdin='{{ includeTemplate "tool-menu-labels" . }}').stdout
        self.assertIn("cloudflared      Cloudflare Tunnel:把服務開給 tailnet 外的人", labels.splitlines())
        self.assertIn('"cloudflared"', self.init({}, "full").stdout)
        self.assertNotIn('"cloudflared"', self.init({}, "minimal").stdout)
        mise = self.render({}, "home/dot_config/mise/conf.d/dotfiles.toml.tmpl", ["cloudflared"])
        self.assertIn('"cloudflared" = "latest"', mise.splitlines())
        brew = self.render(MAC, f"{SCRIPTS}/run_onchange_before_install-packages-darwin.sh.tmpl", ["cloudflared"])
        self.assertIn('brew "cloudflared"', brew.splitlines())

    def test_mac_minimal_is_the_same_lean(self):
        out = self.init(MAC, "minimal").stdout
        self.assertIn('    machineUse = "minimal"', out)
        self.assertIn(self.tools_line(LEAN), out)

    # ===============================================================
    # 原生 Termux(#274):跟 Linux、macOS 同一套用途與選單,pkg 有的工具都能勾
    # ===============================================================
    def write_config(self, use, tools):
        (self.dir / "none.toml").write_text(
            f'[data]\n    machineUse = "{use}"\n    tools = {json.dumps(tools)}\n    toolsSchema = 3\n'
            '    gitUserName = "e2e"\n    gitUserEmail = "e2e@example.com"\n', encoding="utf-8")

    def labels(self, env):
        return self.chezmoi(env, "execute-template", stdin='{{ includeTemplate "tool-menu-labels" . }}').stdout.splitlines()

    def test_android_asks_use_and_menu(self):
        gh = next(l for l in self.labels(ANDROID) if l.startswith("gh "))
        out = self.init(ANDROID, "custom", [gh]).stdout
        self.assertIn('    machineUse = "custom"', out)
        self.assertIn(self.tools_line(["gh"]), out)

    def test_android_minimal_is_ubuntu_minimal(self):
        # 精簡只放 shell 體驗(#273),每一項 Termux 都裝得了:Termux 的精簡跟 Ubuntu 的一樣
        out = self.init(ANDROID, "minimal").stdout
        self.assertIn('    machineUse = "minimal"', out)
        self.assertIn(self.tools_line(LEAN), out)

    def test_android_keeps_hand_added_tool_after_init(self):
        # 以前 android 每次 init 都把 tools 重算回固定那幾項,edit-config 手動加的會不見
        self.write_config("custom", ["gh", "ttyd"])
        template = (self.source / CONFIG_TEMPLATE).read_text(encoding="utf-8")
        out = self.chezmoi(ANDROID, "execute-template", "--init", stdin=template).stdout
        self.assertIn(self.tools_line(["gh", "ttyd"]), out)

    def test_android_unsupported_tools_not_installed_but_recorded(self):
        scripts = {
            "tailscale": "run_onchange_after_install-tailscale.sh.tmpl",
            "code-server": "run_onchange_after_install-code-server.sh.tmpl",
            "claude": "run_onchange_after_install-claude.sh.tmpl",
            "codex": "run_onchange_after_install-codex.sh.tmpl",
            "opencode": "run_onchange_after_install-opencode.sh.tmpl",
            "herdr": "run_onchange_after_install-herdr.sh.tmpl",
            "agent-config": "run_onchange_after_install-agent-config.sh.tmpl",
            "codegraph": "run_onchange_after_npm-install-codegraph.sh.tmpl",
            "headless-chrome": "run_onchange_after_install-headless-chrome.sh.tmpl",
            "playwright-cli": "run_onchange_after_npm-install-playwright-cli.sh.tmpl",
        }
        for tool, script in scripts.items():
            with self.subTest(tool=tool):
                self.assertEqual(self.render(ANDROID, f"{SCRIPTS}/{script}", [tool]).strip(), "")
        rec = self.render(ANDROID, f"{SCRIPTS}/{RECORDER}", [*scripts, "btop", "gh", "wakatime"])
        self.assert_sh(rec)
        recorded = sorted(l.split("'")[1] for l in rec.splitlines() if l.startswith("skip_env "))
        self.assertEqual(recorded, sorted([*scripts, "btop"]))
        self.assertIn("Android app", next(l for l in rec.splitlines() if l.startswith("skip_env 'tailscale'")))
        summary = self.render(ANDROID, f"{SCRIPTS}/{SUMMARY}", ["claude"])
        self.assert_sh(summary)
        self.assertIn("== 這台裝不了,以下選裝工具已略過", summary)

    def test_android_annotations(self):
        got = {l.split(" ")[0] for l in self.labels(ANDROID) if "（裝不了：" in l}
        self.assertEqual(got, {"tailscale", "btop", "code-server", "headless-chrome", "playwright-cli",
                               "claude", "codex", "opencode", "herdr", "agent-config", "codegraph"})

    def test_android_installs_pkg_tools(self):
        tools = ["fastfetch", "gh", "ffmpeg", "ttyd", "cloudflared", "zsh"]
        pkgs = self.render(ANDROID, f"{SCRIPTS}/run_onchange_before_install-packages.sh.tmpl", tools)
        line = next(l for l in pkgs.splitlines() if l.startswith("for pkg in"))
        for p in tools:
            self.assertIn(p, line.replace(";", " ").split())
        self.assertNotIn("nodejs-lts", pkgs)

    def test_android_node_is_pkg_nodejs_lts_not_nvm(self):
        for tool in ("node", "wakatime"):
            with self.subTest(tool=tool):
                self.assertEqual(self.render(ANDROID, f"{SCRIPTS}/run_onchange_after_install-node.sh.tmpl", [tool]).strip(), "")
                pkgs = self.render(ANDROID, f"{SCRIPTS}/run_onchange_before_install-packages.sh.tmpl", [tool])
                self.assertIn("nodejs-lts", pkgs)
                self.assert_sh(pkgs)
                self.assertNotIn("libatomic1", pkgs)
        # wakatime 在 Termux 實測裝得起來(linux 版 wakatime-cli 能跑、連得到 API),不標裝不了
        self.assertNotEqual(self.render(ANDROID, f"{SCRIPTS}/run_onchange_after_install-wakatime.sh.tmpl", ["wakatime"]).strip(), "")

    def test_android_gets_tools_command(self):
        out = self.render(ANDROID, "home/dot_local/bin/executable_tools.tmpl", [])
        first = out.splitlines()[0]
        self.assertTrue(first.startswith("#!") and first != "#!/bin/sh", first)
        self.assertIn("chezmoi init --prompt", out)

    def test_android_does_not_deploy_config_of_unsupported_clients(self):
        ignore = self.render(ANDROID, "home/.chezmoiignore", ["claude", "codex", "opencode", "agent-config", "code-server"])
        lines = {l.strip() for l in ignore.splitlines()}
        for target in (".claude", ".codex", ".config/opencode", ".config/skillshare", ".config/code-server"):
            self.assertIn(target, lines)


if __name__ == "__main__":
    unittest.main()
