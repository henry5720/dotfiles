#!/usr/bin/env python3
"""渲染快照(#329,spec #315 的 Testing Decisions):環境 × 勾選組合的渲染結果存進 repo,每次改動跟它一字不差。

重新產生(刻意改了行為時,同一個 PR 更新快照並寫明哪幾格、為什麼):

    UPDATE_SNAPSHOT=1 python3 -m unittest script/tests/test_render_snapshot.py

快照在 script/tests/fixtures/render-snapshot/<環境>/<勾選>.txt,一格一個檔,`git diff` 就看得出改了哪幾格。
每格記下:選單(含不建議／裝不了的標註)、init 存下的設定(用途與 tools,即預設組合)、要裝與略過的工具、
套件清單(apt／pkg、brew、winget,從渲染出來的腳本抽出)、mise 清單、這台會管的腳本裡渲染成非空的那些與內容
(渲染成空的只列名字)。

環境用 --override-data 模擬(同 test_tool_status.py、test_windows.py),在 Linux 上直接渲染,不用容器。
跟這台裝了什麼無關:
- PATH 只放 sh、ls、awk(home-owner-guard 要後兩個,不然 output 失敗),所以樣板的 lookPath(sudo、tailscale、
  選裝工具表 system 裝法的系統指令)一律找不到;node-runnable 的 `ldconfig -p | grep` 沒有 grep,libatomic 一律算沒有
  (只有 Debian 系有 root 算有)。
  shebang 的 lookPath "sh" 在快照裡寫成 @BIN@/sh。
- 有沒有 root 只看 .chezmoi.uid(root 的格子給 0,其他給 1000,這時找不到 sudo 就是沒有 root)。
- isProot 直接給(proot 為 true,其他 false),不讀這台的 /proc/version。
- 家目錄固定是不存在的 /home/snapshot。
"""
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# 用檔案路徑跑(重新產生那行)時,sys.path 沒有這個目錄
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_tool_status import SECRETS, TOOLS_PROMPT, USE_PROMPT, merge  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT = ROOT / "script/tests/fixtures/render-snapshot"
CHEZMOI = shutil.which("chezmoi")
HOME = "/home/snapshot"
MISE_LIST = ROOT / "home/dot_config/mise/conf.d/dotfiles.toml.tmpl"

# ===============================================================
# 環境矩陣
# ===============================================================
_UBUNTU = {"os": "linux", "arch": "amd64", "uid": "0", "kernel": {"osrelease": "6.8.0-1-generic"},
           "osRelease": {"id": "ubuntu", "idLike": "debian"}}
ENVS = {
    "debian-root": {"chezmoi": _UBUNTU, "isProot": False},
    "debian-noroot": {"chezmoi": _UBUNTU | {"uid": "1000"}, "isProot": False},
    "non-debian": {"chezmoi": _UBUNTU | {"osRelease": {"id": "fedora", "idLike": ""}}, "isProot": False},
    "wsl": {"chezmoi": _UBUNTU | {"kernel": {"osrelease": "5.15.167.4-microsoft-standard-WSL2"}}, "isProot": False},
    "arm": {"chezmoi": _UBUNTU | {"arch": "arm64"}, "isProot": False},
    # proot Ubuntu:userland 是 Ubuntu,kernel 是 Android 的
    "proot": {"chezmoi": _UBUNTU | {"arch": "arm64", "kernel": {"osrelease": "5.15.123-android14-11-g0a1b2c3d4e5f"}},
              "isProot": True},
    "darwin": {"chezmoi": {"os": "darwin", "arch": "arm64", "uid": "501", "kernel": {"osrelease": "24.1.0"},
                           "osRelease": {}}},
    "android": {"chezmoi": {"os": "android", "arch": "arm64", "uid": "10234",
                            "kernel": {"osrelease": "5.15.123-android14-11-g0a1b2c3d4e5f"}, "osRelease": {}}},
    # 真的 Windows 沒有 kernel 欄位(同 test_windows.py)
    "windows": {"chezmoi": {"os": "windows", "arch": "amd64", "uid": "1000", "kernel": {"osrelease": ""},
                            "osRelease": {}}},
}

# ===============================================================
# 勾選組合:用途的預設組合,加全部勾、各別勾跨裝法或有依賴的工具
# ===============================================================
SINGLES = ["snapserver", "snapclient", "headless-chrome", "playwright-cli", "claude", "codex", "opencode",
           "herdr", "node", "uv", "codegraph", "tailscale", "agent-config", "wakatime",
           "windows-mcp", "openssh-server"]
SELECTIONS = ["full", "minimal", "all", *SINGLES]


def cells():
    return [(env, sel) for env in ENVS for sel in SELECTIONS]


class Renderer:
    """在一個暫存目錄裡跑 chezmoi:PATH 只有 sh、家目錄固定、每次呼叫各用一份 state。"""

    def __init__(self, tmp, source=ROOT):
        self.tmp = Path(tmp)
        self.source = Path(source)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        for cmd in ("sh", "ls", "awk"):
            (self.bin / cmd).symlink_to(shutil.which(cmd))
        self.config = self.tmp / "none.toml"
        self.config.write_text("", encoding="utf-8")

    def run(self, data, *args, stdin=None):
        data = merge(data, {"chezmoi": {"homeDir": HOME}})
        fd, state = tempfile.mkstemp(dir=self.tmp, suffix=".boltdb")
        os.close(fd)
        os.unlink(state)
        proc = subprocess.run([
            CHEZMOI, "--no-tty", "--source", str(self.source), "--config", str(self.config),
            "--destination", HOME, "--persistent-state", state,
            "--refresh-externals=never",
            "--override-data", json.dumps(data), *args,
        ], input=stdin, capture_output=True, text=True,
            env={"PATH": str(self.bin), "HOME": str(self.tmp), "LANG": "C.UTF-8"})
        if proc.returncode:
            raise RuntimeError(f"chezmoi {args[0]} 失敗({json.dumps(data, ensure_ascii=False)}):\n{proc.stderr}")
        return proc.stdout.replace(str(self.bin), "@BIN@")

    def menu(self, env):
        return self.run(ENVS[env], "execute-template", '{{ includeTemplate "tool-menu-labels" . }}')

    def init(self, env, selection, menu):
        """全新機器跑 config 樣板,回傳渲染出的 config。"""
        flags = [*SECRETS]
        if selection in ("full", "minimal"):
            flags += ["--promptChoice", f"{USE_PROMPT}={selection[0]}"]
        else:
            labels = menu.splitlines()
            if selection != "all":
                labels = [l for l in labels if l.split(" ")[0] == selection]
            flags += ["--promptChoice", f"{USE_PROMPT}=c",
                      "--promptMultichoice", f"{TOOLS_PROMPT}={'/'.join(labels)}"]
        template = (self.source / "home/.chezmoi.toml.tmpl").read_text(encoding="utf-8")
        return self.run(ENVS[env], "execute-template", "--init", *flags, stdin=template)

    def cell(self, env, selection, menu):
        config = self.init(env, selection, menu)
        data = merge(ENVS[env], tomllib.loads(config).get("data", {}))
        scripts = self.run(data, "managed", "--include", "scripts", "--path-style", "source-relative").split()
        # 一次呼叫渲染全部:execute-template 的多個參數直接接在一起輸出,中間插分隔行
        parts = {
            "tools-to-install": '{{ includeTemplate "tools-to-install" . }}',
            "tools-skipped": '{{ includeTemplate "tools-skipped" . }}',
            "mise": MISE_LIST.read_text(encoding="utf-8"),
            **{s: (ROOT / "home" / s).read_text(encoding="utf-8") for s in scripts},
        }
        args = []
        for i, (name, template) in enumerate(parts.items()):
            args += [f"@@SNAPSHOT-PART-{i}@@", template]
        out = self.run(data, "execute-template", *args)
        rendered = dict(zip(parts, re.split(r"@@SNAPSHOT-PART-\d+@@", out)[1:]))
        return format_cell(env, selection, menu, config, rendered, scripts)


def package_lists(rendered):
    """從渲染出來的套件腳本抽出清單(看得到清單有沒有變,不用讀整支腳本)。"""
    lines = []
    sh = rendered.get(".chezmoiscripts/run_onchange_before_install-packages.sh.tmpl", "")
    m = re.search(r"^for pkg in (.*); do$", sh, re.M)
    lines.append("apt/pkg: " + (m.group(1) if m else ""))
    m = re.search(r'^command -v node .*missing="\$missing (.*)"$', sh, re.M)
    if m:
        lines.append("pkg(node): " + m.group(1))
    darwin = rendered.get(".chezmoiscripts/run_onchange_before_install-packages-darwin.sh.tmpl", "")
    lines.append("brew: " + " ".join(re.findall(r'^brew "(.+)"$', darwin, re.M)))
    lines.append("brew cask: " + " ".join(re.findall(r'^brew install --cask "(.+)" \|\|$', darwin, re.M)))
    win = rendered.get(".chezmoiscripts/run_onchange_before_install-packages-windows.ps1.tmpl", "")
    m = re.search(r"^\$ids = @\((.*?)^\)", win, re.M | re.S)
    lines.append("winget: " + " ".join(re.findall(r"'([^']+)'", m.group(1)) if m else []))
    return "\n".join(lines)


def format_cell(env, selection, menu, config, rendered, scripts):
    nonempty = [s for s in scripts if rendered[s].strip()]
    empty = [s for s in scripts if not rendered[s].strip()]
    out = [f"# 環境 {env} × 勾選 {selection}",
           "", "## 選單", menu.rstrip("\n"),
           "", "## init 存下的設定", config.rstrip("\n"),
           "", "## 要裝", rendered["tools-to-install"],
           "", "## 略過(裝不了)", rendered["tools-skipped"],
           "", "## 套件清單", package_lists(rendered),
           "", "## mise 清單", rendered["mise"].rstrip("\n"),
           "", "## 渲染成空的腳本", *empty,
           "", "## 會跑的腳本", *nonempty]
    for s in nonempty:
        out += ["", f"### {s}", rendered[s].rstrip("\n")]
    return "\n".join(out) + "\n"


def render_all():
    """回傳 {(環境, 勾選): 快照文字}。"""
    with tempfile.TemporaryDirectory() as tmp:
        r = Renderer(tmp)
        # managed 會把 externals 抓進共用的 ~/.cache/chezmoi;先單獨跑一次填好快取,
        # 之後並行的只讀(--refresh-externals=never),不然同時寫快取會讀到一半(unexpected EOF)
        r.run(ENVS[next(iter(ENVS))], "managed", "--include", "scripts")
        with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
            menus = dict(zip(ENVS, pool.map(r.menu, ENVS)))
            texts = pool.map(lambda c: r.cell(*c, menus[c[0]]), cells())
            return dict(zip(cells(), texts))


def path_of(env, selection):
    return SNAPSHOT / env / f"{selection}.txt"


class RenderSnapshotTest(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls):
        cls.got = render_all()
        if os.environ.get("UPDATE_SNAPSHOT"):
            shutil.rmtree(SNAPSHOT, ignore_errors=True)
            for (env, sel), text in cls.got.items():
                path_of(env, sel).parent.mkdir(parents=True, exist_ok=True)
                path_of(env, sel).write_text(text, encoding="utf-8")

    # ===============================================================
    # 每一格跟快照一字不差
    # ===============================================================
    def test_every_cell_matches_snapshot(self):
        failed = []
        for (env, sel), text in self.got.items():
            path = path_of(env, sel)
            want = path.read_text(encoding="utf-8") if path.exists() else ""
            if text != want:
                diff = difflib.unified_diff(want.splitlines(), text.splitlines(), str(path.relative_to(ROOT)),
                                            "現在渲染", lineterm="", n=2)
                failed.append(f"格子 {env}/{sel} 不一樣:\n" + "\n".join(diff))
        self.assertFalse(failed, "\n\n".join(failed) + "\n\n刻意改的話:UPDATE_SNAPSHOT=1 python3 -m unittest "
                                                      "script/tests/test_render_snapshot.py")

    def test_no_stale_cells(self):
        on_disk = {(p.parent.name, p.stem) for p in SNAPSHOT.glob("*/*.txt")}
        self.assertEqual(on_disk, set(self.got))

    # ===============================================================
    # 快照有抓到該抓的(獨立的期望值,防止快照本身空掉)
    # ===============================================================
    def test_cells_capture_known_results(self):
        g = self.got
        self.assertIn("apt/pkg: ", g["debian-root", "snapserver"])
        self.assertRegex(g["debian-root", "snapserver"], r"apt/pkg: .*\bsnapserver\b")
        self.assertRegex(g["darwin", "full"], r'brew: .*\beza\b')
        self.assertRegex(g["windows", "tailscale"], r"winget: .*Tailscale\.Tailscale")
        self.assertIn('"npm:opencode-ai"', g["windows", "opencode"])
        self.assertIn("### .chezmoiscripts/run_onchange_after_install-official.sh.tmpl", g["debian-root", "claude"])
        self.assertIn("## 略過(裝不了)\nheadless-chrome\n", g["wsl", "headless-chrome"])
        self.assertIn("headless-chrome  沒有畫面的 Chrome,給 agent 開網頁（裝不了：", g["wsl", "full"])

    # ===============================================================
    # 沒有 root 的略過訊息只寫事實(#339):略過什麼、缺什麼、為什麼要 root、對應的指令,不叫人去找 root
    # ===============================================================
    def assert_facts_only(self, text, where):
        for bad in ("有 root 的人", "請管理員", "要他停", "手動方式"):
            self.assertNotIn(bad, text, f"{where}:略過訊息只寫事實,不要「{bad}」")

    def test_no_root_skip_messages_state_facts_and_command(self):
        all_cells = "\n".join(t for (env, _), t in self.got.items() if env == "debian-noroot")
        calls = re.findall(r"^[ \t]*skip_root .*$", all_cells, re.M)
        self.assertTrue(calls)
        self.assert_facts_only("\n".join(calls), "skip_root 呼叫")
        header = re.findall(r"^[ \t]*echo \"== 沒有 root.*$", all_cells, re.M)
        self.assertTrue(header)
        self.assert_facts_only("\n".join(header), "略過彙整標題")
        # 獨立的期望值:要 apt 的兩項都附上 apt 的指令(Node 缺 libatomic 從 #342 起是選裝工具表的規則,不走 skip_root)
        for what, cmd in (("系統套件", "sudo apt-get install -y"), ("ssh", "sudo apt-get install -y openssh-client")):
            with self.subTest(what=what):
                self.assertTrue([c for c in calls if f"skip_root {what} " in c and cmd in c], calls)

    def test_no_root_disable_system_service_states_facts(self):
        # 沒有 root 的格子不裝 snapserver,這支分支快照裡看不到,單獨渲染
        with tempfile.TemporaryDirectory() as tmp:
            out = Renderer(tmp).run(ENVS["debian-noroot"], "execute-template",
                                    '{{ includeTemplate "sh-disable-system-service" (dict "root" . "service" "snapserver"'
                                    ' "done" "x" "why" "它監聽所有網卡") }}')
        call = re.findall(r"^[ \t]*skip_root .*$", out, re.M)
        self.assertEqual(len(call), 1, out)
        self.assert_facts_only(call[0], "停用系統服務")
        self.assertIn("sudo systemctl disable --now snapserver", call[0])


if __name__ == "__main__":
    unittest.main()
