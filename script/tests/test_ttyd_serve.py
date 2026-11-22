#!/usr/bin/env python3
"""ttyd-serve:印給人貼的 remote-access 那行，密碼不能出現在那行的 argv 裡。

假的 ttyd(只睡著)、ss(沒人在聽)放在 PATH 最前面，不起真的 ttyd、不碰 7681。
真的 ttyd 用 curl 打 header 的實測寫在 docs/how-to/remote-access/ttyd-serve.md。
"""
import base64
import os
import re
import signal
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TTYD_SERVE = ROOT / "home/dot_local/bin/executable_ttyd-serve"


class TtydServeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        bin_dir = self.dir / "bin"
        bin_dir.mkdir()
        for name, body in (("ttyd", "exec sleep 30"), ("ss", "exit 0")):
            (bin_dir / name).write_text(f"#!/bin/sh\n{body}\n")
            (bin_dir / name).chmod(0o755)
        self.tmpdir = self.dir / "tmp"
        self.tmpdir.mkdir()
        env = {"PATH": f"{bin_dir}:/usr/bin:/bin", "HOME": str(self.dir), "TMPDIR": str(self.tmpdir)}
        self.proc = subprocess.Popen(["bash", str(TTYD_SERVE), "true"], env=env, text=True,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(self.proc.kill)
        self.out = ""
        for line in self.proc.stdout:
            self.out += line
            if "--auth-header-cmd" in line:
                break

    def test_header_file_is_private_and_printed_line_only_cats_it(self):
        pw = re.search(r"密碼 (\S+)", self.out).group(1)
        path = Path(re.search(r"--auth-header-cmd 'cat ([^']+)'", self.out).group(1))
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        auth = base64.b64encode(f"guest:{pw}".encode()).decode()
        self.assertEqual(path.read_text(), f"Authorization: Basic {auth}\n")
        self.assertNotIn(auth, self.out)

    def test_header_file_removed_when_ttyd_serve_exits(self):
        path = Path(re.search(r"--auth-header-cmd 'cat ([^']+)'", self.out).group(1))
        self.proc.send_signal(signal.SIGTERM)
        self.proc.wait(timeout=10)
        self.assertFalse(path.exists())
        self.assertEqual(list(self.tmpdir.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
