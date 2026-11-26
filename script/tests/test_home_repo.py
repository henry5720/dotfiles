#!/usr/bin/env python3
"""home repo 的位置(#411):init 問一次 homeRepo(Windows 也問),三個用到它的檔照它渲染。

沒有這個 key 的舊 config 當 ~/code;\\ 換成 /、結尾固定一個 /。git 的 gitdir:、opencode 的 glob 原樣用 ~,
codegraph-setup-repo 是 shell,~ 展開成 $HOME。環境用 --override-data 模擬,在 Linux 上直接渲染。
"""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG_TEMPLATE = ROOT / "home/.chezmoi.toml.tmpl"
# 提示文字(要跟 config 樣板一字不差,同 e2e.sh 的 INIT_FLAGS)
HOME_REPO_PROMPT = "home repo 的位置"
USE_PROMPT = "用途：按一個字母（full 完整／minimal 精簡：只要 shell 體驗／custom 自訂）"


class HomeRepoTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        self.cfg = Path(self.tmp.name) / "chezmoi.toml"
        self.cfg.write_text("", encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def chezmoi(self, *args, os_name="linux", data=None):
        # 真的 Windows 沒有 kernel 欄位(同 test_windows.py)
        info = {"os": os_name, "homeDir": str(self.home), "kernel": {"osrelease": "6.8.0-1-generic" if os_name == "linux" else ""}}
        return subprocess.run([
            "chezmoi", "--no-tty", "--source", str(ROOT), "--config", str(self.cfg),
            "--destination", str(self.home), "--override-data", json.dumps({"chezmoi": info} | (data or {})), *args,
        ], stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True).stdout

    def cat(self, target, home_repo=None, **kw):
        data = kw.pop("data", {})
        if home_repo is not None:
            data["homeRepo"] = home_repo
        return self.chezmoi("cat", str(self.home / target), data=data, **kw)

    def init(self, *flags, os_name="linux"):
        return self.chezmoi("execute-template", "--init", "--promptChoice", f"{USE_PROMPT}=m", *flags,
                            CONFIG_TEMPLATE.read_text(encoding="utf-8"), os_name=os_name)

    # ===============================================================
    # init 問 homeRepo:每台都問(Windows 也問),存過不再問
    # ===============================================================
    def test_init_defaults_to_code_on_linux_and_windows(self):
        for os_name in ("linux", "windows"):
            with self.subTest(os=os_name):
                self.assertIn('\n    homeRepo = "~/code"\n', self.init(os_name=os_name))

    def test_windows_keeps_backslash_path_as_typed(self):
        out = self.init("--promptString", f"{HOME_REPO_PROMPT}=D:\\code", os_name="windows")
        self.assertIn('\n    homeRepo = "D:\\\\code"\n', out)
        # git 身分照舊不問(Windows 不部署 .gitconfig)
        self.assertNotIn("gitUser", out)

    def test_stored_home_repo_is_not_asked_again(self):
        self.cfg.write_text('[data]\n    homeRepo = "D:/code"\n', encoding="utf-8")
        out = self.init("--promptString", f"{HOME_REPO_PROMPT}=~/other", os_name="windows")
        self.assertIn('\n    homeRepo = "D:/code"\n', out)

    # ===============================================================
    # git 的 includeIf:~ 原樣給 git
    # ===============================================================
    def includeif(self, home_repo):
        out = self.cat(".config/git/config", home_repo)
        return [l for l in out.splitlines() if l.startswith("[includeIf ")]

    def test_git_includeif_follows_home_repo(self):
        for home_repo, want in ((None, "~/code/"), ("D:\\code", "D:/code/"), ("~/home-repo/", "~/home-repo/"),
                                ("/srv/code", "/srv/code/"),
                                # 結尾多個斜線只留一個;只剩根目錄、~、磁碟機時照樣補一個
                                ("~/code//", "~/code/"), ("D:\\code\\\\", "D:/code/"),
                                ("~", "~/"), ("D:\\", "D:/"), ("/", "/")):
            with self.subTest(home_repo=home_repo):
                self.assertEqual(self.includeif(home_repo), [f'[includeIf "gitdir:{want}"]'])

    # ===============================================================
    # opencode 的 external_directory(Windows 也部署)
    # ===============================================================
    def allowed_dirs(self, home_repo, os_name):
        out = self.cat(".config/opencode/opencode.json", home_repo, os_name=os_name,
                       data={"tools": ["opencode"], "codexLbApiKey": "fixture"})
        return set(json.loads(out)["permission"]["external_directory"])

    def test_opencode_allows_home_repo(self):
        for home_repo, os_name, want in ((None, "linux", "~/code/**"), ("D:\\code", "windows", "D:/code/**"),
                                         ("~/home-repo/", "linux", "~/home-repo/**")):
            with self.subTest(home_repo=home_repo, os=os_name):
                dirs = self.allowed_dirs(home_repo, os_name)
                self.assertIn(want, dirs)
                self.assertNotIn("~/code/**", dirs - {want})

    # ===============================================================
    # codegraph-setup-repo:shell 不展開引號裡的 ~,渲染成 $HOME
    # ===============================================================
    def test_codegraph_setup_repo_scans_home_repo(self):
        for home_repo, want in ((None, '"$HOME/code/"*/'), ("~/home-repo/", '"$HOME/home-repo/"*/'),
                                ("/srv/code", '"/srv/code/"*/')):
            with self.subTest(home_repo=home_repo):
                out = self.cat(".local/bin/codegraph-setup-repo", home_repo)
                self.assertEqual([l.strip() for l in out.splitlines() if l.strip().startswith("for d in ")],
                                 [f"for d in {want}; do"])
                subprocess.run(["bash", "-n"], input=out, text=True, check=True)


if __name__ == "__main__":
    unittest.main()
