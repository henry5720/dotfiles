#!/usr/bin/env python3
"""chezmoi 釘進 skillshare config.yaml 的部分:指令檔(Instructions)的 extras 段,與 Claude target 的 agents 路徑。

指令檔內容在 agent-config 的 instructions/,由那邊的 tests/ 驗;這裡只驗 config.yaml 釘的內容與 extras 連出來的位置。
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "home/dot_config/skillshare/modify_config.yaml.tmpl"
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
# skillshare init／extras 指令存檔後的樣子:加 schema 註解、重排 key、extras 放在 preserve_tilde_on_save 前面
SAVED_BY_SKILLSHARE = """\
# yaml-language-server: $schema=https://raw.githubusercontent.com/runkids/skillshare/main/schemas/config.schema.json

sources:
  mcp: ~/.config/skillshare/mcp.yaml
  skills: ~/.config/skillshare/skills

git_root: root

targets:
  claude:
    skills:
      path: ~/.claude/skills
    agents:
      path: ~/old-agents
  codex:
    skills:
      path: ~/.agents/skills

extras:
  - name: old
    source: ~/old
    file: OLD.md
    targets:
      - path: ~/.old

preserve_tilde_on_save: true
"""
# agents 排在 skills 後面,跟 skillshare 存檔的順序一樣
PINNED_CLAUDE = """\
  claude:
    skills:
      path: ~/.claude/skills
    agents:
      path: ~/.claude/agents
"""


class SkillshareExtrasTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        cfg = Path(self.tmp.name) / "chezmoi.toml"
        cfg.write_text("", encoding="utf-8")
        self.script = subprocess.check_output([
            "chezmoi", "--source", str(ROOT), "--config", str(cfg),
            "--destination", str(self.home), "--override-data",
            json.dumps({"chezmoi": {"homeDir": str(self.home)}}), "execute-template",
        ], input=CONFIG.read_bytes()).decode()

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, existing=""):
        return subprocess.run(
            ["sh", "-c", self.script], input=existing, text=True, capture_output=True, check=True,
        ).stdout

    def test_new_machine_gets_base_config_with_extras(self):
        out = self.run_script()
        self.assertIn("git_root: root\n", out)
        self.assertIn("path: ~/.agents/skills\n", out)
        self.assertIn(PINNED_CLAUDE, out)
        self.assertEqual(out.count("\nextras:\n"), 1)
        self.assertEqual(self.run_script(out), out)

    def test_replaces_extras_in_place_and_keeps_skillshare_layout(self):
        out = self.run_script(SAVED_BY_SKILLSHARE)
        self.assertNotIn("name: old", out)
        self.assertNotIn("old-agents", out)
        self.assertIn(PINNED_CLAUDE + "  codex:\n", out)
        before = SAVED_BY_SKILLSHARE.split("extras:\n")[0].replace("~/old-agents", "~/.claude/agents")
        self.assertTrue(out.startswith(before + "extras:\n"))
        self.assertTrue(out.endswith("      - path: ~/.config/opencode\n\npreserve_tilde_on_save: true\n"))
        self.assertEqual(self.run_script(out), out)

    def test_adds_claude_agents_path_when_missing(self):
        existing = SAVED_BY_SKILLSHARE.replace("    agents:\n      path: ~/old-agents\n", "")
        out = self.run_script(existing)
        self.assertIn(PINNED_CLAUDE + "  codex:\n", out)
        self.assertEqual(self.run_script(out), out)

    def test_appends_extras_when_missing(self):
        existing = (SAVED_BY_SKILLSHARE.split("extras:\n")[0].replace("~/old-agents", "~/.claude/agents")
                    + "preserve_tilde_on_save: true\n")
        out = self.run_script(existing)
        self.assertTrue(out.startswith(existing + "\nextras:\n"))
        self.assertEqual(self.run_script(out), out)

    @unittest.skipUnless(shutil.which("skillshare"), "沒有 skillshare")
    def test_sync_links_every_client_path_to_agent_config_instructions(self):
        source = self.home / ".config/skillshare"
        (source / "skills").mkdir(parents=True)  # 沒有 skills 來源 sync 會直接失敗
        (source / "config.yaml").write_text(self.run_script(), encoding="utf-8")
        for target in set(LINKS.values()):
            (self.home / target).parent.mkdir(parents=True, exist_ok=True)
            (self.home / target).write_text(target, encoding="utf-8")
        env = os.environ | {"HOME": str(self.home), "XDG_CONFIG_HOME": str(self.home / ".config")}
        subprocess.run(["skillshare", "sync", "extras"], env=env, cwd=self.home,
                       check=True, capture_output=True)
        for link, target in LINKS.items():
            with self.subTest(link=link):
                path = self.home / link
                self.assertTrue(path.is_symlink())
                self.assertEqual(os.readlink(path), str(self.home / target))


if __name__ == "__main__":
    unittest.main()
