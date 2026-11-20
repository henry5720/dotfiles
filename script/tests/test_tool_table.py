#!/usr/bin/env python3
"""選裝工具表與裝法判斷(#331,spec #315):表 home/.chezmoidata/tool-table.yaml、判斷 home/.chezmoitemplates/tool-install。

選單標註、預設組合、略過彙整已經讀判斷(#332);套件清單、mise 清單、腳本還沒(#333～#336),這裡拿判斷跟它們比:
- 狀態與原因:選單、完整的預設組合、略過清單跟判斷一致
- 裝法:跟渲染快照(#329)那一格實際渲染出的套件清單、mise 清單、會跑的腳本一致

快照每一格跟現在的樣板一字不差(test_render_snapshot.py 擋),所以「跟快照比」就是「跟現在渲染出的比」。
環境、PATH、家目錄沿用 test_render_snapshot 的 Renderer(lookPath 一律找不到)。
"""
import json
import re
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
# #332 起選單、預設組合、略過讀判斷,沒有 root 的 earlyoom、snapclient、snapserver、headless-chrome 經 tools-to-install
# 一起不裝了,剩下的是依賴套件:
KNOWN = {
    ("debian-noroot", "apt", "libatomic1"): "#333:沒有 root 時 apt 用不了,依賴套件不列進 apt 清單"
                                            "(缺 libatomic 維持在執行時判斷,#315 2026-11-20 決定)",
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
        # 選單每一行:不建議、裝不了的後面標「（label：原因）」,跟判斷一致
        for env, res in self.status.items():
            for line in self.menus[env].splitlines():
                name = line.split(" ")[0]
                entry = res["tools"][name]
                mark = f"（{entry['label']}：{entry['reason']}）" if entry["state"] != "ok" else ""
                with self.subTest(env=env, tool=name):
                    if mark:
                        self.assertTrue(line.endswith(mark), line)
                    else:
                        self.assertNotRegex(line, "（(不建議|裝不了)：")

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

    def test_tool_env_is_gone(self):
        # 環境規則只剩表上的 rules:舊的 tool-env、tool-status 刪了,沒有樣板或測試再讀它們
        for name in ("tool-env", "tool-status"):
            self.assertFalse((ROOT / "home/.chezmoitemplates" / name).exists(), name)
        pattern = re.compile(r'include(Template)? "(tool-env|tool-status)"')
        hits = [str(p.relative_to(ROOT)) for d in ("home", "script") for p in (ROOT / d).rglob("*")
                if p.is_file() and "fixtures" not in p.parts and pattern.search(p.read_text(errors="ignore"))]
        self.assertEqual(hits, [])

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
                diffs += self.compare(env, "apt", set(snap["apt/pkg"]) - set(self.base["ubuntu"]), set(lists["apt"]))
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
        reasons += [n["reason"] for n in self.table["needs"].values()]
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
