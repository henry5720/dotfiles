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
        # 跟真的 loginctl 一樣:show-user -p Linger --value 只印值(yes／no)
        self.fake("loginctl", f'case "$*" in *--value*) echo {self.linger};; *) echo Linger={self.linger};; esac')
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

    def test_help_lists_every_subcommand_on_stdout(self):
        for flag in ("help", "-h", "--help"):
            with self.subTest(flag=flag):
                run = self.run_voice_out(flag)
                self.assertEqual(run.returncode, 0, run.stderr)
                for sub in ("on", "off", "status", "skip", "rate", "voice", "voices", "max", "reset", "help"):
                    self.assertRegex(run.stdout, rf"voice-out {sub}\b")

    def test_no_argument_prints_help_to_stderr(self):
        run = self.run_voice_out()
        self.assertEqual(run.returncode, 2)
        self.assertIn("voice-out skip", run.stderr)
        self.assertEqual(run.stdout, "")

    def test_extra_argument_prints_usage(self):
        self.assertEqual(self.run_voice_out("on", "now").returncode, 2)
        self.assertEqual(self.run_voice_out("rate", "+1%", "+2%").returncode, 2)

    # ===============================================================
    # 朗讀設定(#294):rate／max／voice 存進 ~/.config/voice-out/settings,寫入前檢查;不帶值印目前值
    # ===============================================================
    def settings(self):
        path = self.home / ".config/voice-out/settings"
        return path.read_text(encoding="utf-8") if path.exists() else ""

    def test_rate_is_saved_and_shown(self):
        run = self.run_voice_out("rate", "+20%")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("rate=+20%", self.settings())
        self.assertIn("+20%", self.run_voice_out("rate").stdout)

    def test_rate_without_value_shows_default(self):
        run = self.run_voice_out("rate")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("+0%", run.stdout)

    def test_invalid_rate_is_rejected_and_not_saved(self):
        for value in ("20%", "+20", "快一點", "+2.5%"):
            with self.subTest(value=value):
                run = self.run_voice_out("rate", value)
                self.assertNotEqual(run.returncode, 0)
                self.assertIn("+20%", run.stderr)  # 告訴你格式長怎樣
        self.assertEqual(self.settings(), "")

    def test_max_is_saved_and_zero_means_unlimited(self):
        self.assertEqual(self.run_voice_out("max", "1200").returncode, 0)
        self.assertIn("1200", self.run_voice_out("max").stdout)
        self.assertEqual(self.run_voice_out("max", "0").returncode, 0)
        self.assertIn("不限", self.run_voice_out("max").stdout)
        self.assertIn("max=0", self.settings())
        self.assertEqual(self.settings().count("max="), 1)  # 覆蓋舊值,不是一直往後加

    def test_max_leading_zeros_are_normalized(self):
        self.run_voice_out("max", "0600")
        self.assertIn("600 字元", self.run_voice_out("max").stdout)
        self.run_voice_out("max", "00")
        self.assertIn("不限", self.run_voice_out("max").stdout)

    def test_max_default_is_600(self):
        self.assertIn("600", self.run_voice_out("max").stdout)

    def test_invalid_max_is_rejected(self):
        for value in ("-1", "很多", "1.5"):
            with self.subTest(value=value):
                self.assertNotEqual(self.run_voice_out("max", value).returncode, 0)
        self.assertEqual(self.settings(), "")

    def test_changing_one_setting_keeps_the_others(self):
        self.run_voice_out("rate", "-10%")
        self.run_voice_out("max", "900")
        self.assertIn("rate=-10%", self.settings())
        self.assertIn("max=900", self.settings())

    def test_reset_restores_defaults(self):
        self.run_voice_out("rate", "+20%")
        run = self.run_voice_out("reset")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("+0%", self.run_voice_out("rate").stdout)

    def test_status_shows_reading_settings(self):
        self.run_voice_out("rate", "+20%")
        for running in (False, True):
            with self.subTest(running=running):
                if running:
                    self.state.touch()
                out = self.run_voice_out("status").stdout
                self.assertIn("+20%", out)
                self.assertIn("zh-TW-HsiaoChenNeural", out)
                self.assertIn("600", out)

    # 假 uv:`uv tool run --from edge-tts edge-tts --list-voices` 印 edge-tts 7 的表格;voices_fail 時模擬沒網路
    VOICE_TABLE = """Name                               Gender    ContentCategories      VoicePersonalities
---------------------------------  --------  ---------------------  --------------------------------------
en-US-AriaNeural                   Female    News, Novel            Positive, Confident
zh-CN-XiaoxiaoNeural               Female    News, Novel            Warm
zh-HK-WanLungNeural                Male      General                Friendly, Positive
zh-TW-HsiaoChenNeural              Female    General                Friendly, Positive
zh-TW-YunJheNeural                 Male      General                Friendly, Positive
"""

    def fake_uv(self, fail=False):
        table = self.dir / "voices.txt"
        table.write_text(self.VOICE_TABLE, encoding="utf-8")
        body = "exit 1" if fail else f'[ "$*" = "tool run --from edge-tts edge-tts --list-voices" ] && cat {table}'
        self.fake("uv", body)

    def test_voice_is_saved_when_in_edge_tts_list(self):
        self.fake_uv()
        run = self.run_voice_out("voice", "zh-TW-YunJheNeural")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("voice=zh-TW-YunJheNeural", self.settings())
        self.assertIn("zh-TW-YunJheNeural", self.run_voice_out("voice").stdout)

    def test_unknown_voice_is_rejected(self):
        self.fake_uv()
        run = self.run_voice_out("voice", "zh-TW-NobodyNeural")
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("voice-out voices", run.stderr)
        self.assertEqual(self.settings(), "")

    def test_voice_not_saved_when_list_unavailable(self):
        # 沒網路拿不到清單:不能確認就不存
        self.fake_uv(fail=True)
        run = self.run_voice_out("voice", "zh-TW-YunJheNeural")
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(self.settings(), "")

    def test_voices_lists_chinese_voices_only(self):
        self.fake_uv()
        run = self.run_voice_out("voices")
        self.assertEqual(run.returncode, 0, run.stderr)
        for name in ("zh-CN-XiaoxiaoNeural", "zh-HK-WanLungNeural", "zh-TW-HsiaoChenNeural", "zh-TW-YunJheNeural"):
            self.assertIn(name, run.stdout)
        self.assertNotIn("en-US", run.stdout)
        self.assertIn("Male", run.stdout)  # 帶性別,挑的時候用得到

    def test_settings_can_change_while_service_is_off(self):
        run = self.run_voice_out("rate", "+5%")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertFalse(self.state.exists())


if __name__ == "__main__":
    unittest.main()
