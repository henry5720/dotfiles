#!/usr/bin/env python3
"""指令檔(Instructions)的 symlink:chezmoi apply 後,每個 client 讀的位置都連到 agent-config 的 instructions/。

指令檔內容在 agent-config 的 instructions/,由那邊的 tests/ 驗;這裡只驗 chezmoi 把它們放到哪。
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AGENTS_MD = ".config/skillshare/instructions/agents-md/AGENTS.md"
LINKS = {
    # 一份 AGENTS.md,Claude 讀的檔名是 CLAUDE.md
    ".claude/CLAUDE.md": AGENTS_MD,
    ".codex/AGENTS.md": AGENTS_MD,
    ".config/opencode/AGENTS.md": AGENTS_MD,
    ".config/opencode/routes/personal/AGENTS.md": AGENTS_MD,
    # commit 指引:路徑要對上 AGENTS.md 與 opencode.json 引用的位置
    ".config/agent-commit/instructions.md": ".config/skillshare/instructions/agent-commit/instructions.md",
    ".config/opencode/commit-instructions.md":
        ".config/skillshare/instructions/opencode-commit/commit-instructions.md",
}
TEMPLATES = {
    ".claude/CLAUDE.md": "dot_claude/symlink_CLAUDE.md.tmpl",
    ".codex/AGENTS.md": "dot_codex/symlink_AGENTS.md.tmpl",
    ".config/opencode/AGENTS.md": "dot_config/opencode/symlink_AGENTS.md.tmpl",
    ".config/opencode/routes/personal/AGENTS.md":
        "dot_config/opencode/routes/personal/symlink_AGENTS.md.tmpl",
    ".config/agent-commit/instructions.md": "dot_config/agent-commit/symlink_instructions.md.tmpl",
    ".config/opencode/commit-instructions.md": "dot_config/opencode/symlink_commit-instructions.md.tmpl",
}


class InstructionSymlinksTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        tmp = Path(self.tmp.name)
        self.home = tmp / "home"
        self.home.mkdir()
        # 只複製這 6 個模板,apply 時不會跑到其他檔案或腳本
        self.source = tmp / "source"
        for template in TEMPLATES.values():
            (self.source / template).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / "home" / template, self.source / template)
        cfg = tmp / "chezmoi.toml"
        cfg.write_text("", encoding="utf-8")
        self.command = [
            "chezmoi", "--source", str(self.source), "--config", str(cfg),
            "--destination", str(self.home), "--persistent-state", str(tmp / "state.boltdb"),
            "--override-data", json.dumps({"chezmoi": {"homeDir": str(self.home)}}),
        ]

    def tearDown(self):
        self.tmp.cleanup()

    def test_apply_links_every_client_path_to_agent_config_instructions(self):
        subprocess.run(self.command + ["apply"], check=True, capture_output=True)
        for link, target in LINKS.items():
            with self.subTest(link=link):
                path = self.home / link
                self.assertTrue(path.is_symlink())
                self.assertEqual(os.readlink(path), str(self.home / target))
        subprocess.run(self.command + ["verify"], check=True, capture_output=True)

    def test_links_resolve_once_agent_config_is_cloned(self):
        # 新機器上 symlink 先懸空,after 腳本 clone agent-config 後才指得到檔案
        subprocess.run(self.command + ["apply"], check=True, capture_output=True)
        self.assertFalse((self.home / ".claude/CLAUDE.md").exists())
        for target in set(LINKS.values()):
            (self.home / target).parent.mkdir(parents=True, exist_ok=True)
            (self.home / target).write_text(target, encoding="utf-8")
        for link, target in LINKS.items():
            with self.subTest(link=link):
                self.assertEqual((self.home / link).read_text(encoding="utf-8"), target)


if __name__ == "__main__":
    unittest.main()
