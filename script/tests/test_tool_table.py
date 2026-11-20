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
from test_tool_env import menu_tools  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RESOLVE = '{{ includeTemplate "tool-install" . }}'
MENU = '{{ includeTemplate "tool-menu-labels" . }}'
TABLE = '{{ include ".chezmoidata/tool-table.yaml" | fromYaml | toJson }}'


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
        self.assertEqual(line("android", "claude"), "claude           Claude Code CLI（裝不了：官方 installer 沒有原生 "
                         "Termux 版，到 proot Ubuntu 裝）")

    def test_menu_has_no_multichoice_separators(self):
        # ADR 0004:選單文字是 --promptMultichoice 的值,不能有半形 /、'、=
        for env, menu in self.menus.items():
            for line in menu.splitlines():
                with self.subTest(env=env, line=line):
                    self.assertFalse(set(line) & set("/'="))

    def test_every_unsupported_reason_is_written_in_the_table(self):
        # 原因只來自表上的 rules,不由判斷照缺的條件組(#335);沒有 root 的 headless-chrome、snapserver 也寫成規則
        for env, res in self.status.items():
            for name, entry in res["tools"].items():
                if entry["state"] == "ok":
                    continue
                with self.subTest(env=env, tool=name):
                    self.assertIn(entry["reason"], [r["reason"] for r in self.table["tools"][name].get("rules", [])])
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
        diffs = []
        for (env, sel), res in self.resolved.items():
            got = {n for n, t in res["tools"].items() if t["ticked"] and t["install"]}
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
        reasons = [r["reason"] for t in self.table["tools"].values() for r in t.get("rules", [])]
        self.assertTrue(reasons)
        for reason in reasons:
            with self.subTest(reason=reason):
                self.assertFalse(set(reason) & set("/'="))

    def test_not_written_yet_reasons_carry_an_issue(self):
        # 盤點(#315)找到「裝不了」其實是「還沒寫裝法」的(獨立的期望值,照盤點筆記列)
        not_yet = {("headless-chrome", "darwin"), ("headless-chrome", "non-debian"), ("playwright-cli", "darwin"),
                   ("snapserver", "non-debian"), ("snapclient", "non-debian"), ("earlyoom", "non-debian"),
                   ("code-server", "android"), ("bottom", "android"), ("codegraph", "android"),
                   ("claude", "android"), ("codex", "android"), ("opencode", "android"), ("herdr", "android")}
        for name, env in not_yet:
            with self.subTest(tool=name, env=env):
                rule = next(r for r in self.table["tools"][name]["rules"] if env in r["when"])
                self.assertIsInstance(rule.get("issue"), int)

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
