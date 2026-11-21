#!/usr/bin/env python3
"""markdown 連結檢查(#367,spec #366):相對連結的目標存在、#錨點對得到標題(GitHub 的 slug 規則),
有 agent-config checkout 時連兩個 repo 互連的 github.com/henry5720/<repo>/blob/main/... 與 repo 根網址也一起查。

後面搬檔、改標題的 ticket 都靠這支確認連結沒斷。不查外部網址(http、mailto)、不查 code block 與 inline code 裡的連結。
AGENT_CONFIG_DIR 跟 e2e 同一個變數(預設 ~/.config/skillshare),找不到就略過跨 repo 的部分。
"""
import os
import re
import tempfile
import unittest
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]
AGENT_CONFIG = Path(os.environ.get("AGENT_CONFIG_DIR", Path.home() / ".config/skillshare"))
# dotfiles 的 docs/superpowers/ 是當初的 spec / plan,歷史紀錄不是現況(AGENTS.md「文件放哪」),連結斷了也不修;
# agent-config 沒有歷史紀錄資料夾,tests/fixtures/ 是測試用的假 PR body,裡面的截圖連結本來就不存在
EXCLUDE = {"dotfiles": ("docs/superpowers/",), "agent-config": ("tests/fixtures/",)}
# repo 根網址(github.com/henry5720/<repo>#錨點)GitHub 顯示的是 README.md
GITHUB = re.compile(r"https://github\.com/henry5720/([\w-]+)(?:/blob/main/([^)#\s>]*)|/?)(#[^)\s>]*)?")


# ===============================================================
# 讀 markdown:連結與標題(都略過 fenced code block 與 inline code)
# ===============================================================
FENCE = re.compile(r"^\s*(```|~~~)")
INLINE_CODE = re.compile(r"(`+).*?\1")
# [text](target "title")、![alt](target)、<target> 形式;reference 定義 [x]: target
INLINE_LINK = re.compile(r"\]\(\s*(<[^>]*>|[^)\s]*)")
REF_DEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*(<[^>]*>|\S+)")
HEADING = re.compile(r"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
HTML_ID = re.compile(r"""<a\s[^>]*(?:name|id)=["']([^"']+)["']""")


def prose_lines(text):
    """(行號, 行) —— 去掉 frontmatter、fenced code block。"""
    lines = text.splitlines()
    start = 0
    if lines and lines[0].strip() == "---":
        end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
        if end is not None:
            start = end + 1
    fence = None
    for i in range(start, len(lines)):
        line = lines[i]
        m = FENCE.match(line)
        if m:
            if fence is None:
                fence = m.group(1)
            elif m.group(1) == fence:
                fence = None
            continue
        if fence is None:
            yield i + 1, line


def links(text):
    for no, line in prose_lines(text):
        line = INLINE_CODE.sub(" ", line)
        for m in list(INLINE_LINK.finditer(line)) + list(REF_DEF.finditer(line)):
            yield no, m.group(1).strip("<>")


def slug(heading):
    """GitHub 的錨點:去掉 markdown 格式 → 小寫 → 拿掉字母數字底線連字號空白以外的字 → 空白換連字號。"""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)  # 連結只留文字
    text = re.sub(r"<[^>]+>", "", text).replace("`", "").replace("*", "")
    return re.sub(r"[^\w\- ]", "", text.lower()).replace(" ", "-")


def anchors(path):
    """一個檔案所有的錨點;重複的標題照 GitHub 加 -1、-2。"""
    seen, out = {}, set()
    text = path.read_text(encoding="utf-8")
    for _, line in prose_lines(text):
        out.update(HTML_ID.findall(line))
        m = HEADING.match(line)
        if not m:
            continue
        base = slug(m.group(2))
        n = seen.get(base, 0)
        seen[base] = n + 1
        out.add(base if n == 0 else f"{base}-{n}")
    return out


# ===============================================================
# 檢查
# ===============================================================
def md_files(root, exclude):
    for path in sorted(root.rglob("*.md")):
        rel = path.relative_to(root).as_posix()
        if ".git/" not in rel and not rel.startswith(".git") and not rel.startswith(exclude):
            yield path


def problem(target, anchor, repos):
    """一個連結的問題;沒問題回 None。target 是本機路徑,anchor 不含 #(可能是空字串)。"""
    if not target.exists():
        return "目標不存在"
    if not anchor or target.is_dir() or target.suffix != ".md" or re.fullmatch(r"L\d+(-L\d+)?", anchor):
        return None  # 非 markdown 的錨點(例如程式碼的 #L12)GitHub 才有,本機查不了
    if unquote(anchor).lower() not in anchors(target):
        return f"{shown(target, repos)} 沒有 #{anchor} 這個標題"
    return None


def shown(target, repos):
    """訊息裡的路徑:在本 repo 寫相對路徑,在另一個 repo 前面加 repo 名稱。"""
    for i, (name, base) in enumerate(repos.items()):
        base = base.resolve()
        if target.is_relative_to(base):
            rel = target.relative_to(base).as_posix()
            return rel if i == 0 else f"{name}/{rel}"
    return str(target)


def check(root, repos, exclude=()):
    """root 底下所有 .md 的斷連結,每筆是「檔案:行 → 連結 → 原因」。

    repos:repo 名稱 → 本機路徑,github.com/henry5720/<名稱>/blob/main/ 網址照這個對應;不在裡面的 repo 不查。
    """
    out = []
    for path in md_files(root, exclude):
        for no, link in links(path.read_text(encoding="utf-8")):
            gh = GITHUB.fullmatch(link)
            if gh:
                if gh.group(1) not in repos:
                    continue
                target = repos[gh.group(1)] / unquote(gh.group(2) if gh.group(2) is not None else "README.md")
                anchor = (gh.group(3) or "#")[1:]
            elif re.match(r"[a-z][a-z0-9+.-]*:", link, re.I) or not link:
                continue  # 外部網址、mailto、空連結
            else:
                file, _, anchor = link.partition("#")
                target = path.parent / unquote(file) if file else path
            reason = problem(target.resolve(), anchor, {"": root, **repos})
            if reason:
                out.append(f"{path.relative_to(root)}:{no} → {link} → {reason}")
    return out


# ===============================================================
# 檢查本身:故意弄斷的連結要抓得到
# ===============================================================
class CheckTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.a = Path(tmp.name) / "dotfiles"
        self.b = Path(tmp.name) / "agent-config"
        for p in (self.a / "docs", self.b):
            p.mkdir(parents=True)
        (self.a / "docs/target.md").write_text(
            "# 改設定與更新\n\n## Setup (macOS)\n\n## 重複\n\n## 重複\n\n## `chezmoi` 指令\n", encoding="utf-8")
        (self.b / "skill.md").write_text("# 怎麼接瀏覽器\n", encoding="utf-8")
        self.repos = {"dotfiles": self.a, "agent-config": self.b}

    def write(self, root, name, text):
        (root / name).write_text(text, encoding="utf-8")
        return check(root, self.repos)

    def test_good_links_pass(self):
        self.assertEqual(self.write(self.a, "README.md", "\n".join([
            "[a](docs/target.md)",
            "[b](docs/target.md#改設定與更新)",
            "[c](docs/target.md#setup-macos)",
            "[d](docs/target.md#重複-1)",
            "[e](docs/target.md#chezmoi-指令)",
            "[f](#本檔)",
            "[g](docs/)",
            "[h](https://example.com/x.md) [i](mailto:a@b.c)",
            "[j](https://github.com/henry5720/agent-config/blob/main/skill.md#怎麼接瀏覽器)",
            "`[k](不存在.md)`",
            "```", "[l](不存在.md)", "```",
            "[m]: docs/target.md",
            "# 本檔",
        ])), [])

    def test_broken_relative_link(self):
        self.assertEqual(self.write(self.a, "README.md", "x\n[壞](docs/nope.md)\n"),
                         ["README.md:2 → docs/nope.md → 目標不存在"])

    def test_broken_anchor(self):
        self.assertEqual(self.write(self.a, "README.md", "[壞](docs/target.md#重複-2)\n[同檔](#沒有)\n"), [
            "README.md:1 → docs/target.md#重複-2 → docs/target.md 沒有 #重複-2 這個標題",
            "README.md:2 → #沒有 → README.md 沒有 #沒有 這個標題",
        ])

    def test_broken_cross_repo_link(self):
        url = "https://github.com/henry5720/dotfiles/blob/main/docs/target.md#沒有"
        gone = "https://github.com/henry5720/agent-config/blob/main/nope.md"
        self.assertEqual(self.write(self.b, "README.md", f"[壞]({url})\n[壞]({gone})\n"), [
            f"README.md:1 → {url} → dotfiles/docs/target.md 沒有 #沒有 這個標題",
            f"README.md:2 → {gone} → 目標不存在",
        ])

    def test_repo_root_url_checks_readme(self):
        good = "https://github.com/henry5720/dotfiles#readme-的標題"
        bad = "https://github.com/henry5720/dotfiles#沒有"
        (self.a / "README.md").write_text("# README 的標題\n", encoding="utf-8")
        self.assertEqual(self.write(self.b, "README.md", f"[好]({good})\n[壞]({bad})\n"), [
            f"README.md:2 → {bad} → dotfiles/README.md 沒有 #沒有 這個標題",
        ])

    def test_repo_without_checkout_is_skipped(self):
        (self.a / "README.md").write_text(
            "[x](https://github.com/henry5720/agent-config/blob/main/nope.md)\n", encoding="utf-8")
        self.assertEqual(check(self.a, {"dotfiles": self.a}), [])


# ===============================================================
# 真的 repo
# ===============================================================
def report(problems):
    return f"{len(problems)} 個斷掉的連結:\n" + "\n".join(problems)


class RepoLinksTest(unittest.TestCase):
    def test_this_repo(self):
        problems = check(ROOT, {"dotfiles": ROOT}, EXCLUDE["dotfiles"])
        self.assertEqual(problems, [], report(problems))

    def agent_config(self):
        if not AGENT_CONFIG.is_dir():
            self.skipTest(f"沒有 agent-config checkout({AGENT_CONFIG}),設 AGENT_CONFIG_DIR 指過去")
        return {"dotfiles": ROOT, "agent-config": AGENT_CONFIG}

    def test_this_repo_to_agent_config(self):
        repos = self.agent_config()
        problems = [p for p in check(ROOT, repos, EXCLUDE["dotfiles"]) if "henry5720/agent-config" in p]
        self.assertEqual(problems, [], report(problems))

    def test_agent_config(self):
        """agent-config 自己的相對連結,和它連回這邊的網址;斷了要到 agent-config 修。"""
        repos = self.agent_config()
        problems = check(AGENT_CONFIG, repos, EXCLUDE["agent-config"])
        self.assertEqual(problems, [], report(problems))


if __name__ == "__main__":
    unittest.main()
