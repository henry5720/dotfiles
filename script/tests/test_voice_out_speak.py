#!/usr/bin/env python3
"""voice-out-speak(#291):把一則 Stop hook JSON 唸到朗讀串流服務的 pipe。

從外面跑這支指令:stdin 給 Stop hook JSON,VOICE_OUT_FIFO 指到暫存目錄裡的 pipe,
VOICE_OUT_TTS 換成假的 TTS(把收到的文字原樣當成「語音」吐出來),不連網。
「服務在跑」= pipe 有讀者:測試自己開一個 thread 讀 pipe,等於假的 snapserver。
"""
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEAK = ROOT / "home/dot_local/bin/executable_voice-out-speak"

# 假 TTS:stdin 是要唸的文字,stdout 是「語音」。預設原樣吐回,測試從 pipe 讀到的就是被唸的文字
ECHO_TTS = f"{sys.executable} -c 'import sys; sys.stdout.write(sys.stdin.read())'"


def stop_json(message, session="s"):
    """session=None:沒有 session_id 欄(手動測試的寫法)。"""
    hook = {"session_id": session, "hook_event_name": "Stop", "last_assistant_message": message}
    if session is None:
        del hook["session_id"]
    return json.dumps(hook)


class Reader:
    """假的 snapserver:開著 pipe 的讀端,把讀到的全部收起來。delay 讓讀得像播放一樣慢。"""

    def __init__(self, fifo, delay=0.0):
        self.fifo, self.delay, self.data = fifo, delay, b""
        self.fd = os.open(fifo, os.O_RDONLY | os.O_NONBLOCK)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        while not self.stop.is_set():
            try:
                chunk = os.read(self.fd, 4096)
            except BlockingIOError:
                chunk = b""
            if chunk:
                self.data += chunk
                time.sleep(self.delay)
            else:
                time.sleep(0.01)

    def close(self):
        time.sleep(0.2)
        self.stop.set()
        self.thread.join()
        os.close(self.fd)
        return self.data.decode("utf-8")


class PollingReader(Reader):
    """照 snapserver 0.34 實際的做法(strace 看到的):沒有寫入者時每 100 ms 開一次 pipe、
    讀到 EOF 就關掉。所以大部分時間 pipe 沒有讀者,只有寫入者用阻塞的 open 等得到它。"""

    def __init__(self, fifo):
        self.fifo, self.data = fifo, b""
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        while not self.stop.is_set():
            fd = os.open(self.fifo, os.O_RDONLY | os.O_NONBLOCK)
            while True:
                try:
                    chunk = os.read(fd, 4096)
                except BlockingIOError:  # 有寫入者、暫時沒資料
                    time.sleep(0.01)
                    continue
                if not chunk:  # EOF:沒有寫入者
                    break
                self.data += chunk
            os.close(fd)
            time.sleep(0.1)

    def close(self):
        time.sleep(0.3)
        self.stop.set()
        self.thread.join()
        return self.data.decode("utf-8")


class VoiceOutSpeakTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.fifo = self.dir / "snapfifo"
        os.mkfifo(self.fifo)

    def tearDown(self):
        self.tmp.cleanup()

    # ===============================================================
    # 共用
    # ===============================================================
    def env(self, tts=ECHO_TTS):
        env = {"PATH": f"{self.dir / 'bin'}:{os.environ['PATH']}", "HOME": str(self.dir),
               "VOICE_OUT_FIFO": str(self.fifo)}
        if tts is not None:
            env["VOICE_OUT_TTS"] = tts
        return env

    def start(self, stdin, tts=ECHO_TTS, *args):
        proc = subprocess.Popen([sys.executable, str(SPEAK), *args], env=self.env(tts), text=True,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # 測試失敗時也收掉:不然它卡在寫 pipe,變成孤兒
        self.addCleanup(lambda: proc.poll() is None and (proc.kill(), proc.wait()))
        proc.stdin.write(stdin)
        proc.stdin.close()
        return proc

    def speak(self, stdin, tts=ECHO_TTS, *args):
        proc = self.start(stdin, tts, *args)
        proc.wait(timeout=10)
        return proc

    # ===============================================================
    # 服務在跑:唸 last_assistant_message
    # ===============================================================
    def test_speaks_last_assistant_message(self):
        reader = Reader(self.fifo)
        proc = self.speak(stop_json("改好了，測試都過。"))
        self.assertEqual(proc.returncode, 0, proc.stderr.read())
        self.assertEqual(reader.close(), "改好了，測試都過。")

    def test_speaks_to_reader_that_polls_like_snapserver(self):
        reader = PollingReader(self.fifo)
        time.sleep(0.05)
        proc = self.speak(stop_json("snapserver 是輪詢的"))
        self.assertEqual(proc.returncode, 0, proc.stderr.read())
        self.assertEqual(reader.close(), "snapserver 是輪詢的")

    # ===============================================================
    # 服務沒開:pipe 沒有讀者(或還沒建)時立刻結束,不叫 TTS、不卡住
    # ===============================================================
    def tts_marker(self):
        marker = self.dir / "tts-called"
        return marker, f"sh -c 'touch {marker}; cat'"

    def test_exits_at_once_when_pipe_has_no_reader(self):
        marker, tts = self.tts_marker()
        started = time.monotonic()
        proc = self.speak(stop_json("沒人在聽"), tts)
        self.assertEqual(proc.returncode, 0, proc.stderr.read())
        self.assertLess(time.monotonic() - started, 1.5)
        self.assertFalse(marker.exists(), "服務沒開不該花時間跑 TTS")

    def test_exits_at_once_when_pipe_missing(self):
        # 從沒開過服務:snapserver 還沒建 pipe。不能自己建一個普通檔案寫進去
        self.fifo.unlink()
        marker, tts = self.tts_marker()
        proc = self.speak(stop_json("沒人在聽"), tts)
        self.assertEqual(proc.returncode, 0, proc.stderr.read())
        self.assertFalse(marker.exists())
        self.assertFalse(self.fifo.exists())

    # ===============================================================
    # 沒東西可唸:last_assistant_message 空的、沒有這欄、stdin 不是 JSON
    # ===============================================================
    def test_nothing_written_without_message(self):
        reader = Reader(self.fifo)
        marker, tts = self.tts_marker()
        for stdin in (stop_json(""), stop_json("   \n"), json.dumps({"hook_event_name": "Stop"}),
                      json.dumps({"last_assistant_message": None}), "not json", ""):
            with self.subTest(stdin=stdin):
                proc = self.speak(stdin, tts)
                self.assertEqual(proc.returncode, 0, proc.stderr.read())
        self.assertEqual(reader.close(), "")
        self.assertFalse(marker.exists())

    def test_nothing_written_when_only_code(self):
        reader = Reader(self.fifo)
        proc = self.speak(stop_json("```sh\nls -la\n```"))
        self.assertEqual(proc.returncode, 0, proc.stderr.read())
        self.assertEqual(reader.close(), "")

    # ===============================================================
    # 唸什麼:拿掉程式碼區塊與 Markdown 符號,長回覆截斷
    # ===============================================================
    def spoken(self, message):
        reader = Reader(self.fifo)
        proc = self.speak(stop_json(message))
        self.assertEqual(proc.returncode, 0, proc.stderr.read())
        return reader.close()

    def test_strips_code_blocks_and_markdown(self):
        message = ("## 結論\n\n"
                   "**改好了**，`voice-out` 的 *測試* 都過。\n\n"
                   "```python\nprint('不要唸')\n```\n\n"
                   "- 第一項\n"
                   "1. 第二項\n"
                   "> 引用\n\n"
                   "| 檔案 | 結果 |\n|---|---|\n| a.py | 過 |\n\n"
                   "詳見 [主題文件](https://example.com/doc)。\n"
                   "---\n")
        spoken = self.spoken(message)
        self.assertNotIn("print", spoken)
        self.assertNotIn("https://", spoken)
        for symbol in "#*`>|[]()":
            self.assertNotIn(symbol, spoken)
        self.assertNotIn("---", spoken)
        for kept in ("結論", "改好了", "voice-out", "測試", "都過", "第一項", "第二項", "引用", "a.py", "主題文件"):
            self.assertIn(kept, spoken)

    def test_keeps_hyphens_and_underscores_inside_words(self):
        # 檔名、指令名裡的 - _ 不是 Markdown 符號
        self.assertEqual(self.spoken("跑 voice-out-speak 讀 last_assistant_message"),
                         "跑 voice-out-speak 讀 last_assistant_message")

    def test_truncates_long_reply(self):
        spoken = self.spoken("很長的回覆。" * 300)
        self.assertLessEqual(len(spoken), 600)
        self.assertGreaterEqual(len(spoken), 500)
        self.assertTrue(spoken.startswith("很長的回覆。很長的回覆。"))

    # ===============================================================
    # 排隊:同時來的兩則一次一則、不交錯(flock 不保證誰先唸)
    # ===============================================================
    def test_concurrent_replies_play_one_after_another(self):
        # 每則「語音」放大成 200 KB(大過 pipe 緩衝區 64 KB),讀端又讀得慢:沒排隊就會交錯
        big_tts = f"{sys.executable} -c 'import sys; sys.stdout.write(sys.stdin.read() * 200000)'"
        reader = Reader(self.fifo, delay=0.001)
        procs = [self.start(stop_json(m, session=m), big_tts) for m in ("A", "B")]  # 不同 session 才排隊
        for proc in procs:
            proc.wait(timeout=60)
            self.assertEqual(proc.returncode, 0, proc.stderr.read())
        data = reader.close()
        self.assertEqual(len(data), 400000)
        self.assertIn(re.sub(r"(.)\1*", r"\1", data), ("AB", "BA"), "兩則語音交錯了")


    # ===============================================================
    # 跳過(#294):voice-out skip 停掉正在寫 pipe 的那則,排隊的照唸
    # ===============================================================
    def voice_out(self, *args):
        voice_out = ROOT / "home/dot_local/bin/executable_voice-out"
        return subprocess.run(["sh", str(voice_out), *args], env=self.env(), capture_output=True, text=True,
                              timeout=10)

    def test_skip_stops_current_reply_and_queued_one_still_plays(self):
        # A 的「語音」很長(讀端照播放速度慢慢讀,要唸好幾秒),B 很短、在排隊
        tts = (f"{sys.executable} -c 'import sys; t = sys.stdin.read(); "
               f"sys.stdout.write(t * (3000000 if t == \"A\" else 3000))'")
        reader = Reader(self.fifo, delay=0.01)
        a = self.start(stop_json("A", session="a"), tts)
        self.wait_for(reader, "A")
        b = self.start(stop_json("B", session="b"), tts)  # 不同 session:B 不會取代 A
        time.sleep(0.5)  # B 轉完語音、在等排隊的鎖
        skipped = time.monotonic()
        run = self.voice_out("skip")
        self.assertEqual(run.returncode, 0, run.stderr)
        a.wait(timeout=5)
        self.assertLess(time.monotonic() - skipped, 2, "A 沒有被跳過")
        self.assertEqual(a.returncode, 0, a.stderr.read())
        b.wait(timeout=10)
        self.assertEqual(b.returncode, 0, b.stderr.read())
        data = reader.close()
        self.assertEqual(data.count("B"), 3000, "排隊的 B 應該整則唸完")
        self.assertLess(data.count("A"), 3000000)

    # ===============================================================
    # 取代(#296):同一個 session 的新回覆語音轉好時,這個 session 正在唸、還在排隊的舊回覆不唸了;
    # 別的 session、沒有 session_id 的照唸
    # ===============================================================
    # A 的「語音」很長(讀端慢慢讀,要唸好幾秒),其他的短
    LONG_TTS = (f"{sys.executable} -c 'import sys; t = sys.stdin.read(); "
                f"sys.stdout.write(t * (600000 if t == \"A\" else 3000))'")

    def wait_for(self, reader, text):
        deadline = time.monotonic() + 5
        while text.encode() not in reader.data and time.monotonic() < deadline:
            time.sleep(0.05)

    def finish(self, *procs):
        for proc in procs:
            proc.wait(timeout=30)
            self.assertEqual(proc.returncode, 0, proc.stderr.read())

    def test_new_reply_of_same_session_replaces_the_one_playing(self):
        reader = Reader(self.fifo, delay=0.01)
        a = self.start(stop_json("A", session="x"), self.LONG_TTS)
        self.wait_for(reader, "A")
        b = self.start(stop_json("B", session="x"), self.LONG_TTS)
        self.finish(a, b)
        data = reader.close()
        self.assertLess(data.count("A"), 600000, "A 應該被同 session 的 B 取代")
        self.assertEqual(data.count("B"), 3000, "B 應該整則唸完")
        self.assertNotIn("A", data[data.index("B"):], "B 開始唸之後不該再有 A")

    def test_queued_reply_is_dropped_when_same_session_has_newer_one(self):
        # A(別的 session)唸著;B 排在後面;同 session 的 C 來了 → B 不唸、A 唸完、C 唸
        reader = Reader(self.fifo, delay=0.01)
        a = self.start(stop_json("A", session="other"), self.LONG_TTS)
        self.wait_for(reader, "A")
        b = self.start(stop_json("B", session="x"), self.LONG_TTS)
        time.sleep(0.5)  # B 轉完語音、在等排隊的鎖
        c = self.start(stop_json("C", session="x"), self.LONG_TTS)
        self.finish(a, b, c)
        data = reader.close()
        self.assertEqual(data.count("A"), 600000, "別的 session 的 A 應該整則唸完")
        self.assertEqual(data.count("B"), 0, "排隊的 B 被同 session 的 C 取代,不該唸")
        self.assertEqual(data.count("C"), 3000)

    def test_reply_of_other_session_waits_its_turn(self):
        reader = Reader(self.fifo, delay=0.01)
        a = self.start(stop_json("A", session="x"), self.LONG_TTS)
        self.wait_for(reader, "A")
        b = self.start(stop_json("B", session="y"), self.LONG_TTS)
        self.finish(a, b)
        data = reader.close()
        self.assertEqual(re.sub(r"(.)\1*", r"\1", data), "AB", "A 唸完才輪到 B")
        self.assertEqual((data.count("A"), data.count("B")), (600000, 3000))

    def test_replies_without_session_id_never_replace(self):
        reader = Reader(self.fifo, delay=0.01)
        a = self.start(stop_json("A", session=None), self.LONG_TTS)
        self.wait_for(reader, "A")
        b = self.start(stop_json("B", session=None), self.LONG_TTS)
        self.finish(a, b)
        data = reader.close()
        self.assertEqual((data.count("A"), data.count("B")), (600000, 3000))

    def test_skip_when_nothing_is_playing(self):
        run = self.voice_out("skip")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("沒在唸", run.stdout)

    # ===============================================================
    # 預設的 TTS:用 uv 跑 edge-tts(zh-TW-HsiaoChenNeural,不另裝全域套件)產生 mp3,ffmpeg 解成 snapserver 要的 PCM
    # 換成假的 uv、ffmpeg 放 PATH 最前面,記下參數
    # ===============================================================
    def fake(self, name, code, bin_dir=None):
        bin_dir = bin_dir or self.dir / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        path = bin_dir / name
        path.write_text(f"#!{sys.executable}\nimport sys, json\n"
                        f"open({str(self.dir / (name + '.args'))!r}, 'a').write(json.dumps(sys.argv[1:]) + '\\n')\n"
                        + code, encoding="utf-8")
        path.chmod(0o755)

    def args_of(self, name):
        return [json.loads(l) for l in (self.dir / f"{name}.args").read_text(encoding="utf-8").splitlines()]

    def fake_uv_and_ffmpeg(self, edge_tts_exit=0, uv_dir=None):
        # 假的 uv 只認 `uv tool run --from edge-tts edge-tts <edge-tts 的參數>`
        self.fake("uv", f"""
a = sys.argv[1:]
if a[:5] != ['tool', 'run', '--from', 'edge-tts', 'edge-tts']:
    sys.exit('不是用 uv 跑 edge-tts:' + ' '.join(a))
text = open(a[a.index('--file') + 1], encoding='utf-8').read()
open(a[a.index('--write-media') + 1], 'w', encoding='utf-8').write('MP3:' + text)
if {edge_tts_exit}:
    sys.exit('edge-tts 連不上')
""", uv_dir)
        self.fake("ffmpeg", """
a = sys.argv[1:]
sys.stdout.write('PCM:' + open(a[a.index('-i') + 1], encoding='utf-8').read())
""")

    def test_default_tts_is_edge_tts_run_by_uv_decoded_to_snapserver_pcm(self):
        self.fake_uv_and_ffmpeg()
        reader = Reader(self.fifo)
        proc = self.speak(stop_json("-開頭是減號也照唸"), None)
        self.assertEqual(proc.returncode, 0, proc.stderr.read())
        self.assertEqual(reader.close(), "PCM:MP3:-開頭是減號也照唸")
        edge = self.args_of("uv")[0]
        self.assertEqual(edge[edge.index("--voice") + 1], "zh-TW-HsiaoChenNeural")
        ffmpeg = " ".join(self.args_of("ffmpeg")[0])
        # 跟 snapserver.conf 的 sampleformat=48000:16:2 一致
        self.assertIn("-f s16le -ar 48000 -ac 2", ffmpeg)

    # ===============================================================
    # 朗讀設定(#294):~/.config/voice-out/settings,由 voice-out rate／voice／max 寫入;每則回覆重讀
    # ===============================================================
    def write_settings(self, **values):
        path = self.dir / ".config/voice-out/settings"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(f"{k}={v}\n" for k, v in values.items()), encoding="utf-8")

    def edge_tts_args(self):
        self.fake_uv_and_ffmpeg()
        reader = Reader(self.fifo)
        proc = self.speak(stop_json("設定"), None)
        self.assertEqual(proc.returncode, 0, proc.stderr.read())
        reader.close()
        return self.args_of("uv")[0]

    def test_rate_and_voice_from_settings_reach_edge_tts(self):
        self.write_settings(rate="-10%", voice="zh-TW-YunJheNeural")
        edge = self.edge_tts_args()
        # 值以 - 開頭:要寫成 --rate=值,不然 edge-tts 把它當成另一個選項
        self.assertIn("--rate=-10%", edge)
        self.assertEqual(edge[edge.index("--voice") + 1], "zh-TW-YunJheNeural")

    def test_without_settings_uses_default_voice_and_rate(self):
        edge = self.edge_tts_args()
        self.assertEqual(edge[edge.index("--voice") + 1], "zh-TW-HsiaoChenNeural")
        self.assertFalse([a for a in edge if a.startswith("--rate")])

    def test_max_from_settings_limits_length(self):
        self.write_settings(max="20")
        self.assertEqual(self.spoken("很長的回覆。" * 300), "很長的回覆。很長的回覆。很長的回覆。很長")

    def test_max_zero_means_unlimited(self):
        self.write_settings(max="0")
        self.assertEqual(len(self.spoken("很長的回覆。" * 300)), 1800)

    def test_invalid_settings_fall_back_to_defaults(self):
        # 手改壞的設定檔不能讓整則不出聲
        self.write_settings(rate="快一點", voice="", max="²")  # ² 是 isdigit() 但 int() 會炸
        edge = self.edge_tts_args()
        self.assertEqual(edge[edge.index("--voice") + 1], "zh-TW-HsiaoChenNeural")
        self.assertFalse([a for a in edge if a.startswith("--rate")])
        self.assertEqual(len(self.spoken("很長的回覆。" * 300)), 600)

    def test_finds_uv_in_mise_shims_when_hook_path_lacks_it(self):
        # uv 由 mise 裝(miseTools);hook 的 PATH 不一定有 mise 的 shims
        self.fake_uv_and_ffmpeg(uv_dir=self.dir / ".local/share/mise/shims")
        reader = Reader(self.fifo)
        env = {**self.env(None), "PATH": f"{self.dir / 'bin'}:/usr/bin:/bin"}
        proc = subprocess.run([sys.executable, str(SPEAK)], env=env, input=stop_json("找得到 uv"),
                              capture_output=True, text=True, timeout=10)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(reader.close(), "PCM:MP3:找得到 uv")

    def test_tts_failure_writes_nothing_and_never_exits_2(self):
        # Stop hook exit 2 會擋住 agent 結束,TTS 失敗(沒網路)絕不能回 2
        self.fake_uv_and_ffmpeg(edge_tts_exit=1)
        reader = Reader(self.fifo)
        proc = self.speak(stop_json("沒網路"), None)
        self.assertNotIn(proc.returncode, (0, 2))
        self.assertIn("edge-tts", proc.stderr.read())
        self.assertEqual(reader.close(), "")

    def test_default_pipe_is_under_home_state(self):
        # snapserver.conf 的 pipe 位置(#290)
        state = self.dir / ".local/state/voice-out"
        state.mkdir(parents=True)
        self.fifo = state / "snapfifo"
        os.mkfifo(self.fifo)
        reader = Reader(self.fifo)
        env = self.env()
        del env["VOICE_OUT_FIFO"]
        proc = subprocess.run([sys.executable, str(SPEAK)], env=env, input=stop_json("預設位置"),
                              capture_output=True, text=True, timeout=10)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(reader.close(), "預設位置")


    # ===============================================================
    # --background:給不支援 async 的 hook。確認服務在跑就回來,背景繼續唸
    # ===============================================================
    def test_background_returns_before_speech_is_written(self):
        slow_tts = f"sh -c 'sleep 1.5; cat'"
        reader = Reader(self.fifo)
        started = time.monotonic()
        proc = self.speak(stop_json("背景唸"), slow_tts, "--background")
        self.assertEqual(proc.returncode, 0, proc.stderr.read())
        self.assertLess(time.monotonic() - started, 1)
        time.sleep(2.5)
        self.assertEqual(reader.close(), "背景唸")

    def test_background_log_is_cleared_when_too_big(self):
        # speak.log 只有 --background 的錯誤會寫;超過約 1 MB 就從頭清空,不會無限長大
        log = self.fifo.with_name("speak.log")
        log.write_text("舊錯誤\n" * 200000, encoding="utf-8")  # 約 2 MB
        self.fake_uv_and_ffmpeg(edge_tts_exit=1)
        reader = Reader(self.fifo)
        proc = self.speak(stop_json("沒網路"), None, "--background")
        self.assertEqual(proc.returncode, 0, proc.stderr.read())
        deadline = time.monotonic() + 5
        while "edge-tts" not in log.read_text(encoding="utf-8", errors="ignore") and time.monotonic() < deadline:
            time.sleep(0.1)
        reader.close()
        text = log.read_text(encoding="utf-8")
        self.assertIn("edge-tts", text)
        self.assertFalse("舊錯誤" in text, f"speak.log 沒被清空({len(text)} 字)")

    def test_background_log_is_kept_when_small(self):
        log = self.fifo.with_name("speak.log")
        log.write_text("舊錯誤\n", encoding="utf-8")
        self.fake_uv_and_ffmpeg(edge_tts_exit=1)
        reader = Reader(self.fifo)
        self.speak(stop_json("沒網路"), None, "--background")
        deadline = time.monotonic() + 5
        while "edge-tts" not in log.read_text(encoding="utf-8") and time.monotonic() < deadline:
            time.sleep(0.1)
        reader.close()
        self.assertTrue(log.read_text(encoding="utf-8").startswith("舊錯誤\n"))

    def test_background_survives_hook_process_group_kill(self):
        # Codex 的 hook 行程結束時會 kill 整個 process group:背景的子行程要在父行程回來之前就脫離。
        # 假的 hook:sh 開自己的 process group,voice-out-speak --background 一回來就 kill -9 整個 group。
        # 父行程 exit 與子行程 setsid 之間是 race:CPU 滿載時子行程比較晚排到,跑多次才抓得到
        reader = Reader(self.fifo)
        busy = [subprocess.Popen([sys.executable, "-c", "while True: pass"]) for _ in range(os.cpu_count() or 1)]
        self.addCleanup(lambda: [b.kill() or b.wait() for b in busy])
        runs = 100
        for i in range(runs):
            hook = f"{shlex.quote(sys.executable)} {shlex.quote(str(SPEAK))} --background; kill -9 0"
            subprocess.run(["sh", "-c", hook], env=self.env(), input=stop_json(f"第{i}則"), text=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True, timeout=10)
        for b in busy:
            b.kill()
            b.wait()
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and reader.data.decode("utf-8", "ignore").count("則") < runs:
            time.sleep(0.1)
        spoken = reader.close()
        missing = [i for i in range(runs) if f"第{i}則" not in spoken]
        self.assertEqual(missing, [], f"{len(missing)}/{runs} 則被 kill 整個 process group 時一起砍掉")

if __name__ == "__main__":
    unittest.main()
