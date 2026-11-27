#!/usr/bin/env python3
"""MCP 交給 skillshare 之後(#34),chezmoi 這側不能搶它寫的條目。"""
import json
import os
import shutil
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CODEX = ROOT / "home/dot_codex/modify_private_config.toml.tmpl"
CODEX_PERSONAL = ROOT / "home/dot_codex/modify_private_personal.config.toml"
OPENCODE = ROOT / "home/dot_config/opencode/modify_private_opencode.json.tmpl"
MODIFY_TARGETS = {OPENCODE: ".config/opencode/opencode.json", CODEX: ".codex/config.toml",
                  CODEX_PERSONAL: ".codex/personal.config.toml"}
CLEANUP = ROOT / "home/.chezmoiscripts/run_once_after_remove-chezmoi-mcp.py.tmpl"
LEGACY_CHROME = ["-y", "chrome-devtools-mcp@latest", "--browser-url=http://127.0.0.1:9222", "--no-usage-statistics", "--no-performance-crux"]
PERMISSIONS = {"approvals_reviewer": "auto_review"}
# 這幾個 key 不寫、用 codex 預設;TUI 寫回的值每次 apply 都丟掉(#204)
DEFAULTED = ("model", "model_reasoning_effort", "approval_policy", "sandbox_mode")


class McpHandoffTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"; self.home.mkdir()
        self.cfg = Path(self.tmp.name) / "data.toml"
        self.cfg.write_text('[data]\ncodexLbApiKey="fixture"\ncontext7ApiKey=""\n', encoding="utf-8")

    def tearDown(self): self.tmp.cleanup()

    def render(self, template):
        return subprocess.check_output(["chezmoi", "--source", str(ROOT), "--config", str(self.cfg), "--destination", str(self.home), "execute-template"], input=template.read_bytes()).decode()

    def run_script(self, template, interpreter, stdin=""):
        env = os.environ.copy(); env["HOME"] = str(self.home)
        return subprocess.run([interpreter, "-c", self.render(template)], input=stdin, env=env, text=True, capture_output=True, check=True).stdout

    def run_modify(self, template, existing=""):
        # modify-template(#204 起所有平台):把現有內容放到暫存家目錄,用 chezmoi cat 算出 apply 會寫的內容
        path = self.home / MODIFY_TARGETS[template]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(existing, encoding="utf-8")
        override = {"chezmoi": {"homeDir": str(self.home)}, "tools": ["claude", "codex", "opencode"]}
        return subprocess.run([
            "chezmoi", "--no-tty", "--source", str(ROOT), "--config", str(self.cfg),
            "--destination", str(self.home), "--override-data", json.dumps(override), "cat", str(path),
        ], stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True).stdout

    def test_env_zsh_exports_only_filled_mcp_keys(self):
        # skillshare 的 MCP 設定只留 fromEnv／bearerToken 參照，值從 env.zsh 來；兩個都空就整份不部署。
        env = ROOT / "home/dot_config/zsh/private_env.zsh.tmpl"
        for c7, gk, want in (("", "", []), ("c7", "", ["CONTEXT7_API_KEY"]), ("", "gk", ["GRAPHIFY_API_KEY"]),
                             ("c7", "gk", ["CONTEXT7_API_KEY", "GRAPHIFY_API_KEY"])):
            self.cfg.write_text(f'[data]\ncontext7ApiKey="{c7}"\ngraphifyApiKey="{gk}"\n', encoding="utf-8")
            out = self.render(env)
            self.assertEqual([l.split("=")[0].removeprefix("export ") for l in out.splitlines() if l.startswith("export ")], want)
            if not want: self.assertEqual(out.strip(), "")
        self.cfg.write_text('[data]\ndiscordBotToken="dt"\n', encoding="utf-8")
        self.assertIn("export DISCORD_TOKEN='dt'", self.render(env))

    def test_codex_keeps_tables_skillshare_appends(self):
        # 停用 skill 那段要出現,才驗得到它不會被搬到 skillshare 的 table 後面。
        wiki = self.home / "obsidian_wiki/skills/wiki-query"; wiki.mkdir(parents=True); (wiki / "SKILL.md").write_text("x")
        (self.home / ".codex/skills").mkdir(parents=True); (self.home / ".codex/skills/wiki-query").symlink_to(wiki)
        first = self.run_modify(CODEX)
        self.assertIn('path = "' + str(self.home / ".codex/skills/wiki-query/SKILL.md") + '"\nenabled = false', first)
        synced = first + "\n[mcp_servers.gh_grep]\nurl = 'https://mcp.grep.app'\n"
        self.assertEqual(self.run_modify(CODEX, synced), synced)

    def test_codex_keeps_wakatime_plugin_tables(self):
        # install-wakatime 腳本跑 `codex plugin add` 寫進來的兩個 table(#173),apply 要原樣留著。
        first = self.run_modify(CODEX)
        added = first + (
            '\n[marketplaces.wakatime]\nsource_type = "git"\n'
            'source = "https://github.com/wakatime/codex-cli-wakatime.git"\n'
            '\n[plugins."codex-cli-wakatime@wakatime"]\nenabled = true\n'
        )
        self.assertEqual(self.run_modify(CODEX, added), added)
        self.assertTrue(tomllib.loads(added)["plugins"]["codex-cli-wakatime@wakatime"]["enabled"])

    def test_codex_pins_permission_keys_at_top_level(self):
        # codex 自己寫的 "user" 要被換掉,它自己的頂層 key 與 table 照留;輸出再餵一次要一樣。
        existing = (
            'approvals_reviewer = "user"\napproval_policy = "never"\nsandbox_mode = "read-only"\n'
            'model = "gpt-6.1-sol"\nmodel_reasoning_effort = "medium"\nnotify = ["herdr"]\n\n'
            '[projects."/x"]\ntrust_level = "trusted"\n'
        )
        first = self.run_modify(CODEX, existing)
        config = tomllib.loads(first)
        for key, value in PERMISSIONS.items():
            self.assertEqual(config[key], value)  # 解析後是頂層 key,不在 provider table 底下
        for key in DEFAULTED:
            self.assertNotIn(key, config)
        self.assertEqual(config["notify"], ["herdr"])
        self.assertEqual(config["projects"], {"/x": {"trust_level": "trusted"}})
        self.assertNotIn("approvals_reviewer", config["model_providers"]["codex-lb-gcp"])
        self.assertEqual(self.run_modify(CODEX, first), first)

    def test_codex_personal_has_no_permission_keys(self):
        output = tomllib.loads(self.run_modify(CODEX_PERSONAL))
        self.assertFalse(set(PERMISSIONS) & set(output))
        # TUI 的 /permissions 在 --profile personal 時寫進這份,要丟掉,不然蓋過 base 的 auto_review
        written = 'approvals_reviewer = "user"\napproval_policy = "never"\nsandbox_mode = "read-only"\n'
        output = tomllib.loads(self.run_modify(CODEX_PERSONAL, written))
        self.assertFalse({"approvals_reviewer", "approval_policy", "sandbox_mode"} & set(output))

    def test_opencode_keeps_mcp_and_resets_other_keys(self):
        existing = {"model": "drifted", "mcp": {"gh_grep": {"type": "remote", "url": "https://mcp.grep.app"}}}
        output = json.loads(self.run_modify(OPENCODE, json.dumps(existing)))
        self.assertEqual(output["mcp"], existing["mcp"])
        self.assertEqual(output["model"], "codex-lb-gcp/gpt-6.1-sol")

    def test_opencode_models_follow_active_omo_preset(self):
        with tempfile.TemporaryDirectory() as d:
            source = Path(d)
            company_path = source / "dot_config/opencode/oh-my-opencode-slim.json"
            company_path.parent.mkdir(parents=True)
            company = json.loads((ROOT / "home/dot_config/opencode/oh-my-opencode-slim.json").read_text())
            company["preset"] = "fixture-active"
            company["presets"]["fixture-active"] = json.loads(json.dumps(company["presets"]["teamsync"]))
            company["presets"]["fixture-active"]["orchestrator"]["model"] = "codex-lb-gcp/fixture-main"
            company["presets"]["fixture-active"]["explorer"]["model"] = "codex-lb-gcp/fixture-small"
            company_path.write_text(json.dumps(company), encoding="utf-8")
            # modify-template 引用的共用片段(opencode-json)也要在這份暫時的 source 裡
            shutil.copytree(ROOT / "home/.chezmoitemplates", source / ".chezmoitemplates")
            rendered = subprocess.check_output([
                "chezmoi", "--source", str(source), "--config", str(self.cfg),
                "--destination", str(self.home), "execute-template",
            ], input=OPENCODE.read_bytes()).decode()
            # 第二輪:chezmoi 跑 modify-template 時會帶 .chezmoi.stdin,execute-template 不會,用 override 補上
            output = json.loads(subprocess.check_output([
                "chezmoi", "--source", str(source), "--config", str(self.cfg), "--destination", str(self.home),
                "--override-data", json.dumps({"chezmoi": {"stdin": "{}"}}), "execute-template",
            ], input=rendered.encode()).decode())
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
