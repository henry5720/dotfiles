#!/usr/bin/env python3
"""驗證各工具設定合成後的 commit attribution，保留使用者既有設定。"""
import json
import os
import shutil
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLAUDE = ROOT / "home/dot_claude/modify_settings.json.tmpl"
CODEX = ROOT / "home/dot_codex/modify_private_config.toml.tmpl"
OPENCODE = ROOT / "home/dot_config/opencode/modify_private_opencode.json.tmpl"
OPENCODE_PERSONAL = ROOT / "home/dot_config/opencode/routes/personal/opencode.json.tmpl"
CODEX_PERSONAL = ROOT / "home/dot_codex/modify_private_personal.config.toml.tmpl"


class CommitAttributionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        self.cfg = Path(self.tmp.name) / "data.toml"
        self.cfg.write_text('[data]\ncodexLbApiKey="fixture"\n', encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def render(self, template):
        return subprocess.check_output([
            "chezmoi", "--source", str(ROOT), "--config", str(self.cfg),
            "--destination", str(self.home), "--override-data",
            json.dumps({"chezmoi": {"homeDir": str(self.home)}}), "execute-template",
        ], input=template.read_bytes()).decode()

    def run_script(self, template, existing=""):
        env = os.environ.copy()
        env["HOME"] = str(self.home)
        return subprocess.run(
            ["sh", "-c", self.render(template)], input=existing, env=env,
            text=True, capture_output=True, check=True,
        ).stdout

    def test_claude_sets_commit_attribution_and_preserves_other_settings(self):
        existing = {
            "attribution": {"commit": "old", "pr": "Keep PR attribution"},
            "hooks": {"SessionStart": [{"hooks": [{"command": "keep-hook"}]}]},
            "enabledPlugins": {"other-plugin": True},
        }
        first = self.run_script(CLAUDE, json.dumps(existing))
        result = json.loads(first)
        self.assertEqual(result["attribution"], {
            "commit": "Co-Authored-By: Claude Code <noreply@anthropic.com>",
            "pr": "Keep PR attribution",
        })
        self.assertEqual(result["hooks"], existing["hooks"])
        self.assertTrue(result["enabledPlugins"]["other-plugin"])
        self.assertEqual(self.run_script(CLAUDE, first), first)

    def test_codex_appends_attribution_and_preserves_multiline_instructions(self):
        existing = (
            'developer_instructions = """既有指引\n'
            '[features]\n'
            '保留這段文字與引號。"""\n'
            'notify = ["herdr"]\n'
            '[mcp_servers.fixture]\nurl = "https://example.com/mcp"\n'
        )
        first = self.run_script(CODEX, existing)
        before, after = tomllib.loads(existing), tomllib.loads(first)
        instructions = after["developer_instructions"]
        self.assertTrue(instructions.startswith(before["developer_instructions"]))
        self.assertIn("Co-authored-by: Codex <noreply@openai.com>", instructions)
        self.assertEqual(after["notify"], before["notify"])
        self.assertEqual(after["mcp_servers"], before["mcp_servers"])
        self.assertEqual(self.run_script(CODEX, first), first)

    def test_codex_replaces_only_its_managed_instruction_block(self):
        instructions = (
            "使用者原有指引\n\n"
            "<!-- chezmoi:codex-commit-attribution:start -->\n舊版指引\n"
            "<!-- chezmoi:codex-commit-attribution:end -->\n後來追加的指引"
        )
        first = self.run_script(CODEX, "\"developer_instructions\" = " + json.dumps(instructions))
        after = tomllib.loads(first)["developer_instructions"]
        self.assertIn("使用者原有指引\n後來追加的指引", after)
        self.assertNotIn("舊版指引", after)
        self.assertEqual(after.count("Co-authored-by: Codex <noreply@openai.com>"), 1)
        self.assertEqual(self.run_script(CODEX, first), first)
        personal = tomllib.loads(self.run_script(CODEX_PERSONAL))
        self.assertNotIn("developer_instructions", personal)

    def test_opencode_routes_load_one_shared_commit_guide_and_keep_mcp(self):
        existing = {"mcp": {"fixture": {"type": "remote", "url": "https://example.com/mcp"}}}
        first = self.run_script(OPENCODE, json.dumps(existing))
        work = json.loads(first)
        personal = json.loads(self.render(OPENCODE_PERSONAL))
        expected = [str(self.home / ".config/opencode/commit-instructions.md")]
        self.assertEqual(work["instructions"], expected)
        self.assertEqual(personal["instructions"], expected)
        self.assertEqual(work["mcp"], existing["mcp"])
        self.assertEqual(personal["enabled_providers"], ["openai"])
        self.assertEqual(self.run_script(OPENCODE, first), first)

    def test_scoped_apply_deploys_guides_and_keeps_shared_symlinks(self):
        source = Path(self.tmp.name) / "source"
        for directory in ("dot_claude", "dot_codex", "dot_config/opencode", "dot_config/agent-commit", ".chezmoitemplates"):
            shutil.copytree(ROOT / "home" / directory, source / directory)
        command = [
            "chezmoi", "--source", str(source), "--config", str(self.cfg),
            "--destination", str(self.home), "--persistent-state",
            str(Path(self.tmp.name) / "state.boltdb"), "--override-data",
            json.dumps({"chezmoi": {"homeDir": str(self.home)}}),
        ]
        subprocess.run(command + ["apply"], check=True, capture_output=True)
        settings = json.loads((self.home / ".claude/settings.json").read_text())
        self.assertEqual(settings["attribution"]["commit"],
                         "Co-Authored-By: Claude Code <noreply@anthropic.com>")
        config = tomllib.loads((self.home / ".codex/config.toml").read_text())
        self.assertIn("Co-authored-by: Codex <noreply@openai.com>", config["developer_instructions"])
        for relative in (".codex/AGENTS.md", ".config/opencode/AGENTS.md"):
            deployed = self.home / relative
            self.assertTrue(deployed.is_symlink())
            self.assertEqual(deployed.resolve(), self.home / ".claude/CLAUDE.md")
        work = json.loads((self.home / ".config/opencode/opencode.json").read_text())
        personal = json.loads((self.home / ".config/opencode/routes/personal/opencode.json").read_text())
        guide = self.home / ".config/opencode/commit-instructions.md"
        self.assertEqual(work["instructions"], [str(guide)])
        self.assertEqual(personal["instructions"], [str(guide)])
        self.assertIn("Generated with OpenCode.", guide.read_text())
        shared_guide = self.home / ".config/agent-commit/instructions.md"
        self.assertEqual(shared_guide.read_text(),
                         (ROOT / "home/dot_config/agent-commit/instructions.md").read_text())
        for relative in (".claude/CLAUDE.md", ".codex/AGENTS.md", ".config/opencode/AGENTS.md"):
            self.assertIn("~/.config/agent-commit/instructions.md",
                          (self.home / relative).read_text())
        subprocess.run(command + ["verify"], check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
