#!/usr/bin/env python3
"""skillshare 設定(create_config.yaml)裡的 extras:指令檔要連到每個 client 讀的位置。

指令檔內容在 agent-config 的 extras/,由那邊的 tests/ 驗;這裡只驗要連到哪(Settings)。
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "home/dot_config/skillshare/create_config.yaml"


def extras_targets():
    """回傳 {extra 名稱: (file, [(path, as), ...])}。設定格式固定,不為此引入 YAML 套件。"""
    extras, current, in_extras = {}, None, False
    for line in CONFIG.read_text(encoding="utf-8").splitlines():
        if line.startswith("extras:"):
            in_extras = True
            continue
        if not in_extras or not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            break
        key, _, value = line.strip().removeprefix("- ").partition(": ")
        if line.startswith("  - name:"):
            current = extras.setdefault(value, [None, []])
        elif key == "file":
            current[0] = value
        elif key == "path":
            current[1].append([value, None])
        elif key == "as":
            current[1][-1][1] = value
    return {name: (file, [tuple(t) for t in targets]) for name, (file, targets) in extras.items()}


class SkillshareExtrasTest(unittest.TestCase):
    # ===============================================================
    # 1. 全域指令檔:一份 AGENTS.md,Claude 讀的檔名是 CLAUDE.md
    # ===============================================================
    def test_agents_md_links_to_every_client(self):
        file, targets = extras_targets()["agents-md"]
        self.assertEqual(file, "AGENTS.md")
        self.assertEqual(targets, [
            ("~/.claude", "CLAUDE.md"),
            ("~/.codex", None),
            ("~/.config/opencode", None),
            ("~/.config/opencode/routes/personal", None),
        ])

    # ===============================================================
    # 2. commit 指引:路徑要對上 AGENTS.md 與 opencode.json 引用的位置
    # ===============================================================
    def test_commit_guides_keep_their_paths(self):
        extras = extras_targets()
        self.assertEqual(extras["agent-commit"],
                         ("instructions.md", [("~/.config/agent-commit", None)]))
        self.assertEqual(extras["opencode-commit"],
                         ("commit-instructions.md", [("~/.config/opencode", None)]))


if __name__ == "__main__":
    unittest.main()
