#!/usr/bin/env python3
"""Windows 主機會部署什麼:用 --override-data 把 chezmoi.os 換成 windows／linux／android,
在 Linux 上驗 chezmoi 對這個 repo 會管哪些 target、config 樣板渲染出什麼(spec #254 的 Testing Decisions)。

Windows 白名單多一個檔案時:改 home/.chezmoiignore 的 Windows 段,再把 target 加進下面的 WINDOWS_TARGETS。
實機才驗得到的(PowerShell 讀不讀 profile、Terminal 讀不讀 settings.json)在 docs/windows.md 的實機清單。
"""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
CONFIG_TEMPLATE = ROOT / "home/.chezmoi.toml.tmpl"
# Windows 只部署這些 target;多一個、少一個都算錯。跟 home/.chezmoiignore 的 Windows 白名單對應
WINDOWS_TARGETS = {
    ".wslconfig",
    ".config/starship.toml",
    "Documents/PowerShell/Profile.ps1",
    "Documents/WindowsPowerShell/Profile.ps1",
}
# 只給 Windows 的 target(或它們的頂層目錄),Linux／Termux 不能部署
WINDOWS_ONLY = ("Documents", "AppData", ".wslconfig")


def parents(paths):
    """每個 target 的上層目錄(chezmoi managed 會把它們也列出來)。"""
    return {str(p) for t in paths for p in PurePosixPath(t).parents if str(p) != "."}


class WindowsDeployTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        self.cfg = Path(self.tmp.name) / "chezmoi.toml"
        self.cfg.write_text("", encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def chezmoi(self, os_name, *args, data=None):
        override = {"chezmoi": {"os": os_name, "homeDir": str(self.home)}} | (data or {})
        return subprocess.run([
            "chezmoi", "--no-tty", "--source", str(ROOT), "--config", str(self.cfg),
            "--destination", str(self.home), "--override-data", json.dumps(override), *args,
        ], stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True).stdout

    def managed(self, os_name, tools):
        return set(self.chezmoi(os_name, "managed", data={"tools": tools}).split())

    # ===============================================================
    # 部署哪些 target
    # ===============================================================
    def test_windows_manages_exactly_the_whitelist(self):
        # Windows 的 config 是 tools = [](見下面 config 樣板的測試)
        self.assertEqual(self.managed("windows", []), WINDOWS_TARGETS | parents(WINDOWS_TARGETS))

    def test_linux_and_termux_skip_windows_only_targets(self):
        for os_name in ("linux", "android"):
            for tools in ([], ["zsh", "starship", "claude", "agent-config"]):
                with self.subTest(os=os_name, tools=tools):
                    leaked = {t for t in self.managed(os_name, tools)
                              if PurePosixPath(t).parts[0] in WINDOWS_ONLY}
                    self.assertEqual(leaked, set())

    # ===============================================================
    # config 樣板(chezmoi init 問什麼)
    # ===============================================================
    def test_windows_init_asks_nothing_and_has_no_tools(self):
        # stdin 是 /dev/null:樣板只要問任何一題就讀到 EOF 失敗
        out = self.chezmoi("windows", "execute-template", "--init",
                           CONFIG_TEMPLATE.read_text(encoding="utf-8"))
        self.assertIn("\n    tools = []\n", out)
        for key in ("gitUserName", "gitUserEmail", "machineUse", "ApiKey", "Password"):
            self.assertNotIn(key, out)

    # ===============================================================
    # PowerShell profile(pwsh 7 與 5.1 共用一份)
    # ===============================================================
    def test_both_powershell_profiles_render_the_same_five_settings(self):
        self.chezmoi("windows", "apply", data={"tools": []})
        pwsh7 = (self.home / "Documents/PowerShell/Profile.ps1").read_text(encoding="utf-8")
        ps51 = (self.home / "Documents/WindowsPowerShell/Profile.ps1").read_text(encoding="utf-8")
        self.assertEqual(pwsh7, ps51)
        for needle in (
            r"$HOME\.local\bin",
            "Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete",
            "Set-PSReadLineOption -PredictionSource History",
            "Get-Command starship",
            "starship init powershell",
            "Get-Command zoxide",
            "zoxide init powershell",
        ):
            with self.subTest(needle=needle):
                self.assertIn(needle, pwsh7)
        self.assertNotIn("oh-my-posh", pwsh7)

    def test_powershell_profile_is_ascii_only(self):
        # 5.1 讀沒有 BOM 的檔案用系統 ANSI 字碼頁,UTF-8 的中文註解會變亂碼
        self.chezmoi("windows", "apply", data={"tools": []})
        for target in ("Documents/PowerShell/Profile.ps1", "Documents/WindowsPowerShell/Profile.ps1"):
            with self.subTest(target=target):
                self.assertTrue((self.home / target).read_bytes().isascii())

    def test_history_prediction_only_enabled_on_pwsh7(self):
        # 5.1 內建的 PSReadLine 2.0 沒有 -PredictionSource,不包在版本判斷裡會出紅字
        self.chezmoi("windows", "apply", data={"tools": []})
        lines = (self.home / "Documents/PowerShell/Profile.ps1").read_text(encoding="utf-8").splitlines()
        idx = next(i for i, l in enumerate(lines) if "-PredictionSource History" in l)
        guard = next(l for l in reversed(lines[:idx]) if l.strip().startswith("if"))
        self.assertRegex(guard, r"\$PSVersionTable\.PSVersion\.Major\s+-ge\s+7")


if __name__ == "__main__":
    unittest.main()
