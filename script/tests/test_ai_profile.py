#!/usr/bin/env python3
"""共用 roots profile routing 的 fixture tests。"""
import json
import os
import stat
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "home/dot_local/bin/executable_ai-profile"


class AiProfileTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"; self.bin.mkdir()
        self.home = self.root / "home"; self.home.mkdir()
        self.project = self.root / "project"; self.project.mkdir()
        for name in ("codex-work", "codex-personal", "opencode-work", "opencode-personal"):
            (self.bin / name).symlink_to(LAUNCHER)
        self.write_fake("codex", "#!/bin/sh\nif [ \"$1\" = login ] && [ \"$2\" = status ]; then printf 'chatgpt\\n'; exit 0; fi\nprintf '%s\\n' \"$*\"\nprintf 'CODEX_HOME=%s\\n' \"${CODEX_HOME-}\"\nexit 7\n")
        self.write_fake("opencode", "#!/usr/bin/env python3\nimport json,os,sys\nprint(json.dumps({'argv':sys.argv[1:],'config':os.environ.get('OPENCODE_CONFIG_DIR',''),'content':os.environ.get('OPENCODE_CONFIG_CONTENT',''),'tui':os.environ.get('OPENCODE_TUI_CONFIG',''),'preset':os.environ.get('OH_MY_OPENCODE_SLIM_PRESET','')}))\nraise SystemExit(7)\n")

    def tearDown(self): self.tmp.cleanup()

    def write_fake(self, name, body):
        path = self.bin / name; path.write_text(body, encoding="utf-8"); path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def invoke(self, name, *args, extra=None):
        env = os.environ.copy(); env.update({"HOME": str(self.home), "PATH": f"{self.bin}:{env['PATH']}", "CODEX_HOME": str(self.home / ".codex"), "XDG_CONFIG_HOME": str(self.home / ".config"), "OPENAI_API_KEY": "fixture"})
        if extra: env.update(extra)
        return subprocess.run([str(self.bin / name), *args], cwd=self.project, env=env, text=True, capture_output=True)

    def write_codex_profile(self, model="gpt-personal"):
        path = self.home / ".codex"; path.mkdir(exist_ok=True); (path / "personal.config.toml").write_text(f'model = "{model}"\nmodel_provider = "openai"\n', encoding="utf-8")

    def write_opencode_route(self):
        path = self.home / ".config/opencode/routes/personal"; path.mkdir(parents=True)
        (path / "opencode.json").write_text('{"model":"openai/personal","small_model":"openai/small"}', encoding="utf-8")
        (path / "oh-my-opencode-slim.json").write_text('{"presets":{"personal":{}},"council":{"presets":{"personal":{"terra":{"model":"openai/personal"},"sol":{"model":"openai/sol"},"luna":{"model":"openai/luna"}}}}}', encoding="utf-8")

    def test_codex_work_passes_argv_and_shared_root(self):
        result = self.invoke("codex-work", "exec", "hello"); self.assertEqual(result.returncode, 7); self.assertIn("exec hello", result.stdout); self.assertIn("CODEX_HOME=" + str(self.home / ".codex"), result.stdout)

    def test_codex_personal_profile_and_empty_gate(self):
        result = self.invoke("codex-personal", "exec", "hello"); self.assertEqual(result.returncode, 2); self.assertIn("data.aiPersonal.codexModel", result.stderr)
        self.write_codex_profile(); result = self.invoke("codex-personal", "exec", "hello"); self.assertEqual(result.returncode, 7); self.assertIn("--profile personal exec hello", result.stdout)
        result = self.invoke("codex-personal"); self.assertEqual(result.returncode, 7); self.assertIn("--profile personal", result.stdout)

    def test_codex_personal_keeps_user_flags_and_open_code_c_is_not_rejected(self):
        self.write_codex_profile(); result = self.invoke("codex-personal", "-c", 'model="other"'); self.assertEqual(result.returncode, 7); self.assertIn("--profile personal -c model=", result.stdout)
        self.write_opencode_route(); result = self.invoke("opencode-personal", "-c", "run"); self.assertEqual(result.returncode, 7)

    def test_opencode_personal_route_overlay_and_no_runtime_write(self):
        self.write_opencode_route(); before = sorted(str(p.relative_to(self.home)) for p in self.home.rglob("*"))
        result = self.invoke("opencode-personal", "run", "hello", extra={"OPENCODE_CONFIG_CONTENT": '{"theme":"neutral"}'})
        self.assertEqual(result.returncode, 7); payload = json.loads(result.stdout); self.assertIn("routes/personal", payload["config"]); self.assertEqual(json.loads(payload["content"])["theme"], "neutral")
        self.assertEqual(before, sorted(str(p.relative_to(self.home)) for p in self.home.rglob("*")))

    def test_opencode_personal_ready_empty_argv_and_work_resets_route_overrides(self):
        self.write_opencode_route(); result = self.invoke("opencode-personal")
        self.assertEqual(result.returncode, 7)
        result = self.invoke("opencode-work", "--help", extra={"OPENCODE_CONFIG_DIR": "personal", "OPENCODE_TUI_CONFIG": "personal", "OH_MY_OPENCODE_SLIM_PRESET": "personal"})
        self.assertEqual(result.returncode, 7)

    def test_personal_help_login_models_no_model_injection(self):
        self.write_opencode_route()
        for name, args in (("opencode-personal", ("auth", "login")), ("opencode-personal", ("models",))):
            result = self.invoke(name, *args); self.assertEqual(result.returncode, 7); self.assertNotIn("--model", result.stdout)

    def test_codex_personal_login_status_is_native_and_safe(self):
        # fixture 只模擬 status；不建立 auth 檔，也不會執行 login/logout。
        result = self.invoke("codex-personal", "login", "status")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "chatgpt\n")
        self.assertEqual(result.stderr, "")

    def test_codex_personal_logout_is_native(self):
        result = self.invoke("codex-personal", "logout")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout.splitlines()[0], "logout")

    def test_opencode_login_uses_pure_and_clears_route_environment(self):
        for args in (("auth", "login"), ("providers", "login")):
            result = self.invoke("opencode-personal", *args, extra={"OPENCODE_CONFIG": "bad", "OPENCODE_CONFIG_DIR": "bad", "OPENCODE_TUI_CONFIG": "bad", "OPENCODE_CONFIG_CONTENT": "bad", "OH_MY_OPENCODE_SLIM_PRESET": "bad"})
            self.assertEqual(result.returncode, 7)
            payload = json.loads(result.stdout)
            self.assertEqual(payload["argv"], ["--pure", *args])
            self.assertEqual(payload["config"], "")
            self.assertEqual(payload["content"], "")
            self.assertEqual(payload["tui"], "")
            self.assertEqual(payload["preset"], "")

    def test_templates_missing_full_and_reinit(self):
        with tempfile.TemporaryDirectory() as d:
            cfg = Path(d) / "data.toml"; cfg.write_text("", encoding="utf-8")
            for relative in ("home/dot_config/opencode/routes/personal/opencode.json.tmpl", "home/dot_config/opencode/routes/personal/oh-my-opencode-slim.json.tmpl"):
                subprocess.run(["chezmoi", "--config", str(cfg), "execute-template"], input=(ROOT / relative).read_bytes(), check=True, stdout=subprocess.DEVNULL)
            cfg.write_text('[data]\ncodeServerPassword="x"\ncodexLbApiKey="x"\ncontext7ApiKey=""\ngitUserName="x"\ngitUserEmail="x@y.invalid"\n[data.aiPersonal]\ncodexModel="keep-codex"\n[data.aiPersonal.models]\nastra="keep-astra"\nsol="keep-sol"\nluna="keep-luna"\n', encoding="utf-8")
            output = subprocess.check_output(["chezmoi", "--no-tty", "--config", str(cfg), "execute-template", "--init"], input=(ROOT / "home/.chezmoi.toml.tmpl").read_bytes()).decode()
            self.assertTrue(all(value in output for value in ("keep-codex", "keep-astra", "keep-sol", "keep-luna")))

    def test_personal_route_names_and_tui_pin(self):
        self.assertIn("{{ .chezmoi.homeDir }}", (ROOT / "home/dot_config/opencode/routes/personal/symlink_tui.jsonc.tmpl").read_text())
        self.assertNotIn("acpAgents", (ROOT / "home/dot_config/opencode/routes/personal/oh-my-opencode-slim.json.tmpl").read_text())
        self.assertIn("{{ .chezmoi.homeDir }}", (ROOT / "home/dot_config/opencode/routes/personal/symlink_skills.tmpl").read_text())
        self.assertIn("{{ .chezmoi.homeDir }}", (ROOT / "home/dot_config/opencode/routes/personal/symlink_oh-my-opencode-slim.tmpl").read_text())
        self.assertFalse((ROOT / "home/dot_config/opencode/routes/personal/skills/symlink_local-artifact-intake.tmpl").exists())

    def test_rendered_personal_route_models_and_common_role_metadata(self):
        with tempfile.TemporaryDirectory() as d:
            cfg = Path(d) / "data.toml"
            cfg.write_text('[data.aiPersonal.models]\nastra="astra"\nsol="sol"\nluna="luna"\n', encoding="utf-8")
            rendered = json.loads(subprocess.check_output(["chezmoi", "--config", str(cfg), "execute-template"], input=(ROOT / "home/dot_config/opencode/routes/personal/oh-my-opencode-slim.json.tmpl").read_bytes()))
        roles = rendered["presets"]["personal"]
        self.assertEqual(set(roles), {"orchestrator", "oracle", "council", "explorer", "librarian", "designer", "fixer"})
        self.assertTrue(all(role["model"].startswith("openai/") for role in roles.values()))
        self.assertNotIn("acpAgents", rendered); self.assertEqual(rendered["fallback"]["enabled"], False)
        company = json.loads((ROOT / "home/dot_config/opencode/oh-my-opencode-slim.json").read_text())
        company_orchestrator = company["presets"]["teamsync-astra"]["orchestrator"]
        self.assertEqual(roles["orchestrator"]["skills"], company_orchestrator["skills"])
        self.assertEqual(roles["orchestrator"]["mcps"], company_orchestrator["mcps"])
        for name in ("oracle", "librarian"):
            self.assertEqual(roles[name]["skills"], company["presets"]["teamsync-astra"][name]["skills"])
            self.assertEqual(roles[name]["mcps"], company["presets"]["teamsync-astra"][name]["mcps"])

    def test_personal_omo_include_inherits_changed_company_metadata(self):
        with tempfile.TemporaryDirectory() as d:
            source = Path(d); company_path = source / "dot_config/opencode/oh-my-opencode-slim.json"
            company_path.parent.mkdir(parents=True)
            company = json.loads((ROOT / "home/dot_config/opencode/oh-my-opencode-slim.json").read_text())
            company["presets"]["teamsync-astra"]["orchestrator"]["skills"] = ["fixture-common-skill"]
            company["presets"]["teamsync-astra"]["orchestrator"]["mcps"] = ["fixture-common-mcp"]
            company["presets"]["teamsync-astra"]["orchestrator"]["variant"] = "fixture-variant"
            company_path.write_text(json.dumps(company), encoding="utf-8")
            template = source / "route.tmpl"
            template.write_bytes((ROOT / "home/dot_config/opencode/routes/personal/oh-my-opencode-slim.json.tmpl").read_bytes())
            cfg = source / "data.toml"; cfg.write_text('[data.aiPersonal.models]\nastra="a"\nsol="s"\nluna="l"\n', encoding="utf-8")
            rendered = subprocess.check_output(["chezmoi", "--source", str(source), "--config", str(cfg), "execute-template"], input=template.read_bytes())
            output = json.loads(rendered)
            self.assertEqual(output["presets"]["personal"]["orchestrator"]["skills"], ["fixture-common-skill"])
            self.assertEqual(output["presets"]["personal"]["orchestrator"]["mcps"], ["fixture-common-mcp"])
            self.assertEqual(output["presets"]["personal"]["orchestrator"]["variant"], "fixture-variant")

    def test_personal_opencode_route_denies_company_imagegen_skill(self):
        with tempfile.TemporaryDirectory() as d:
            cfg = Path(d) / "data.toml"
            cfg.write_text('[data.aiPersonal.models]\nastra="astra"\nluna="luna"\n', encoding="utf-8")
            rendered = json.loads(subprocess.check_output(["chezmoi", "--config", str(cfg), "execute-template"], input=(ROOT / "home/dot_config/opencode/routes/personal/opencode.json.tmpl").read_bytes()))
        self.assertEqual(rendered["permission"]["skill"]["company-imagegen-fallback"], "deny")

    def test_personal_codex_skill_deny_renders_valid_and_idempotent_toml(self):
        with tempfile.TemporaryDirectory() as d:
            cfg = Path(d) / "data.toml"
            cfg.write_text('[data.aiPersonal]\ncodexModel="gpt-6-astra"\n', encoding="utf-8")
            template = ROOT / "home/dot_codex/modify_private_personal.config.toml.tmpl"
            script = subprocess.check_output(["chezmoi", "--source", str(ROOT), "--config", str(cfg), "execute-template"], input=template.read_bytes())
        existing = '[skills]\nstate = "keep"\n\n[[skills.config]]\npath = "/tmp/other/SKILL.md"\nenabled = true\n\n'
        first = subprocess.check_output(["sh", "-c", script.decode()], input=existing.encode()).decode()
        second = subprocess.check_output(["sh", "-c", script.decode()], input=first.encode()).decode()
        self.assertEqual(first, second)
        parsed = tomllib.loads(first)
        self.assertEqual(parsed["model"], "gpt-6-astra")
        self.assertEqual(parsed["skills"]["state"], "keep")
        target = Path.home() / ".agents/skills/company-imagegen-fallback/SKILL.md"
        matches = [entry for entry in parsed["skills"]["config"] if entry.get("path") == str(target)]
        self.assertEqual(len(matches), 1)
        self.assertFalse(matches[0]["enabled"])


if __name__ == "__main__": unittest.main()
