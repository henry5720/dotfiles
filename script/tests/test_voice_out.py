#!/usr/bin/env python3
"""voice-out(#290):開關朗讀串流服務(snapserver 的 user service voice-out.service)。

假的 systemctl、loginctl、tailscale 放在 PATH 最前面,記下收到的參數;服務狀態由一個檔案決定。
不用真的 systemd,也不碰這台的 user service。真的起 snapserver、看 port 綁哪裡由 e2e 的 ubuntu 目標驗。
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VOICE_OUT = ROOT / "home/dot_local/bin/executable_voice-out"


class VoiceOutTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.home = self.dir / "home"
        (self.home / ".config/snapserver").mkdir(parents=True)
        self.write_conf("100.64.0.7")
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        self.log = self.dir / "calls.log"
        self.state = self.dir / "active"  # 存在 = 服務在跑
        self.linger = "yes"
        self.tailnet_ip = "100.64.0.7"

    def tearDown(self):
        self.tmp.cleanup()

    # ===============================================================
    # 共用
    # ===============================================================
    def write_conf(self, ip):
        (self.home / ".config/snapserver/snapserver.conf").write_text(
            f"# 現在綁的位址:{ip}\n[http]\nbind_to_address = {ip}\nport = 1780\n"
            f"[stream]\nbind_to_address = {ip}\nport = 1704\n", encoding="utf-8")

    def fake(self, name, body):
        path = self.bin / name
        path.write_text(f"#!/bin/sh\necho \"{name} $*\" >> {self.log}\n{body}\n", encoding="utf-8")
        path.chmod(0o755)

    def run_voice_out(self, *args):
        state = self.state
        self.fake("systemctl", f"""
case "$*" in
  *is-active*) [ -e {state} ] && {{ echo active; exit 0; }}; echo inactive; exit 3;;
  *start*) touch {state};;
  *stop*) rm -f {state};;
esac
exit 0""")
        self.fake("loginctl", f"echo Linger={self.linger}")
        self.fake("tailscale", f'[ -n "{self.tailnet_ip}" ] && echo {self.tailnet_ip} || exit 1')
        env = {"PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.home), "USER": "e2e"}
        return subprocess.run(["sh", str(VOICE_OUT), *args], env=env, capture_output=True, text=True)

    def calls(self):
        return self.log.read_text(encoding="utf-8").splitlines() if self.log.exists() else []

    # ===============================================================
    # status:服務沒在跑 exit 非 0(朗讀指令靠這個判斷要不要寫 pipe)
    # ===============================================================
    def test_status_when_stopped(self):
        run = self.run_voice_out("status")
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("停止", run.stdout)

    def test_status_when_running_shows_where_to_connect(self):
        self.state.touch()
        run = self.run_voice_out("status")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("在跑", run.stdout)
        self.assertIn("100.64.0.7", run.stdout)

    def test_status_warns_when_bound_to_loopback(self):
        # apply 時 tailscale 還沒 up:設定綁 127.0.0.1,個人電腦連不到,要提醒再 apply 一次
        self.write_conf("127.0.0.1")
        run = self.run_voice_out("status")
        self.assertIn("chezmoi apply", run.stdout + run.stderr)

    def test_status_warns_when_tailnet_ip_changed(self):
        self.tailnet_ip = "100.64.0.9"
        run = self.run_voice_out("status")
        self.assertIn("chezmoi apply", run.stdout + run.stderr)

    # ===============================================================
    # on／off:包 user service,不 enable(不開機自動啟動)
    # ===============================================================
    def test_on_starts_user_service_without_enabling(self):
        run = self.run_voice_out("on")
        self.assertEqual(run.returncode, 0, run.stderr)
        calls = self.calls()
        self.assertIn("systemctl --user start voice-out.service", calls)
        self.assertFalse([c for c in calls if " enable" in c])
        self.assertTrue(self.state.exists())

    def test_on_warns_without_linger(self):
        self.linger = "no"
        run = self.run_voice_out("on")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("enable-linger", run.stdout + run.stderr)

    def test_off_stops_user_service(self):
        self.state.touch()
        run = self.run_voice_out("off")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("systemctl --user stop voice-out.service", self.calls())
        self.assertFalse(self.state.exists())

    def test_unknown_argument_prints_usage(self):
        run = self.run_voice_out("bogus")
        self.assertEqual(run.returncode, 2)
        self.assertIn("voice-out on", run.stderr)


if __name__ == "__main__":
    unittest.main()
