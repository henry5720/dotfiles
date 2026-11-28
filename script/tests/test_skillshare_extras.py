#!/usr/bin/env python3
"""chezmoi 釘進 skillshare config.yaml 的部分:targets 段與指令檔(Instructions)的 extras 段,都照選單勾的 client 產生。
另外驗沒勾的 client 不部署它的設定目錄(.chezmoiignore)。

指令檔內容在 agent-config 的 extras/,由那邊的 tests/ 驗;這裡只驗 config.yaml 釘的內容與 extras 連出來的位置。
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "home/dot_config/skillshare/modify_config.yaml.tmpl"
# Windows 版(#321):skillshare 讀 %AppData%\skillshare\config.yaml,同一個行為的 modify-template
WINDOWS_CONFIG = "AppData/Roaming/skillshare/config.yaml"
AGENTS_MD = ".config/skillshare/extras/agents-md/AGENTS.md"
AGENT_COMMIT = ".config/skillshare/extras/agent-commit/instructions.md"
OPENCODE_COMMIT = ".config/skillshare/extras/opencode-commit/commit-instructions.md"
PSTACK_MODELS = ".config/skillshare/extras/pstack-models/pstack-models.md"
# 勾了哪個 client 才有哪幾個連結;任一個 agent 都有 agent-commit
LINKS = {
    # 一份 AGENTS.md,Claude 讀的檔名是 CLAUDE.md
    # pstack 的模型設定只給 claude(官方 pstack 只支援 Cursor 與 Claude Code)
    "claude": {".claude/CLAUDE.md": AGENTS_MD, ".claude/rules/pstack-models.md": PSTACK_MODELS},
    "codex": {".codex/AGENTS.md": AGENTS_MD},
    # commit 指引:路徑要對上 AGENTS.md 與 opencode.json 引用的位置
    "opencode": {
        ".config/opencode/AGENTS.md": AGENTS_MD,
        ".config/opencode/routes/personal/AGENTS.md": AGENTS_MD,
        ".config/opencode/commit-instructions.md": OPENCODE_COMMIT,
    },
}
ALL = ["claude", "codex", "opencode", "agent-config"]
# skillshare init／extras 指令存檔後的樣子:加 schema 註解、重排 key、extras 放在 preserve_tilde_on_save 前面。
# targets 多一個手動 `skillshare target add` 加的 gemini,claude 的 agents 路徑是舊的
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
  gemini:
    skills:
      path: ~/.gemini/skills

extras:
  - name: old
    source: ~/old
    file: OLD.md
    targets:
      - path: ~/.old

preserve_tilde_on_save: true
"""
# agents 排在 skills 後面,跟 skillshare 存檔的順序一樣
CLAUDE_TARGET = """\
  claude:
    skills:
      path: ~/.claude/skills
    agents:
      path: ~/.claude/agents
"""
CODEX_TARGET = """\
  codex:
    skills:
      path: ~/.agents/skills
"""


class SkillshareConfigTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        self.cfg = Path(self.tmp.name) / "chezmoi.toml"
        self.cfg.write_text("", encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def chezmoi(self, tools, *args, **kw):
        return subprocess.check_output([
            "chezmoi", "--source", str(ROOT), "--config", str(self.cfg),
            "--destination", str(self.home), "--override-data",
            json.dumps({"chezmoi": {"homeDir": str(self.home)}, "tools": tools}), *args,
        ], **kw).decode()

    def run_script(self, tools, existing=""):
        script = self.chezmoi(tools, "execute-template", input=CONFIG.read_bytes())
        return subprocess.run(
            ["sh", "-c", script], input=existing, text=True, capture_output=True, check=True,
        ).stdout

    def section(self, out, key):
        """頂層 key 那一段(含 key 那行),到下一個頂層 key 之前;沒有就是空字串。"""
        lines, keep = [], False
        for line in out.splitlines(keepends=True):
            if line[:1] not in ("", " ", "-", "\n"):
                keep = line.startswith(key + ":")
            if keep:
                lines.append(line)
        return "".join(lines).rstrip("\n") + "\n" if lines else ""

    def extras_paths(self, out):
        return [l.strip().removeprefix("- path: ") for l in self.section(out, "extras").splitlines()
                if l.strip().startswith("- path: ")]

    # ===============================================================
    # targets 與 extras 照勾的 client
    # ===============================================================
    def test_only_claude_targets_claude_and_links_claude_md_and_agent_commit(self):
        out = self.run_script(["claude", "agent-config"])
        self.assertEqual(self.section(out, "targets"), "targets:\n" + CLAUDE_TARGET)
        self.assertEqual(self.extras_paths(out), ["~/.claude", "~/.config/agent-commit", "~/.claude/rules"])
        self.assertIn("as: CLAUDE.md", out)

    def test_all_clients_target_claude_and_codex_but_not_opencode(self):
        out = self.run_script(ALL)
        self.assertEqual(self.section(out, "targets"), "targets:\n" + CLAUDE_TARGET + CODEX_TARGET)
        self.assertEqual(self.extras_paths(out), [
            "~/.claude", "~/.codex", "~/.config/opencode", "~/.config/opencode/routes/personal",
            "~/.config/agent-commit", "~/.claude/rules", "~/.config/opencode",
        ])
        # 來源用 skillshare 預設的 ~/.config/skillshare/extras/<name>/,不寫 source
        self.assertNotIn("source:", self.section(out, "extras"))

    def test_only_opencode_has_no_target_but_its_extras(self):
        out = self.run_script(["opencode", "agent-config"])
        self.assertEqual(self.section(out, "targets"), "targets: {}\n")
        self.assertEqual(self.extras_paths(out), [
            "~/.config/opencode", "~/.config/opencode/routes/personal",
            "~/.config/agent-commit", "~/.config/opencode",
        ])

    def test_no_agent_has_no_targets_and_drops_extras(self):
        out = self.run_script(["agent-config"], SAVED_BY_SKILLSHARE)
        self.assertEqual(self.section(out, "targets"), "targets: {}\n")
        self.assertNotIn("extras", out)
        self.assertNotIn("\n\n\n", out)
        self.assertTrue(out.endswith("targets: {}\n\npreserve_tilde_on_save: true\n"))
        self.assertEqual(self.run_script(["agent-config"], out), out)

    # ===============================================================
    # 每次 apply 都釘回去,其餘照 skillshare 寫的留著
    # ===============================================================
    def test_new_machine_gets_base_config(self):
        out = self.run_script(ALL)
        self.assertIn("git_root: root\n", out)
        self.assertIn("preserve_tilde_on_save: true\n", out)
        self.assertEqual(out.count("\ntargets:\n"), 1)
        self.assertEqual(out.count("\nextras:\n"), 1)
        self.assertEqual(self.run_script(ALL, out), out)

    def test_manual_target_and_extras_are_overwritten_in_place(self):
        out = self.run_script(ALL, SAVED_BY_SKILLSHARE)
        for gone in ("gemini", "old-agents", "name: old"):
            self.assertNotIn(gone, out)
        before = SAVED_BY_SKILLSHARE.split("targets:\n")[0]
        self.assertTrue(out.startswith(before + "targets:\n" + CLAUDE_TARGET + CODEX_TARGET + "\nextras:\n"))
        self.assertTrue(out.endswith("      - path: ~/.config/opencode\n\npreserve_tilde_on_save: true\n"))
        self.assertEqual(self.run_script(ALL, out), out)

    def test_appends_targets_and_extras_when_missing(self):
        existing = "git_root: root\n\npreserve_tilde_on_save: true\n"
        out = self.run_script(["claude", "agent-config"], existing)
        self.assertTrue(out.startswith(existing + "\ntargets:\n" + CLAUDE_TARGET + "\nextras:\n"))
        self.assertEqual(self.run_script(["claude", "agent-config"], out), out)

    # ===============================================================
    # Windows:同一套行為,路徑換成 Windows 的(#321)
    # ===============================================================
    def run_windows(self, tools, existing=None):
        """把 existing(None = 檔案不存在)放到 Windows 的位置,回傳 chezmoi 算出的新內容。"""
        target = self.home / WINDOWS_CONFIG
        target.unlink(missing_ok=True)
        if existing is not None:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(existing, encoding="utf-8")
        override = {"chezmoi": {"os": "windows", "homeDir": str(self.home), "kernel": {"osrelease": ""}},
                    "tools": tools}
        return subprocess.check_output([
            "chezmoi", "--source", str(ROOT), "--config", str(self.cfg), "--destination", str(self.home),
            "--override-data", json.dumps(override), "cat", str(target),
        ]).decode()

    @staticmethod
    def windowsify(text):
        """Linux 的路徑換成 skillshare 在 Windows 存檔的樣子:設定目錄在 %AppData%,~ 開頭的路徑用反斜線。"""
        text = text.replace("~/.config/skillshare", "~/AppData/Roaming/skillshare")
        return re.sub(r"~/\S*", lambda m: m.group(0).replace("/", "\\"), text)

    def test_windows_paths_use_appdata_and_backslashes(self):
        out = self.run_windows(ALL)
        self.assertIn("      path: ~\\.claude\\skills\n", out)
        self.assertNotIn("source:", self.section(out, "extras"))
        self.assertIn("  skills: ~\\AppData\\Roaming\\skillshare\\skills\n", out)
        self.assertNotIn("/", out)
        self.assertNotIn(".config\\skillshare", out)

    def test_windows_opencode_skips_personal_route(self):
        # routes/personal 給只有 Linux 的 opencode-personal 用,Windows 不部署它(#318),指令檔也不連過去
        self.assertEqual(self.extras_paths(self.run_windows(["opencode", "agent-config"])), [
            "~\\.config\\opencode", "~\\.config\\agent-commit", "~\\.config\\opencode",
        ])

    def test_windows_matches_linux_for_same_input(self):
        # Windows 沒有 sh,另寫一份 Go template;同一批輸入,輸出要跟 Linux 那份只差路徑
        cases = [
            (ALL, None), (ALL, SAVED_BY_SKILLSHARE), (["claude", "agent-config"], SAVED_BY_SKILLSHARE),
            (["opencode", "agent-config"], None), (["agent-config"], SAVED_BY_SKILLSHARE),
            # 整段拿掉的 extras 後面多幾行空白:沿用它前面的空行
            (["agent-config"], SAVED_BY_SKILLSHARE.replace("\n\npreserve_tilde", "\n\n\n\npreserve_tilde")),
            (["claude", "agent-config"], "git_root: root\n\npreserve_tilde_on_save: true\n"),
            (ALL, SAVED_BY_SKILLSHARE.replace("\nextras:", "\n\n\n# 手寫的註解\nextras:") + "\n\n"),
        ]
        for tools, existing in cases:
            with self.subTest(tools=tools, existing=(existing or "")[:40]):
                linux = self.run_script(tools, existing or "")
                win = self.run_windows(tools, None if existing is None else self.windowsify(existing))
                # Windows 只少 opencode 的 routes/personal 那個目標(見上一個測試)
                route = "      - path: ~\\.config\\opencode\\routes\\personal\n"
                self.assertEqual(win, self.windowsify(linux).replace(route, ""))
                self.assertEqual(self.run_windows(tools, win), win)

    # ===============================================================
    # 沒勾的 client 不部署設定目錄
    # ===============================================================
    def test_unchecked_clients_config_dirs_are_ignored(self):
        dirs = {".claude", ".codex", ".config/opencode", ".config/skillshare"}
        cases = {
            (): dirs,
            ("claude", "agent-config"): {".codex", ".config/opencode"},
            tuple(ALL): set(),
        }
        for tools, expected in cases.items():
            with self.subTest(tools=tools):
                ignored = set(self.chezmoi(list(tools), "ignored").split())
                self.assertEqual(ignored & dirs, expected)

    # ===============================================================
    # skillshare 真的照釘的 extras 連出來
    # ===============================================================
    @unittest.skipUnless(shutil.which("skillshare"), "沒有 skillshare")
    def test_sync_links_only_checked_clients(self):
        for tools in (ALL, ["claude", "agent-config"]):
            with self.subTest(tools=tools):
                self.tearDown()
                self.setUp()
                source = self.home / ".config/skillshare"
                (source / "skills").mkdir(parents=True)  # 沒有 skills 來源 sync 會直接失敗
                (source / "config.yaml").write_text(self.run_script(tools), encoding="utf-8")
                for target in (AGENTS_MD, AGENT_COMMIT, OPENCODE_COMMIT, PSTACK_MODELS):
                    (self.home / target).parent.mkdir(parents=True, exist_ok=True)
                    (self.home / target).write_text(target, encoding="utf-8")
                env = os.environ | {"HOME": str(self.home), "XDG_CONFIG_HOME": str(self.home / ".config")}
                subprocess.run(["skillshare", "sync", "extras"], env=env, cwd=self.home,
                               check=True, capture_output=True)
                expected = {".config/agent-commit/instructions.md": AGENT_COMMIT}
                for client in ("claude", "codex", "opencode"):
                    if client in tools:
                        expected |= LINKS[client]
                for link, target in expected.items():
                    path = self.home / link
                    self.assertTrue(path.is_symlink(), link)
                    self.assertEqual(os.readlink(path), str(self.home / target))
                for client, links in LINKS.items():
                    if client not in tools:
                        for link in links:
                            self.assertFalse((self.home / link).exists(), link)


if __name__ == "__main__":
    unittest.main()
