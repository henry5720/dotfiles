#!/usr/bin/env python3
"""官方 installer 照選裝工具表跑(#334,spec #315):Linux、macOS 一支 sh,Windows 一支 ps1。

只看渲染出來的腳本(--override-data 模擬環境,同 test_tool_env.py、test_windows.py),不看判斷樣板內部。
期望值(網址、參數、跳過條件)是 #334 之前各自那支腳本寫的,獨立於表,不從表算。
跟這台裝了什麼無關:PATH 只放 sh、ls、awk(同 test_render_snapshot.py),sudo、code-server 一律找不到。
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "home/.chezmoiscripts/run_onchange_after_install-official.sh.tmpl"
PS1 = ROOT / "home/.chezmoiscripts/run_onchange_after_install-official.ps1.tmpl"
CHEZMOI = shutil.which("chezmoi")

UBUNTU = {"os": "linux", "arch": "amd64", "uid": "0", "kernel": {"osrelease": "6.8.0-1-generic"},
          "osRelease": {"id": "ubuntu", "idLike": "debian"}}
NOROOT = UBUNTU | {"uid": "1000"}
DARWIN = {"os": "darwin", "arch": "arm64", "uid": "501", "kernel": {"osrelease": "24.1.0"}, "osRelease": {}}
ANDROID = {"os": "android", "arch": "arm64", "uid": "10234", "kernel": {"osrelease": "5.15.123-android14"},
           "osRelease": {}}
WINDOWS = {"os": "windows", "arch": "amd64", "uid": "1000", "kernel": {"osrelease": ""}, "osRelease": {}}

# #334 之前各自那支 sh 跑的:已安裝的判斷、跑 installer 的那一行(下載到 $tmp/<工具>.sh)
SH_EXPECT = {
    "claude": ('command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]',
               "https://claude.ai/install.sh", 'bash "$tmp/claude.sh"'),
    "code-server": ("command -v code-server >/dev/null 2>&1",
                    "https://code-server.dev/install.sh", 'sh "$tmp/code-server.sh"'),
    "codex": ('command -v codex >/dev/null 2>&1 || [ -x "$HOME/.local/bin/codex" ]',
              "https://chatgpt.com/codex/install.sh",
              'CODEX_NON_INTERACTIVE="1" PATH="$HOME/.local/bin:$PATH" bash "$tmp/codex.sh"'),
    "herdr": ("command -v herdr >/dev/null 2>&1", "https://herdr.dev/install.sh", 'sh "$tmp/herdr.sh"'),
    "opencode": ('command -v opencode >/dev/null 2>&1 || [ -x "$HOME/.opencode/bin/opencode" ]',
                 "https://opencode.ai/install", 'bash "$tmp/opencode.sh" --no-modify-path'),
}
PS1_EXPECT = {
    "claude": ("https://claude.ai/install.ps1", r"Join-Path $HOME '.local\bin\claude.exe'"),
    "codex": ("https://chatgpt.com/codex/install.ps1",
              r"Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'"),
}


class OfficialInstallerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.source = ROOT
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        for cmd in ("sh", "ls", "awk"):
            (self.bin / cmd).symlink_to(shutil.which(cmd))

    def tearDown(self):
        self.tmp.cleanup()

    def render(self, template, env, tools):
        data = {"chezmoi": env | {"homeDir": "/home/t"}, "tools": tools, "isProot": False}
        return subprocess.run([
            CHEZMOI, "--no-tty", "--source", str(self.source), "--config", str(self.dir / "none.toml"),
            "--persistent-state", str(self.dir / "state.boltdb"), "--override-data", json.dumps(data),
            "execute-template", template.read_text(encoding="utf-8"),
        ], stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True,
            env={"PATH": str(self.bin), "HOME": str(self.dir), "LANG": "C.UTF-8"}).stdout

    def assert_sh(self, text):
        path = self.dir / "s.sh"
        path.write_text(text, encoding="utf-8")
        subprocess.run(["sh", "-n", str(path)], check=True)

    # ===============================================================
    # sh:Linux、macOS
    # ===============================================================
    def test_sh_runs_each_ticked_tool_like_before(self):
        for env_name, env in (("linux", UBUNTU), ("darwin", DARWIN)):
            for tool, (installed, url, run) in SH_EXPECT.items():
                if env_name == "darwin" and tool == "code-server":
                    continue  # macOS 走 brew
                with self.subTest(env=env_name, tool=tool):
                    out = self.render(SH, env, [tool])
                    self.assert_sh(out)
                    self.assertTrue(out.startswith("#!"))
                    self.assertIn("set -eu", out)
                    self.assertIn(f"if {installed}; then", out)
                    self.assertIn(f'curl -fsSL -o "$tmp/{tool}.sh" {url}\n', out)
                    self.assertIn(f"  {run}\n", out)
                    # 跳過判斷在下載之前
                    self.assertLess(out.index(installed), out.index(url))
                    others = [u for t, (_, u, _) in SH_EXPECT.items() if t != tool]
                    self.assertFalse([u for u in others if u in out])

    def test_sh_keeps_alphabetical_order_of_the_old_scripts(self):
        out = self.render(SH, UBUNTU, list(SH_EXPECT))
        self.assert_sh(out)
        pos = [out.index(url) for _, url, _ in SH_EXPECT.values()]
        self.assertEqual(pos, sorted(pos))

    def test_sh_empty_when_nothing_to_run(self):
        cases = (("linux", UBUNTU, []), ("linux", UBUNTU, ["gh", "vim", "tailscale", "agent-config"]),
                 # code-server 沒有 root 走 mise、macOS 走 brew
                 ("noroot", NOROOT, ["code-server"]), ("darwin", DARWIN, ["code-server"]),
                 ("android", ANDROID, list(SH_EXPECT)), ("windows", WINDOWS, list(SH_EXPECT)))
        for name, env, tools in cases:
            with self.subTest(env=name, tools=tools):
                self.assertEqual(self.render(SH, env, tools).strip(), "")

    def test_url_comes_from_the_table(self):
        source = self.dir / "src"
        subprocess.run(["cp", "-r", str(ROOT / "home"), str(source)], check=True)
        table = source / ".chezmoidata/tool-table.yaml"
        text = table.read_text(encoding="utf-8")
        table.write_text(text.replace("https://herdr.dev/install.sh", "https://example.com/herdr.sh")
                         .replace("https://claude.ai/install.ps1", "https://example.com/claude.ps1"),
                         encoding="utf-8")
        self.source = source
        self.assertIn("https://example.com/herdr.sh", self.render(SH, UBUNTU, ["herdr"]))
        self.assertIn("https://example.com/claude.ps1", self.render(PS1, WINDOWS, ["claude"]))

    # ===============================================================
    # ps1:Windows
    # ===============================================================
    def test_ps1_runs_each_ticked_agent_like_before(self):
        for tool, (url, exe) in PS1_EXPECT.items():
            with self.subTest(tool=tool):
                out = self.render(PS1, WINDOWS, [tool])
                self.assertTrue(out.isascii(), [l for l in out.splitlines() if not l.isascii()][:3])
                self.assertIn(f"if (Test-Path ({exe})) {{", out)
                self.assertIn(f"Invoke-WebRequest -Uri '{url}' -OutFile $installer", out)
                self.assertLess(out.index("Test-Path"), out.index(url))
                # 失敗印手動指令(base64 的中文訊息裡帶網址),不中斷 apply
                self.assertIn(f"'{url}')", out)
                self.assertTrue(out.rstrip().endswith("exit 0"))
                self.assertNotIn("| iex", out.replace("irm {1} | iex", ""))

    def test_ps1_codex_non_interactive_and_both_agents_in_one_script(self):
        out = self.render(PS1, WINDOWS, ["claude", "codex"])
        self.assertTrue(out.isascii())
        claude, codex = PS1_EXPECT["claude"][0], PS1_EXPECT["codex"][0]
        self.assertLess(out.index(claude), out.index(codex))
        self.assertLess(out.index("$env:CODEX_NON_INTERACTIVE = '1'"), out.rindex("& $installer"))
        self.assertLess(out.index(codex), out.index("$env:CODEX_NON_INTERACTIVE = '1'"))
        # 已安裝時不能整支 exit:後面的工具還要跑
        self.assertEqual(out.count("exit 0"), 1)

    def test_ps1_empty_when_nothing_to_run(self):
        for name, env, tools in (("windows", WINDOWS, []), ("windows", WINDOWS, ["herdr", "opencode", "agent-config"]),
                                 ("linux", UBUNTU, list(PS1_EXPECT))):
            with self.subTest(env=name, tools=tools):
                self.assertEqual(self.render(PS1, env, tools).strip(), "")


if __name__ == "__main__":
    unittest.main()
