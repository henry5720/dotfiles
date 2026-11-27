#!/usr/bin/env python3
"""裝失敗(ADR 0006、#420):選裝工具裝不起來時略過、apply 最後列出、下次 apply 重試;基底裝失敗才讓 apply 停。

渲染真的腳本(--override-data 釘成有 root 的 Ubuntu),PATH 換成假的 dpkg-query、apt-get、sudo 再執行,
看 exit code、略過彙整檔與重試標記。真的 brew、apt 壞掉要真機(macOS 那支只驗渲染)。
"""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "home/.chezmoiscripts"
PACKAGES = SCRIPTS / "run_onchange_before_install-packages.sh.tmpl"
DARWIN = SCRIPTS / "run_onchange_before_install-packages-darwin.sh.tmpl"
SUMMARY = SCRIPTS / "run_after_zz-root-skipped-summary.sh.tmpl"


class InstallFailedTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.bin = self.home / "fakebin"
        self.bin.mkdir()
        self.state = self.home / ".local/state/dotfiles"
        # 沒裝任何套件;sudo 直接執行後面的指令
        self.fake("dpkg-query", "exit 1")
        self.fake("sudo", 'exec "$@"')

    def tearDown(self):
        self.tmp.cleanup()

    def fake(self, name, body):
        p = self.bin / name
        p.write_text(f"#!/bin/sh\n{body}\n")
        p.chmod(0o755)

    def render(self, path, os_name="linux", tools=("zsh",)):
        data = {"tools": list(tools), "chezmoi": {
            "os": os_name, "arch": "amd64", "uid": "0", "homeDir": str(self.home),
            "kernel": {"osrelease": "6.8.0-1-generic"}, "osRelease": {"id": "ubuntu", "idLike": "debian"}}}
        return subprocess.run(
            ["chezmoi", "--no-tty", "--source", str(ROOT), "--config", str(self.home / "none.toml"),
             "--persistent-state", str(self.home / "state.boltdb"), "--override-data", json.dumps(data),
             "execute-template"],
            input=path.read_text(encoding="utf-8"), capture_output=True, text=True, check=True).stdout

    def run_sh(self, script):
        p = self.home / "script.sh"
        p.write_text(script)
        env = {**os.environ, "PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.home)}
        return subprocess.run(["sh", str(p)], env=env, capture_output=True, text=True)

    # ===============================================================
    # Linux:選裝工具的套件裝失敗略過,基底裝失敗停
    # ===============================================================
    def test_tool_package_failure_skips_and_marks_retry(self):
        # 基底裝得起來,zsh(選裝工具)那次失敗
        self.fake("apt-get", 'case "$*" in *zsh*) exit 100 ;; esac; exit 0')
        run = self.run_sh(self.render(PACKAGES))
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("zsh", (self.state / "install-failed").read_text())
        self.assertTrue((self.state / "retry/install-packages").exists())

    def test_base_package_failure_stops_apply(self):
        self.fake("apt-get", 'case "$*" in *install*) exit 100 ;; esac; exit 0')
        run = self.run_sh(self.render(PACKAGES))
        self.assertNotEqual(run.returncode, 0)
        self.assertFalse((self.state / "install-failed").exists())

    def test_retry_marker_changes_script_and_is_cleared_on_success(self):
        before = self.render(PACKAGES)
        (self.state / "retry").mkdir(parents=True)
        (self.state / "retry/install-packages").touch()
        after = self.render(PACKAGES)
        # 內容不同,run_onchange_ 才會在下次 apply 重跑
        self.assertNotEqual(before, after)
        self.assertIn("這次重跑", after)
        self.fake("apt-get", "exit 0")
        self.assertEqual(self.run_sh(after).returncode, 0)
        self.assertFalse((self.state / "retry/install-packages").exists())

    # ===============================================================
    # macOS:brew bundle 失敗不讓 apply 停
    # ===============================================================
    def test_darwin_brew_bundle_failure_skips(self):
        self.fake("brew", 'case "$1" in bundle) cat >/dev/null; exit 1 ;; esac; exit 0')
        run = self.run_sh(self.render(DARWIN, os_name="darwin", tools=("bat",)))
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("bat", (self.state / "install-failed").read_text())
        self.assertTrue((self.state / "retry/install-packages-darwin").exists())

    # ===============================================================
    # 彙整:每台都有,列出裝失敗那段後刪掉,重試標記留著
    # ===============================================================
    def test_summary_lists_install_failed(self):
        script = self.render(SUMMARY)
        self.assertTrue(script.startswith("#!"))
        self.state.joinpath("retry").mkdir(parents=True)
        (self.state / "install-failed").write_text("- zsh:修好再 apply\n")
        (self.state / "retry/install-packages").touch()
        run = self.run_sh(script)
        self.assertIn("== 這次裝失敗", run.stdout)
        self.assertIn("- zsh:修好再 apply", run.stdout)
        self.assertFalse((self.state / "install-failed").exists())
        self.assertTrue((self.state / "retry/install-packages").exists())


if __name__ == "__main__":
    unittest.main()
