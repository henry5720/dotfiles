#!/usr/bin/env python3
"""MCP 交給 skillshare 之後(#34),chezmoi 這側不能搶它寫的條目。"""
import json
import os
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CODEX = ROOT / "home/dot_codex/modify_private_config.toml.tmpl"
CODEX_PERSONAL = ROOT / "home/dot_codex/modify_private_personal.config.toml.tmpl"
OPENCODE = ROOT / "home/dot_config/opencode/modify_private_opencode.json.tmpl"
CLEANUP = ROOT / "home/.chezmoiscripts/run_once_after_remove-chezmoi-mcp.py.tmpl"
LEGACY_CHROME = ["-y", "chrome-devtools-mcp@latest", "--browser-url=http://127.0.0.1:9222", "--no-usage-statistics", "--no-performance-crux"]
PERMISSIONS = {"approval_policy": "on-request", "sandbox_mode": "workspace-write", "approvals_reviewer": "auto_review"}


class McpHandoffTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"; self.home.mkdir()
        self.cfg = Path(self.tmp.name) / "data.toml"
        self.cfg.write_text('[data]\ncodexLbApiKey="fixture"\ncontext7ApiKey=""\n', encoding="utf-8")

    def tearDown(self): self.tmp.cleanup()

    def render(self, template):
        return subprocess.check_output(["chezmoi", "--config", str(self.cfg), "--destination", str(self.home), "execute-template"], input=template.read_bytes()).decode()

    def run_script(self, template, interpreter, stdin=""):
        env = os.environ.copy(); env["HOME"] = str(self.home)
        return subprocess.run([interpreter, "-c", self.render(template)], input=stdin, env=env, text=True, capture_output=True, check=True).stdout

    def test_codex_keeps_tables_skillshare_appends(self):
        # 停用 skill 那段要出現,才驗得到它不會被搬到 skillshare 的 table 後面。
        wiki = self.home / "obsidian_wiki/skills/wiki-query"; wiki.mkdir(parents=True); (wiki / "SKILL.md").write_text("x")
        (self.home / ".codex/skills").mkdir(parents=True); (self.home / ".codex/skills/wiki-query").symlink_to(wiki)
        first = self.run_script(CODEX, "sh")
        synced = first + "\n[mcp_servers.gh_grep]\nurl = 'https://mcp.grep.app'\n"
        self.assertEqual(self.run_script(CODEX, "sh", synced), synced)

    def test_codex_pins_permission_keys_at_top_level(self):
        # codex 自己寫的 "user" 要被換掉,它自己的頂層 key 與 table 照留;輸出再餵一次要一樣。
        existing = (
            'approvals_reviewer = "user"\nnotify = ["herdr"]\n\n'
            '[projects."/x"]\ntrust_level = "trusted"\n'
        )
        first = self.run_script(CODEX, "sh", existing)
        config = tomllib.loads(first)
        for key, value in PERMISSIONS.items():
            self.assertEqual(config[key], value)  # 解析後是頂層 key,不在 provider table 底下
        self.assertEqual(config["notify"], ["herdr"])
        self.assertEqual(config["projects"], {"/x": {"trust_level": "trusted"}})
        self.assertNotIn("approvals_reviewer", config["model_providers"]["codex-lb-gcp"])
        self.assertEqual(self.run_script(CODEX, "sh", first), first)

    def test_codex_personal_has_no_permission_keys(self):
        output = tomllib.loads(self.run_script(CODEX_PERSONAL, "sh"))
        self.assertFalse(set(PERMISSIONS) & set(output))

    def test_opencode_keeps_mcp_and_resets_other_keys(self):
        existing = {"model": "drifted", "mcp": {"gh_grep": {"type": "remote", "url": "https://mcp.grep.app"}}}
        output = json.loads(self.run_script(OPENCODE, "sh", json.dumps(existing)))
        self.assertEqual(output["mcp"], existing["mcp"])
        self.assertEqual(output["model"], "codex-lb-gcp/gpt-6.1-sol")

    def test_opencode_models_follow_active_omo_preset(self):
        with tempfile.TemporaryDirectory() as d:
            source = Path(d)
            company_path = source / "dot_config/opencode/oh-my-opencode-slim.json"
            company_path.parent.mkdir(parents=True)
            company = json.loads((ROOT / "home/dot_config/opencode/oh-my-opencode-slim.json").read_text())
            company["preset"] = "fixture-active"
            company["presets"]["fixture-active"] = json.loads(json.dumps(company["presets"]["teamsync-astra"]))
            company["presets"]["fixture-active"]["orchestrator"]["model"] = "codex-lb-gcp/fixture-main"
            company["presets"]["fixture-active"]["explorer"]["model"] = "codex-lb-gcp/fixture-small"
            company_path.write_text(json.dumps(company), encoding="utf-8")
            rendered = subprocess.check_output([
                "chezmoi", "--source", str(source), "--config", str(self.cfg),
                "--destination", str(self.home), "execute-template",
            ], input=OPENCODE.read_bytes()).decode()
            env = os.environ.copy(); env["HOME"] = str(self.home)
            output = json.loads(subprocess.run(
                ["sh", "-c", rendered], input='{}', env=env, text=True,
                capture_output=True, check=True,
            ).stdout)
        self.assertEqual(output["model"], "codex-lb-gcp/fixture-main")
        self.assertEqual(output["small_model"], "codex-lb-gcp/fixture-small")

    def test_cleanup_removes_only_verbatim_legacy_entries(self):
        pinned = ["-y", "chrome-devtools-mcp@1.10.1"] + LEGACY_CHROME[2:]
        (self.home / ".claude.json").write_text(json.dumps({"mcpServers": {
            "chrome-devtools": {"type": "stdio", "command": "npx", "args": LEGACY_CHROME, "env": {}},
            "codegraph": {"type": "stdio", "command": "codegraph", "args": ["serve", "--mcp"]},
        }, "userID": "keep"}))
        (self.home / ".codex").mkdir()
        (self.home / ".codex/config.toml").write_text(
            'model = "m"\n\n[projects."/x"]\ntrust_level = "trusted"\n'
            '[mcp_servers.chrome-devtools]\ncommand = "npx"\nargs = ' + json.dumps(LEGACY_CHROME) + '\nenabled = true\nstartup_timeout_sec = 60\n\n'
            '[mcp_servers.context7]\nurl = "https://mcp.context7.com/mcp"\nenabled = true\nhttp_headers = { "CONTEXT7_API_KEY" = "secret" }\n\n'
            '[mcp_servers.gh_grep]\nurl = "https://mcp.grep.app"\n'
        )
        opencode = self.home / ".config/opencode/opencode.json"; opencode.parent.mkdir(parents=True)
        opencode.write_text(json.dumps({"mcp": {"chrome-devtools": {"type": "local", "command": ["npx"] + pinned}}}))
        self.run_script(CLEANUP, "python3")
        claude = json.loads((self.home / ".claude.json").read_text())
        self.assertEqual(sorted(claude["mcpServers"]), ["codegraph"])  # 手動加的不動
        self.assertEqual(claude["userID"], "keep")
        codex = tomllib.loads((self.home / ".codex/config.toml").read_text())
        self.assertEqual(sorted(codex["mcp_servers"]), ["gh_grep"])
        self.assertEqual(codex["projects"], {"/x": {"trust_level": "trusted"}})
        self.assertEqual(sorted(json.loads(opencode.read_text())["mcp"]), ["chrome-devtools"])  # 版本不同 = skillshare 寫的


if __name__ == "__main__":
    unittest.main()
