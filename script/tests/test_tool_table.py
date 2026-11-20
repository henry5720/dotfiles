#!/usr/bin/env python3
"""選裝工具表與裝法判斷(#331,spec #315):表 home/.chezmoidata/tool-table.yaml、判斷 home/.chezmoitemplates/tool-install。

選單標註、預設組合、略過彙整(#332)、套件清單、mise 清單(#333)、腳本(#334、#336)都讀判斷,這裡拿判斷跟渲染結果比:
- 狀態與原因:選單、完整的預設組合、略過清單跟判斷一致
- 裝法:跟渲染快照(#329)那一格實際渲染出的套件清單、mise 清單、會跑的腳本一致

快照每一格跟現在的樣板一字不差(test_render_snapshot.py 擋),所以「跟快照比」就是「跟現在渲染出的比」。
環境、PATH、家目錄沿用 test_render_snapshot 的 Renderer(lookPath 一律找不到)。
"""
import json
import re
import shutil
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_render_snapshot import ENVS, SELECTIONS, Renderer, path_of  # noqa: E402
from test_tool_status import menu_tools  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RESOLVE = '{{ includeTemplate "tool-install" . }}'
MENU = '{{ includeTemplate "tool-menu-labels" . }}'
TABLE = '{{ include ".chezmoidata/tool-table.yaml" | fromYaml | toJson }}'
NO_METHOD = "沒有這個環境的裝法"
RUNTIMES = {"needsNode": "node", "needsUv": "uv"}  # 表上「要這個 runtime 的 OS」欄 → runtime(#341)  # 表上沒有這個 OS 的裝法、也沒有規則對到時的原因


def table():
    with tempfile.TemporaryDirectory() as tmp:
        return json.loads(Renderer(tmp).run(ENVS["debian-root"], "execute-template", TABLE))["toolTable"]


# ===============================================================
# 讀快照那一格(格式見 test_render_snapshot.format_cell)
# ===============================================================
def sections(text):
    out, name = {}, None
    for line in text.splitlines():
        if line.startswith("## "):
            name = line[3:]
            out[name] = []
        elif line.startswith("### "):
            name = None
        elif name:
            out[name].append(line)
    return out


def parse_cell(text):
    sec = sections(text)
    tools = next(l for l in sec["init 存下的設定"] if l.startswith("    tools = "))
    packages = {}
    for line in sec["套件清單"]:
        key, _, value = line.partition(": ")
        packages[key] = value.split()
    mise = sec["mise 清單"]
    mise = mise[mise.index("[tools]") + 1:] if "[tools]" in mise else []
    scripts = {s.removeprefix(".chezmoiscripts/"): False for s in sec["渲染成空的腳本"] if s}
    scripts |= {s.removeprefix(".chezmoiscripts/"): True for s in sec["會跑的腳本"] if s}
    jq_zsh = text.partition("### .chezmoiscripts/run_onchange_before_install-home-jq-zsh.sh.tmpl")[2]
    return {"tools": json.loads(tools.partition(" = ")[2]),
            "installing": " ".join(sec["要裝"]).split(), "skipped": " ".join(sec["略過(裝不了)"]).split(), "packages": packages, "mise": set(filter(None, mise)),
            "scripts": scripts, "zsh-bin": "zsh_install=" in jq_zsh.partition("\n### ")[0]}


def mise_line(entry):
    """判斷結果的 mise 項目寫成 mise 清單的一行(同 .chezmoitemplates/mise-tools 的寫法)。"""
    def value(v):
        return "[" + ", ".join(json.dumps(x) for x in v) + "]" if isinstance(v, list) else json.dumps(v)
    if not entry["options"]:
        return f'{json.dumps(entry["tool"])} = {json.dumps(entry["version"])}'
    opts = "".join(f", {k} = {value(v)}" for k, v in entry["options"].items())
    return f'{json.dumps(entry["tool"])} = {{ version = {json.dumps(entry["version"])}{opts} }}'


# 工具自己的腳本 → (工具, 哪些裝法會讓它渲染成非空)。只部署到它那個 OS(.ps1 只在 Windows,.sh 不在 Windows)
SCRIPT_METHODS = {
    # claude、codex、herdr、opencode、code-server 的官方 installer 從 #334 起由 install-official 照判斷結果跑,
    # 不再跟舊腳本比(test_official_installer.py 驗渲染結果跟以前各自那支一樣)
    "run_onchange_after_install-gh.sh.tmpl": ("gh", {"script"}),
    "run_onchange_after_install-headless-chrome.sh.tmpl": ("headless-chrome", {"deb"}),
    "run_onchange_after_install-node.sh.tmpl": ("node", {"script"}),
    "run_onchange_after_npm-install-codegraph.sh.tmpl": ("codegraph", {"script"}),
    "run_onchange_after_npm-install-playwright-cli.sh.tmpl": ("playwright-cli", {"script"}),
    "run_onchange_after_install-tailscale.sh.tmpl": ("tailscale", {"official", "script"}),
    **{f"run_onchange_after_install-{t}.sh.tmpl": (t, {"apt"}) for t in ("snapserver", "snapclient", "earlyoom")},
    **{f"run_onchange_after_install-wakatime.{ext}.tmpl": ("wakatime", {"script"}) for ext in ("sh", "ps1")},
    **{f"run_onchange_after_{s}.{ext}.tmpl": ("agent-config", {"official"})
       for s in ("install-agent-config", "sync-skillshare") for ext in ("sh", "ps1")},
}

# 刻意的差異(spec #315「行為改變」與它的推論):判斷已經照新規則算,消費端還照舊,等那張 ticket 切過去。
# (環境, 比的項目, 工具或套件) → 說明。比的項目:installing、apt、mise、script:<腳本>
# 套件清單與 mise 清單從 #333 起照判斷產生;選單、預設組合、略過從 #332 起讀判斷,
# 沒有 root 的 earlyoom、snapclient、snapserver、headless-chrome 經 tools-to-install 一起不裝了。現在沒有差異。
KNOWN = {
}


class ToolTableTest(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls):
        cls.table = table()
        cells = [(env, sel) for env in ENVS for sel in SELECTIONS]
        cls.snap = {c: parse_cell(path_of(*c).read_text(encoding="utf-8")) for c in cells}
        with tempfile.TemporaryDirectory() as tmp:
            r = Renderer(tmp)
            cls.base = json.loads(r.run(ENVS["debian-root"], "execute-template", "{{ .packages | toJson }}"))

            def status(env):
                out = r.run(ENVS[env], "execute-template", RESOLVE, "@@", MENU)
                res, menu = out.split("@@")
                return json.loads(res), menu

            def resolve(cell):
                data = dict(ENVS[cell[0]], tools=cls.snap[cell]["tools"])
                return json.loads(r.run(data, "execute-template", RESOLVE))

            with ThreadPoolExecutor() as pool:
                both = dict(zip(ENVS, pool.map(status, ENVS)))
                cls.status = {env: res for env, (res, _) in both.items()}
                cls.menus = {env: menu for env, (_, menu) in both.items()}
                cls.resolved = dict(zip(cells, pool.map(resolve, cells)))

    def known(self, env, aspect, item):
        return (env, aspect, item) in KNOWN

    # ===============================================================
    # 選單標註、預設組合、略過彙整讀判斷(#332)
    # ===============================================================
    def test_menu_labels_come_from_resolver(self):
        # 選單每一行:裝得了的標這台的裝法「[裝法]」(#335),不建議、裝不了的後面標「（label：原因）」,跟判斷一致
        for env, res in self.status.items():
            for line in self.menus[env].splitlines():
                name = line.split(" ")[0]
                entry = res["tools"][name]
                method = f" [{entry['method']}]" if entry["state"] != "unsupported" else ""
                mark = f"（{entry['label']}：{entry['reason']}）" if entry["state"] != "ok" else ""
                with self.subTest(env=env, tool=name):
                    self.assertTrue(line.endswith(method + mark), line)
                    if not mark:
                        self.assertNotRegex(line, "（(不建議|裝不了)：")
                    if not method:
                        self.assertNotRegex(line, r" \[[a-z]+\]")

    def test_menu_shows_this_machines_method(self):
        # #335:說明後面標這台會走的裝法;不建議的照樣標裝法再標原因,裝不了的只標原因
        def line(env, name):
            return next(l for l in self.menus[env].splitlines() if l.split(" ")[0] == name)
        self.assertEqual(line("debian-root", "fzf"), "fzf              模糊搜尋:Ctrl-R 找歷史、Ctrl-T 找檔案 [mise]")
        self.assertEqual(line("debian-root", "earlyoom"),
                         "earlyoom         記憶體快滿先砍最肥的程序；ssh、tailscale、ssm-agent 保有記憶體和 CPU [apt]")
        self.assertEqual(line("debian-root", "claude"), "claude           Claude Code CLI [official]")
        self.assertEqual(line("windows", "tailscale"), "tailscale        私人 VPN,連自己的機器 [winget]")
        self.assertEqual(line("darwin", "tailscale"), "tailscale        私人 VPN,連自己的機器 [cask]")
        self.assertEqual(line("android", "gh"), "gh               GitHub CLI(官方 apt 源),裝完 gh auth login [pkg]")
        self.assertEqual(line("wsl", "tailscale"), "tailscale        私人 VPN,連自己的機器 [official]（不建議：網路借 Windows "
                         "那份 Tailscale（mirrored），再裝一份會變成 tailnet 上兩個節點）")
        self.assertEqual(line("android", "claude"), "claude           Claude Code CLI（裝不了：官方沒有 Android 版，"
                         "npm 版也沒有 Android 的執行檔）")
        self.assertEqual(line("android", "codex"), "codex            Codex CLI [pkg]")
        self.assertEqual(line("darwin", "headless-chrome"), "headless-chrome  沒有畫面的 Chrome,給 agent 開網頁 [cask]")

    def test_menu_has_no_multichoice_separators(self):
        # ADR 0004:選單文字是 --promptMultichoice 的值,不能有半形 /、'、=
        for env, menu in self.menus.items():
            for line in menu.splitlines():
                with self.subTest(env=env, line=line):
                    self.assertFalse(set(line) & set("/'="))

    def test_unsupported_reason_is_a_rule_or_no_method_for_this_os(self):
        # 原因只在要解釋時才寫成規則(spec #315 user story 3、4):表上沒有這個 OS 的裝法、又沒有規則對到 →
        # 固定的「沒有這個環境的裝法」;有這個 OS 的裝法卻一個都用不了,要寫規則說為什麼(不由判斷照缺的條件組,#335)。
        # 沒有 root 的 headless-chrome、snapserver 也寫成規則
        for env, res in self.status.items():
            os_name = ENVS[env]["chezmoi"]["os"]
            for name, entry in res["tools"].items():
                if entry["state"] == "ok":
                    continue
                written = [r["reason"] for r in self.table["tools"][name].get("rules", [])]
                with self.subTest(env=env, tool=name):
                    if os_name in self.table["tools"][name]["install"]:
                        self.assertIn(entry["reason"], written)
                    else:
                        self.assertIn(entry["reason"], [*written, NO_METHOD])
        tools = self.status["debian-noroot"]["tools"]
        self.assertEqual({n: tools[n]["reason"] for n in ("headless-chrome", "snapserver")}, {
            "headless-chrome": "Chrome 要的系統函式庫只能用 apt 裝，沒有 root 用不了 apt",
            "snapserver": "沒有 root 用不了 apt，官方只出 .deb",
        })

    def test_full_preset_is_menu_minus_discouraged_and_unsupported(self):
        for env, res in self.status.items():
            want = [n for n in menu_tools() if res["tools"][n]["state"] == "ok"]
            with self.subTest(env=env):
                self.assertEqual(self.snap[env, "full"]["tools"], want)

    def test_skipped_is_ticked_and_unsupported(self):
        for (env, sel), res in self.resolved.items():
            want = sorted(n for n, t in res["tools"].items() if t["ticked"] and t["state"] == "unsupported")
            with self.subTest(env=env, sel=sel):
                self.assertEqual(sorted(self.snap[env, sel]["skipped"]), want)

    def test_noroot_apt_only_tools_say_why(self):
        # 決定(#315 2026-11-20):沒有 root 的 Debian 系,只能走 apt 的兩個標裝不了,原因只寫事實
        tools = self.status["debian-noroot"]["tools"]
        self.assertEqual({n: (tools[n]["state"], tools[n]["reason"]) for n in ("earlyoom", "snapclient")}, {
            "earlyoom": ("unsupported", "要 root：要改系統服務的記憶體設定"),
            "snapclient": ("unsupported", "沒有 root 用不了 apt，官方只出 .deb"),
        })
        # 有 root 照裝;原生 Termux 的 pkg 不用 root
        self.assertEqual(self.status["debian-root"]["tools"]["snapclient"]["state"], "ok")
        self.assertEqual(self.status["android"]["tools"]["snapclient"]["state"], "ok")

    def test_playwright_cli_follows_its_own_install_not_headless_chrome(self):
        # #349:playwright-cli 看自己的裝法(npm,要 Node),不跟 headless-chrome 綁:沒有本機 Chrome 也能
        # attach 遠端瀏覽器(#260)。Playwright 官方支援 WSL、macOS、arm64、非 Debian 系的 Linux 照 npm 裝
        # (fedora:42 容器實測 attach --cdp,見 #349 留言)。期望值照那份盤點,不從表推
        want = {"debian-root": "script", "debian-noroot": "script", "wsl": "script", "arm": "script",
                "non-debian": "script", "proot": "script", "darwin": "script", "windows": "mise"}
        for env, method in want.items():
            with self.subTest(env=env):
                res = self.status[env]["tools"]
                self.assertEqual((res["playwright-cli"]["state"], res["playwright-cli"]["method"]), ("ok", method))
        # 這幾台 headless-chrome 照樣裝不了:兩者真的拆開了(macOS 的 headless-chrome 由 #348 改走 brew cask)
        for env in ("debian-noroot", "wsl", "arm", "non-debian"):
            with self.subTest(env=env, tool="headless-chrome"):
                self.assertEqual(self.status[env]["tools"]["headless-chrome"]["state"], "unsupported")

    def test_playwright_cli_on_native_termux_says_playwright_rejects_android(self):
        # 原生 Termux 的 Node 平台是 android,playwright-core 只認 linux、darwin、win32,連 --version 都丟
        # Unsupported platform(termux-docker 實測,#349 留言)。原因寫這個事實,不寫 headless-chrome
        res = self.status["android"]["tools"]["playwright-cli"]
        self.assertEqual((res["state"], res["reason"]),
                         ("unsupported", "Playwright 只支援 Linux、macOS、Windows，原生 Termux 的 Node 一跑就報 "
                                         "Unsupported platform：android"))

    def test_noroot_skip_summary_prints_the_reason(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Renderer(tmp).run(dict(ENVS["debian-noroot"], tools=["earlyoom", "fzf"]), "execute-template",
                                    (ROOT / "home/.chezmoiscripts/run_onchange_after_record-env-skipped.sh.tmpl")
                                    .read_text(encoding="utf-8"))
        self.assertEqual(re.findall(r"^skip_env .*$", out, re.M), ["skip_env 'earlyoom' '要 root：要改系統服務的記憶體設定'"])

    def test_old_rules_and_lists_are_gone(self):
        # 裝法只寫在表上(#332、#336):舊的環境規則樣板(tool-env、tool-status)、apt 用不了的判斷(use-mise)、
        # 要不要 Node 的判斷(needs-node)刪了;套件清單檔只剩基本套件,沒有 toolPackages、miseTools、nodeTools、
        # nodeToolsSkip、nodePackages。沒有樣板、腳本、測試、文件再提到它們(docs/superpowers 是歷史紀錄)
        templates = ("tool-env", "tool-status", "use-mise", "needs-node")
        for name in templates:
            self.assertFalse((ROOT / "home/.chezmoitemplates" / name).exists(), name)
        self.assertEqual(sorted(self.base), ["darwin", "termux", "ubuntu", "windows"])
        names = (*templates, "toolPackages", "miseTools", "nodeTools", "nodePackages")
        pattern = re.compile(r"(?<![\w-])(" + "|".join(map(re.escape, names)) + r")(?![\w-])")
        files = [p for d in ("home", "script", "docs", ".github") for p in (ROOT / d).rglob("*")
                 if p.is_file() and not {"fixtures", "superpowers", "__pycache__"} & set(p.parts)]
        files += [ROOT / "AGENTS.md", ROOT / "GLOSSARY.md", ROOT / "README.md"]
        hits = [f"{p.relative_to(ROOT)}:{m.group(0)}" for p in files if p != Path(__file__).resolve()
                for m in pattern.finditer(p.read_text(errors="ignore"))]
        self.assertEqual(hits, [])

    def test_linux_only_tool_needs_no_reasons_for_other_oses(self):
        # 只寫 linux 裝法、沒有 rules 的假工具:其他 OS 自動裝不了,原因是固定的「沒有這個環境的裝法」,不用另寫規則
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src"
            shutil.copytree(ROOT / "home", src / "home", symlinks=True)
            shutil.copy(ROOT / ".chezmoiroot", src / ".chezmoiroot")
            with (src / "home/.chezmoidata/tool-table.yaml").open("a", encoding="utf-8") as f:
                f.write("    linuxonly:\n"
                        "      docs: https://example.com/linuxonly\n"
                        "      checked: 2026-11-20\n"
                        "      install: {linux: [mise]}\n"
                        "      mise: {tool: linuxonly}\n")
            with (src / "home/.chezmoitemplates/tool-menu").open("a", encoding="utf-8") as f:
                f.write("linuxonly 只有 Linux 裝法的假工具\n")
            (Path(tmp) / "r").mkdir()
            r = Renderer(Path(tmp) / "r", source=src)
            got = {env: json.loads(r.run(dict(ENVS[env], tools=["linuxonly"]), "execute-template", RESOLVE))
                   ["tools"]["linuxonly"] for env in ("debian-noroot", "darwin", "android", "windows")}
            menu = r.menu("darwin")
        self.assertEqual({e: (t["state"], t["method"], t["reason"]) for e, t in got.items()}, {
            "debian-noroot": ("ok", "mise", ""),
            "darwin": ("unsupported", "", "沒有這個環境的裝法"),
            "android": ("unsupported", "", "沒有這個環境的裝法"),
            "windows": ("unsupported", "", "沒有這個環境的裝法"),
        })
        self.assertRegex(menu, r"(?m)^linuxonly +只有 Linux 裝法的假工具（裝不了：沒有這個環境的裝法）$")

    def test_adding_a_tool_takes_a_table_entry_and_a_menu_line(self):
        # 照 .chezmoi.toml.tmpl 選單上方的說明加一個走既有裝法的假工具:只改表、加選單說明,
        # 選單、預設組合、各套件管理員與 mise 的清單就都有它
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src"
            shutil.copytree(ROOT / "home", src / "home", symlinks=True)
            shutil.copy(ROOT / ".chezmoiroot", src / ".chezmoiroot")
            with (src / "home/.chezmoidata/tool-table.yaml").open("a", encoding="utf-8") as f:
                f.write("    faketool:\n"
                        "      docs: https://example.com/faketool\n"
                        "      checked: 2026-11-20\n"
                        "      install: {linux: [apt, mise], darwin: [brew], android: [pkg], windows: [mise]}\n"
                        "      apt: [faketool-apt]\n      pkg: [faketool-pkg]\n      brew: [faketool-brew]\n"
                        "      mise: {tool: faketool-mise}\n")
            with (src / "home/.chezmoitemplates/tool-menu").open("a", encoding="utf-8") as f:
                f.write("faketool 測試用的假工具\n")
            (Path(tmp) / "r").mkdir()
            r = Renderer(Path(tmp) / "r", source=src)
            home = src / "home"
            pkgs = (home / ".chezmoiscripts/run_onchange_before_install-packages.sh.tmpl").read_text()
            darwin = (home / ".chezmoiscripts/run_onchange_before_install-packages-darwin.sh.tmpl").read_text()
            mise = (home / "dot_config/mise/conf.d/dotfiles.toml.tmpl").read_text()
            menu = r.menu("debian-root")
            self.assertRegex(menu, r"(?m)^faketool +測試用的假工具")
            config = r.init("debian-root", "full", menu)
            self.assertIn('"faketool"', config)

            def render(env, template):
                return r.run(dict(ENVS[env], tools=["faketool"]), "execute-template", template)

            self.assertRegex(render("debian-root", pkgs), r"(?m)^for pkg in .*\bfaketool-apt\b")
            self.assertIn('"faketool-mise" = "latest"', render("debian-noroot", mise))
            self.assertRegex(render("android", pkgs), r"(?m)^for pkg in .*\bfaketool-pkg\b")
            self.assertIn('brew "faketool-brew"', render("darwin", darwin))
            self.assertIn('"faketool-mise" = "latest"', render("windows", mise))

    # ===============================================================
    # 裝法:跟快照那一格實際渲染出的清單與腳本一致
    # ===============================================================
    def compare(self, env, aspect, want, got):
        """回傳差異說明(扣掉 KNOWN 的)。want、got 是集合。"""
        return [f"{env} {aspect}: {'多' if x in got else '少'} {x}" for x in sorted(want ^ got)
                if not self.known(env, aspect, x)]

    def test_installing_matches_tools_to_install(self):
        # tools-to-install 就是判斷的 install(#315 review):被連帶裝的 node 也算,消費端跟判斷不會各算一份
        diffs = []
        for (env, sel), res in self.resolved.items():
            got = {n for n, t in res["tools"].items() if t["install"]}
            diffs += self.compare(env, "installing", set(self.snap[env, sel]["installing"]), got)
        self.assertFalse(sorted(set(diffs)), "\n".join(sorted(set(diffs))))

    def test_package_lists_match_rendered_lists(self):
        diffs = []
        for (env, sel), res in self.resolved.items():
            snap, lists = self.snap[env, sel]["packages"], res["lists"]
            if env == "android":
                want = set(snap["apt/pkg"]) - set(self.base["termux"]) | set(snap.get("pkg(node)", []))
                diffs += self.compare(env, "pkg", want, set(lists["pkg"]))
            else:
                diffs += self.compare(env, "apt", set(snap["apt/pkg"]) - set(self.base["ubuntu"]),
                                      set(lists["apt"]) | set(lists["aptNeedsRoot"]))
            diffs += self.compare(env, "brew", set(snap["brew"]) - set(self.base["darwin"]["brews"]),
                                  set(lists["brew"]))
            diffs += self.compare(env, "cask", set(snap["brew cask"]), set(lists["cask"]))
            diffs += self.compare(env, "winget", set(snap["winget"]) - set(self.base["windows"]["winget"]),
                                  set(lists["winget"]))
        self.assertFalse(sorted(set(diffs)), "\n".join(sorted(set(diffs))))

    def test_mise_list_matches_rendered_list(self):
        diffs = []
        base = {f'"{t}" = "latest"' for t in self.base["windows"]["mise"]}
        for (env, sel), res in self.resolved.items():
            got = {mise_line(e) for e in res["lists"]["mise"]}
            diffs += self.compare(env, "mise", self.snap[env, sel]["mise"] - base, got)
        self.assertFalse(sorted(set(diffs)), "\n".join(sorted(set(diffs))))

    def test_install_scripts_match_rendered_scripts(self):
        diffs = []
        for (env, sel), res in self.resolved.items():
            scripts = self.snap[env, sel]["scripts"]
            for script, (tool, methods) in SCRIPT_METHODS.items():
                if script.endswith(".ps1.tmpl") != (env == "windows"):
                    continue
                entry = res["tools"][tool]
                want = scripts.get(script, False)
                got = entry["install"] and entry["method"] in methods
                if want != got and not self.known(env, f"script:{script}", tool):
                    diffs.append(f"{env}/{sel} {script}: 現在{'會' if want else '不'}跑,判斷 {tool} 走 "
                                 f"{entry['method'] or '裝不了'}")
            entry = res["tools"]["zsh"]
            if self.snap[env, sel]["zsh-bin"] != (entry["install"] and entry["method"] == "script"):
                diffs.append(f"{env}/{sel} zsh-bin:判斷 zsh 走 {entry['method']}")
        self.assertFalse(diffs, "\n".join(diffs))

    # ===============================================================
    # #333:清單只從判斷結果來,而且順序照判斷(基本套件在前)
    # ===============================================================
    def test_rendered_lists_are_base_then_resolver_lists_in_order(self):
        diffs = []
        for (env, sel), res in self.resolved.items():
            snap, lists, b = self.snap[env, sel]["packages"], res["lists"], self.base
            node = res["tools"]["node"]
            if env == "android":
                termux_node = node["packages"] if node["install"] and node["method"] == "pkg" else []
                want = {"apt/pkg": b["termux"] + [p for p in lists["pkg"] if p not in termux_node]}
                if termux_node:
                    want["pkg(node)"] = termux_node
            elif env in ("darwin", "windows", "non-debian"):
                want = {"apt/pkg": []}
            else:
                base = b["ubuntu"] if env != "debian-noroot" else [p for p in b["ubuntu"] if p != "jq"]
                want = {"apt/pkg": base + lists["apt"] + lists["aptNeedsRoot"]}
            want["brew"] = b["darwin"]["brews"] + lists["brew"] if env == "darwin" else []
            want["brew cask"] = b["darwin"]["casks"] + lists["cask"] if env == "darwin" else []
            want["winget"] = list(dict.fromkeys(b["windows"]["winget"] + lists["winget"])) if env == "windows" else []
            got = {k: v for k, v in snap.items() if k}
            want = {k: list(dict.fromkeys(v)) for k, v in want.items()}
            if got != want:
                diffs.append(f"{env}/{sel}: 快照 {got} ≠ 判斷 {want}")
        self.assertFalse(diffs, "\n".join(diffs))

    def test_rendered_mise_list_is_resolver_list_in_order(self):
        diffs = []
        for (env, sel), res in self.resolved.items():
            text = path_of(env, sel).read_text(encoding="utf-8")
            body = sections(text)["mise 清單"]
            got = body[body.index("[tools]") + 1:] if "[tools]" in body else []
            got = [l for l in got if l]
            want = [mise_line(e) for e in res["lists"]["mise"]]
            if env == "windows":
                want = [f'"{t}" = "latest"' for t in self.base["windows"]["mise"]] + want
            if got != want:
                diffs.append(f"{env}/{sel}: 快照 {got} ≠ 判斷 {want}")
        self.assertFalse(diffs, "\n".join(diffs))

    def test_mise_template_names_no_tool(self):
        # mise 清單樣板沒有針對單一工具的判斷(spec #315):表上的工具名一個都不出現
        text = (ROOT / "home/.chezmoitemplates/mise-tools").read_text(encoding="utf-8")
        code = re.sub(r"\{\{-? /\*.*?\*/ -?\}\}", "", text, flags=re.S)
        for name in self.table["tools"]:
            with self.subTest(tool=name):
                self.assertNotIn(f'"{name}"', code)

    def test_debian_noroot_snapserver_follows_table(self):
        # 盤點的 bug(#333):沒有 root 的 Debian 勾 snapserver,snapserver 與 ffmpeg 的 apt 套件被默默拿掉,
        # 卻照裝 uv、照跑 install-snapserver。改成照表:snapserver 走 apt 裝不了,它的依賴與腳本都不動
        snap = self.snap["debian-noroot", "snapserver"]
        self.assertEqual(self.resolved["debian-noroot", "snapserver"]["tools"]["snapserver"]["state"], "unsupported")
        self.assertEqual(snap["packages"]["apt/pkg"], ["git", "curl", "python3"])
        self.assertEqual(snap["mise"], set())
        self.assertFalse(snap["scripts"]["run_onchange_after_install-snapserver.sh.tmpl"])
        # 有 root 照舊:apt 裝 snapserver、ffmpeg,mise 裝 uv,跑 install-snapserver
        root = self.snap["debian-root", "snapserver"]
        self.assertEqual(root["packages"]["apt/pkg"], ["git", "curl", "jq", "python3", "snapserver", "ffmpeg"])
        self.assertEqual(root["mise"], {'"uv" = "latest"'})
        self.assertTrue(root["scripts"]["run_onchange_after_install-snapserver.sh.tmpl"])

    def test_libatomic_stays_in_apt_list_without_root(self):
        # 決定(#315 2026-11-20):依賴裝不了不擋 node,缺 libatomic1 照舊在執行時由套件腳本印手動指令
        for sel in ("node", "codegraph", "playwright-cli", "opencode", "wakatime", "full"):
            with self.subTest(sel=sel):
                self.assertEqual(self.snap["debian-noroot", sel]["packages"]["apt/pkg"][-1], "libatomic1")
        self.assertNotIn("earlyoom", self.snap["debian-noroot", "full"]["packages"]["apt/pkg"])
        self.assertNotIn("snapclient", self.snap["debian-noroot", "full"]["packages"]["apt/pkg"])

    def test_needs_node_matches_rendered_node(self):
        # Node 有沒有被連帶裝:Linux、macOS 看 install-node、Termux 看 pkg 的 nodejs-lts、Windows 看 mise 的 node
        for (env, sel), res in self.resolved.items():
            snap = self.snap[env, sel]
            want = {"android": bool(snap["packages"].get("pkg(node)")),
                    "windows": '"node" = "lts"' in snap["mise"]}.get(
                env, snap["scripts"].get("run_onchange_after_install-node.sh.tmpl", False))
            with self.subTest(env=env, sel=sel):
                self.assertEqual(res["needsNode"], want)

    def test_needs_uv_matches_rendered_uv(self):
        # uv 有沒有裝(勾了或被連帶):Linux、Windows 看 mise 的 uv、macOS 看 brew、Termux 看 pkg
        for (env, sel), res in self.resolved.items():
            snap = self.snap[env, sel]
            want = {"darwin": "uv" in snap["packages"]["brew"],
                    "android": "uv" in snap["packages"]["apt/pkg"]}.get(env, '"uv" = "latest"' in snap["mise"])
            with self.subTest(env=env, sel=sel):
                self.assertEqual(res["needsUv"], want)
                self.assertEqual(res["tools"]["uv"]["install"], want)

    # ===============================================================
    # runtime(#341):別的選裝工具要靠它才跑得起來、也能單獨勾。node、uv
    # ===============================================================
    def test_runtime_fields_list_oses(self):
        # needsNode、needsUv 同一種格式:非空、不重複的 OS 清單;只有這兩欄,對到的 runtime 在表上
        for name, tool in self.table["tools"].items():
            for field in (k for k in tool if k.startswith("needs")):
                with self.subTest(tool=name, field=field):
                    self.assertIn(field, RUNTIMES)
                    self.assertIn(RUNTIMES[field], self.table["tools"])
                    self.assertNotEqual(name, RUNTIMES[field])
                    oses = tool[field]
                    self.assertIsInstance(oses, list)
                    self.assertTrue(oses)
                    self.assertEqual(len(oses), len(set(oses)))
                    self.assertLessEqual(set(oses), {"linux", "darwin", "android", "windows"})

    def test_uv_is_a_runtime_on_the_menu(self):
        # #341(獨立的期望值):uv 能單獨勾,走 mise(macOS brew、Termux pkg,ADR 0005 的例外);
        # 不再是 snapserver 的依賴套件,改由 snapserver、agent-config 的 needsUv 連帶裝
        want = {"debian-root": "mise", "debian-noroot": "mise", "wsl": "mise", "arm": "mise", "non-debian": "mise",
                "proot": "mise", "darwin": "brew", "android": "pkg", "windows": "mise"}
        for env, method in want.items():
            with self.subTest(env=env):
                uv = self.resolved[env, "uv"]
                self.assertEqual((uv["tools"]["uv"]["state"], uv["tools"]["uv"]["method"]), ("ok", method))
                self.assertTrue(uv["needsUv"])
                self.assertEqual(self.snap[env, "uv"]["installing"], ["uv"])
                self.assertFalse(self.resolved[env, "minimal"]["needsUv"])
                self.assertNotIn("uv", self.snap[env, "minimal"]["tools"])
        self.assertNotIn("uv", self.table["tools"]["snapserver"].get("deps", {}))
        for env, sel in [("debian-root", "snapserver"), ("debian-root", "agent-config"), ("darwin", "agent-config"),
                         ("windows", "agent-config")]:
            with self.subTest(env=env, sel=sel):
                res = self.resolved[env, sel]
                self.assertFalse(res["tools"]["uv"]["ticked"])
                self.assertTrue(res["needsUv"])
                self.assertEqual(self.snap[env, sel]["installing"][-1], "uv")
        # 裝不了的工具不連帶:原生 Termux 的 agent-config、沒有 root 的 snapserver
        self.assertFalse(self.resolved["android", "agent-config"]["needsUv"])
        self.assertFalse(self.resolved["debian-noroot", "snapserver"]["needsUv"])

    def test_system_command_is_reused_without_root_like_mise_tools(self):
        # 快照的 PATH 什麼都找不到,system 裝法另外驗:沒有 root 的 Debian 系、系統已經有 vim
        with tempfile.TemporaryDirectory() as tmp:
            r = Renderer(tmp)
            (r.bin / "vim").symlink_to(r.bin / "sh")
            data = dict(ENVS["debian-noroot"], tools=["vim", "ffmpeg"])
            out = r.run(data, "execute-template", RESOLVE, "@@", (ROOT / "home/.chezmoitemplates/mise-tools").read_text())
            res, mise = out.split("@@")
            res = json.loads(res)
        self.assertEqual(res["tools"]["vim"]["method"], "system")
        self.assertEqual(res["tools"]["ffmpeg"]["method"], "mise")
        self.assertEqual({mise_line(e) for e in res["lists"]["mise"]}, set(filter(None, mise.splitlines())))

    # ===============================================================
    # init 時讀得到表(config 樣板讀不到 data 目錄,判斷改 include)
    # ===============================================================
    def test_resolves_at_init(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = json.loads(Renderer(tmp).run(ENVS["wsl"], "execute-template", "--init", RESOLVE))
        self.assertEqual(out["tools"]["headless-chrome"]["state"], "unsupported")
        self.assertEqual(out["tools"]["claude"]["official"]["url"], "https://claude.ai/install.sh")

    # ===============================================================
    # 表本身:跟選單一一對應、有官方文件與日期、原因能放進選單
    # ===============================================================
    def test_table_and_menu_list_the_same_tools(self):
        self.assertEqual(sorted(self.table["tools"]), sorted(menu_tools()))

    def test_every_tool_has_official_docs_and_checked_date(self):
        for name, tool in self.table["tools"].items():
            with self.subTest(tool=name):
                self.assertRegex(tool.get("docs", ""), r"^https://")
                self.assertRegex(str(tool.get("checked", "")), r"^\d{4}-\d{2}-\d{2}$")

    def test_reasons_are_menu_safe(self):
        # ADR 0004:原因接在選單文字後面,半形 / 會被 e2e 的 --promptMultichoice 切開,' 弄壞略過腳本的引號
        reasons = [r["reason"] for t in self.table["tools"].values() for r in t.get("rules", [])] + [NO_METHOD]
        self.assertTrue(reasons)
        for reason in reasons:
            with self.subTest(reason=reason):
                self.assertFalse(set(reason) & set("/'="))

    def test_not_written_yet_reasons_carry_an_issue(self):
        # 盤點(#315)找到「裝不了」其實是「還沒寫裝法」的(獨立的期望值,照盤點筆記列)
        # #348、#349 之後表上沒有「還沒寫裝法」的規則
        not_yet = set()
        for name, env in not_yet:
            with self.subTest(tool=name, env=env):
                rule = next(r for r in self.table["tools"][name]["rules"] if env in r["when"])
                self.assertIsInstance(rule.get("issue"), int)

    def test_issue_rules_only_match_where_no_install_method_works(self):
        # 帶 issue 的規則 = 「還沒寫裝法」:它對到的環境,拿掉所有規則時這個工具也一定沒有用得了的裝法。
        # 不然補了裝法之後,舊規則還是一直擋著(#309 的 herdr 就是這樣)
        no_rules = {"toolTable": {"tools": {n: {"rules": []} for n in self.table["tools"]}}}
        with tempfile.TemporaryDirectory() as tmp:
            r = Renderer(tmp)
            with ThreadPoolExecutor() as pool:
                bare = dict(zip(ENVS, pool.map(
                    lambda env: json.loads(r.run(dict(ENVS[env], **no_rules), "execute-template", RESOLVE)), ENVS)))
        checked = 0
        for name, tool in self.table["tools"].items():
            for rule in tool.get("rules", []):
                if "issue" not in rule:
                    continue
                for env in ENVS:
                    if not set(rule["when"]) & set(self.status[env]["env"]):
                        continue
                    checked += 1
                    with self.subTest(tool=name, env=env, when=rule["when"]):
                        self.assertEqual(bare[env]["tools"][name]["method"], "")
        # #348、#349 之後表上沒有帶 issue 的規則,checked 可以是 0;之後加了規則這裡就會檢查到

    def test_348_decisions(self):
        # #348 使用者的決定(2026-11-20,獨立的期望值):codex 在 Termux 走 pkg、headless-chrome 在 macOS 走 cask;
        # 其他確定裝不了,原因只寫查證過的事實,規則不再帶 issue
        installs = {("android", "codex"): "pkg", ("darwin", "headless-chrome"): "cask"}
        for (env, name), method in installs.items():
            with self.subTest(env=env, tool=name):
                entry = self.status[env]["tools"][name]
                self.assertEqual((entry["state"], entry["method"]), ("ok", method))
        self.assertEqual(self.table["tools"]["codex"]["pkg"], ["codex"])
        self.assertEqual(self.table["tools"]["headless-chrome"]["cask"], ["google-chrome"])
        unsupported = {
            ("android", "claude"): "官方沒有 Android 版，npm 版也沒有 Android 的執行檔",
            ("android", "opencode"): "官方沒有 Android 版，npm 版限定 macOS、Linux、Windows，Termux 的 npm 拒裝",
            ("android", "herdr"): "官方 installer 擋 Android，release 沒有 Android 版，npm 上的 herdr 是佔名的空套件",
            ("android", "codegraph"): "官方沒有 Android 版；npm 版裝得上，但執行時要下載 Android 版，release 沒有",
            ("android", "bottom"): "termux-packages 沒有 bottom，到 proot Ubuntu 裝",
            ("android", "code-server"): "官方的 Termux 裝法要另加 TUR 套件庫",
            ("non-debian", "earlyoom"): "earlyoom 走 apt，只能裝在 Debian 系",
            ("non-debian", "snapclient"): "snapclient 走 apt，只能裝在 Debian 系",
            ("non-debian", "snapserver"): "snapserver 走 apt，只能裝在 Debian 系",
            ("non-debian", "headless-chrome"): ".deb 只能裝在 Debian 系",
        }
        for (env, name), reason in unsupported.items():
            with self.subTest(env=env, tool=name):
                entry = self.status[env]["tools"][name]
                self.assertEqual((entry["state"], entry["reason"]), ("unsupported", reason))
                rule = next(r for r in self.table["tools"][name]["rules"] if r["reason"] == reason)
                self.assertNotIn("issue", rule)

    def test_issue_rules_point_at_the_open_tracking_issue(self):
        # 「還沒寫裝法」曾追蹤在 #348(spec #315 收尾時開的),#348、#349 之後一條都不剩。
        # 之後再加,issue 要指向開著的追蹤單:這裡改成那張的編號
        issues = {r["issue"] for t in self.table["tools"].values() for r in t.get("rules", []) if "issue" in r}
        self.assertEqual(issues, set())

    def test_every_install_method_is_a_known_method(self):
        methods = set(self.table["methods"])
        for name, tool in self.table["tools"].items():
            for owner, spec in [(name, tool), *((f"{name}.{d}", s) for d, s in tool.get("deps", {}).items())]:
                for os_name, order in spec["install"].items():
                    with self.subTest(tool=owner, os=os_name):
                        self.assertIn(os_name, ("linux", "darwin", "android", "windows"))
                        self.assertLessEqual(set(order), methods)
                        # 用到的套件管理員要寫套件名
                        for m in set(order) & {"apt", "pkg", "brew", "cask", "winget", "mise"}:
                            self.assertTrue(spec.get(m), f"{owner} 用 {m} 卻沒寫 {m} 欄")


if __name__ == "__main__":
    unittest.main()
