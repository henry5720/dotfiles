#!/usr/bin/env python3
"""tools-ai 的 agent-config 項(#35):沒 init 走 init,init 過走 pull,最後都要 sync mcp -g。"""
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "script/ubuntu/install-tools-ai.sh"
AGENT_CONFIG = str(re.search(r"^TOOLS=\((.*)\)$", SCRIPT.read_text(), re.M).group(1).split().index("agent-config") + 1)  # 選單編號從 1 起


class AgentConfigItemTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        (self.home / ".config/skillshare").mkdir(parents=True)
        (self.home / ".config/skillshare/config.yaml").write_text("git_root: root\n")
        # 假的 skillshare:只把收到的參數記下來。
        bin_dir = self.home / "bin"
        bin_dir.mkdir()
        (bin_dir / "skillshare").write_text(f'#!/bin/sh\necho "$*" >> {self.home}/calls\n')
        (bin_dir / "skillshare").chmod(0o755)
        self.path = f"{bin_dir}:/usr/bin:/bin"

    def tearDown(self):
        self.tmp.cleanup()

    def run_item(self, choice=AGENT_CONFIG, **env):
        pick = self.home / "pick"
        pick.write_text(choice + "\n")
        full = {"HOME": str(self.home), "PATH": self.path, "INPUT_SRC": str(pick), "AGENT_CONFIG_REMOTE": "REMOTE", **env}
        out = subprocess.run(["bash", str(SCRIPT)], env=full, capture_output=True, text=True, check=True).stdout
        calls = (self.home / "calls").read_text().splitlines() if (self.home / "calls").exists() else []
        return out, calls

    def test_first_run_inits_then_syncs(self):
        _, calls = self.run_item()
        self.assertEqual(calls, [
            "init --git-root root --remote REMOTE --no-copy --no-skill --targets claude,codex",
            "install -g", "sync", "sync mcp -g",
        ])

    def test_after_init_pulls_then_syncs_mcp(self):
        (self.home / ".config/skillshare/.git").mkdir()
        out, calls = self.run_item()
        self.assertIn("agent-config（skills 與 MCP） ✅", out)
        self.assertEqual(calls, ["pull", "sync mcp -g"])

    def test_skillshare_off_path_is_not_reinstalled(self):
        # 裝在 ~/.local/bin 但這一輪 PATH 沒有它(chezmoi apply 前、從 bash 叫)。
        local_bin = self.home / ".local/bin"
        local_bin.mkdir(parents=True)
        (self.home / "bin/skillshare").rename(local_bin / "skillshare")
        (self.home / ".config/skillshare/.git").mkdir()
        out, calls = self.run_item(PATH="/usr/bin:/bin")
        self.assertIn("agent-config（skills 與 MCP） ✅", out)
        self.assertNotIn("install.sh", out)
        self.assertEqual(calls, ["pull", "sync mcp -g"])

    def test_clients_off_path_are_not_reinstalled(self):
        # 非互動 ssh 的 PATH 沒有這些目錄;以前會重跑官方 installer,Codex 那支還會往 .zshrc 追加 PATH(#36)。
        for rel in (".local/bin/claude", ".local/bin/codex", ".opencode/bin/opencode"):
            (self.home / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.home / rel).write_text("#!/bin/sh\n")
            (self.home / rel).chmod(0o755)
        (self.home / "bin/curl").write_text(f'#!/bin/sh\necho "curl $*" >> {self.home}/calls\n')
        (self.home / "bin/curl").chmod(0o755)
        out, calls = self.run_item(choice="1 2 3")
        for label in ("Claude Code", "Codex", "OpenCode"):
            self.assertIn(f"✅ {label} 已安裝。", out)
        self.assertEqual(calls, [])

    def test_codex_installer_sees_local_bin_on_path(self):
        # Codex installer 只有在 ~/.local/bin 不在 PATH 時才往 shell rc 追加 PATH;先放進去,它就不動 .zshrc。
        (self.home / "bin/curl").write_text('#!/bin/sh\necho \'echo "installer PATH=$PATH" >> "$HOME/calls"\'\n')
        (self.home / "bin/curl").chmod(0o755)
        _, calls = self.run_item(choice="2")
        self.assertEqual(len(calls), 1)
        self.assertIn(f"{self.home}/.local/bin", calls[0].split("=", 1)[1].split(":"))

    def test_dry_run_prints_without_running(self):
        out, calls = self.run_item(DRY_RUN="1")
        self.assertIn("skillshare init --git-root root --remote REMOTE", out)
        self.assertIn("skillshare sync mcp -g", out)
        self.assertEqual(calls, [])


if __name__ == "__main__": unittest.main()
