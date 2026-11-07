# 朗讀串流：voice-out

已配置主機上的 agent 回完話，把回覆唸到你開著 Snapcast 的個人電腦（桌機、筆電、平板、手機同時聽得到）。
這份講服務本身：怎麼裝、怎麼開關、各裝置怎麼連、沒聲音時查什麼。為什麼這樣做見 spec #289。

```
已配置主機                                         個人電腦（tailnet 內）
agent 回完話 → voice-out-speak → pipe → snapserver ══tailnet══▶ Snapcast app／snapclient → 喇叭
              （Stop hook）                （voice-out 開關）
```

## 裝

已配置主機的選裝工具選單勾 `snapserver`（之後要加見[改設定與更新](../after-install.md)），apply 時：

- 用 apt 裝 snapserver、ffmpeg、pipx，再用 pipx 把 TTS 的 edge-tts 裝到 `~/.local/bin`。
- 停用並關掉套件自帶的系統服務（它監聽所有網卡、開機自動啟動）。
- 部署 user service `voice-out.service`、設定 `~/.config/snapserver/snapserver.conf`、開關指令 `voice-out`、
  朗讀指令 `voice-out-speak`。

只能裝在有 systemd 的 Debian 系 Linux（雲端主機、Ubuntu）。Windows、macOS、原生 Termux、平板的 proot Ubuntu
在選單上標裝不了；WSL 標不建議（抓不到自己的 tailnet IP）。

**tailscale 要先登入。** 設定裡的位址是 `chezmoi apply` 當下的 `tailscale ip -4`；第一次 `chezmoi init --apply`
時 tailscale 多半還沒 up，設定會先綁 `127.0.0.1`（個人電腦連不到）。`tailscale up` 之後再跑一次 `chezmoi apply`。
`voice-out status` 看到「只綁 127.0.0.1」就是這個情況。

## 開關

| 指令 | 做什麼 |
|---|---|
| `voice-out on` | 開。只開這一次，重開機後是關的 |
| `voice-out off` | 關 |
| `voice-out status` | 看狀態與伺服器位址。在跑 exit 0、停止 exit 3 |

預設不啟動、不開機自動啟動，跟 code-server 一樣想聽才開。沒開的時候 agent 照常跑，`voice-out-speak` 會直接略過。

- **登出後要繼續跑**：user service 在你 ssh 全斷後會跟著停，除非帳號開了 linger：
  `sudo loginctl enable-linger "$USER"`（一次就好）。`voice-out on` 沒有 linger 時會提醒。
- **改了設定**（例如換了 tailnet IP 後 `chezmoi apply`）：`voice-out off` 再 `voice-out on` 才會套用。
- 看服務的 log：`journalctl --user -u voice-out -f`。

## 朗讀指令：voice-out-speak

agent 的 Stop hook 呼叫它（hook 定義在 agent-config）。手動試：

```bash
echo '{"last_assistant_message":"改好了，測試都過。"}' | voice-out-speak
```

stdin 是一則 Stop hook JSON，唸 `last_assistant_message`（Claude Code、Codex 都有這欄）。

| 情況 | 結果 |
|---|---|
| 服務開著 | 唸出來，唸完才結束（9 秒的語音寫 9 秒） |
| 服務沒開（`voice-out off`） | 0.5 秒內結束，什麼都不寫 |
| `last_assistant_message` 空的、沒有這欄、stdin 不是 JSON | 立刻結束，什麼都不寫 |
| 同時來好幾則 | 語音各自先轉好，播放排隊一則一則來，不交錯 |
| edge-tts 失敗（沒網路） | exit 1，錯誤印在 stderr；不會回 2（Stop hook exit 2 會擋住 agent 結束） |

**唸什麼、不唸什麼。** 唸給人聽的結論：

- 程式碼區塊（` ``` ` 包起來的）整段不唸；只有程式碼的回覆就不唸。
- 連結只唸文字、不唸網址；裸網址拿掉。
- 標題、粗體、斜體、引用、清單、表格的符號拿掉，字留著；行內程式碼留內容（多半是檔名、指令名）。
- 超過 600 字元截斷（約 2 分鐘語音）；再長就去看畫面。

**多快聽到。** 從 agent 講完到聽到約 3 秒，大部分花在 edge-tts 產生語音（約 2.5 秒）。
2026-11-07 實測：原型在 Android 平板上約 2.8 秒聽到；`voice-out-speak` 在 company-ec2 從觸發到 snapclient 輸出聲音約 2.4 秒。

**hook 要不要等它。** 唸多久就跑多久，hook 不能同步等。Claude Code 的 hook 設 `"async": true`；
不支援 async 的 agent 加 `--background`：讀完 stdin、確認服務開著就回來，剩下的在背景做，
錯誤寫到 `~/.local/state/voice-out/speak.log`。

**沒裝時。** 沒勾 `snapserver` 的機器沒有這支指令。hook 寫成
`[ -x "$HOME/.local/bin/voice-out-speak" ] && exec "$HOME/.local/bin/voice-out-speak" --background; exit 0`，
沒裝就安靜略過。

### TTS 換別的

聲音是 edge-tts 的 `zh-TW-HsiaoChenNeural`（台灣華語女聲）。edge-tts 呼叫微軟 Edge 的線上朗讀服務，
免費、不用帳號，但不是公開 API，哪天可能被擋。被擋時改用離線 TTS，接法是環境變數 `VOICE_OUT_TTS`：
指令從 stdin 讀文字，stdout 吐 48000 Hz、16 bit、雙聲道的 PCM。

| 備援 | 說明 |
|---|---|
| [Piper](https://github.com/OHF-Voice/piper1-gpl) | 離線、CPU 就快；中文只有 `zh_CN` 的聲音（例如 `zh_CN-huayan-medium`），沒有台灣腔 |
| [Kokoro](https://github.com/hexgrad/kokoro) | 離線、音質比 Piper 自然，有中文聲音；要 Python 套件與模型（約 300 MB），CPU 上比 Piper 慢 |

兩個都還沒在這裡實測過。輸出的取樣率不是 48000 Hz 時，在指令後面接一段 ffmpeg 轉：
`ffmpeg -loglevel error -f s16le -ar <原取樣率> -ac 1 -i - -f s16le -ar 48000 -ac 2 -`。
`VOICE_OUT_TTS` 要在呼叫 `voice-out-speak` 的環境裡（例如 hook 的指令前面加上）。

## port 與綁定

| port | 用途 | 綁定 |
|---|---|---|
| 1704 | 串流（snapclient、app 收音訊） | 這台的 tailnet IP |
| 1705 | 控制（app 調音量、改名稱） | 同上 |
| 1780 | 網頁（Snapweb）與 JSON-RPC | 同上 |

三個 port 都只綁 tailnet IP，沒有驗證：tailnet 內的裝置都連得到，tailnet 外連不到，不用開 security group
或公開網址。確認：`ss -ltnp | grep snapserver`，位址欄要是 `100.` 開頭，不能是 `0.0.0.0` 或 `*`。

輸入是 `~/.local/state/voice-out/snapfifo` 這個 pipe（48000 Hz、16 bit、雙聲道 PCM），`voice-out-speak` 寫進去。

## 個人電腦怎麼連

伺服器都填 `voice-out status` 印的 tailnet IP（`100.` 開頭；也可以用 MagicDNS 名稱）。裝置要在 tailnet 裡。

### Android 手機、平板：Snapcast app

1. 裝 Snapcast app：[Google Play](https://play.google.com/store/apps/details?id=de.badaix.snapcast)，
   或 [GitHub releases](https://github.com/badaix/snapdroid/releases) 的 APK。
2. 開 app 的設定，伺服器的 Host 手動填 tailnet IP，port 用預設。不要靠自動找伺服器：它用 mDNS，過不了 tailnet。
3. 回到主畫面按播放。列表上會看到這支裝置，把它的音量條拉起來。

2026-11-07 原型實測：Snapcast app v0.29.0（Android 16 平板）接 snapserver v0.34.0 聽得到。

### 桌機、筆電、Termux：snapclient

勾選裝工具 `snapclient`（之後要加見[改設定與更新](../after-install.md)）：

| 平台 | 裝法 | 備註 |
|---|---|---|
| Debian 系 Linux（含 WSL） | apt 的 `snapclient` | apply 會停用套件自帶的系統服務（開機自動啟動、靠 mDNS 找伺服器，過不了 tailnet） |
| 原生 Termux | pkg 的 `snapcast-client` | 跟著裝 pulseaudio，出聲靠它 |
| macOS | brew 的 `snapcast` | |
| Windows | 裝不了，手動下載 | 見下面 [Windows](#windows手動下載) |

非 Debian 系 Linux 裝不了（只走 apt）；平板的 proot Ubuntu 標不建議（沒有音效裝置，到同一台的原生 Termux 勾，或用 Snapcast app）。

收聽（Ctrl+C 停）：

```bash
snapclient --host <tailnet IP>
```

Termux 要先起 pulseaudio：`pulseaudio --start --exit-idle-time=-1`，再跑上面那行。
Linux 桌機沒聲音時加 `--player pulse` 試（預設走 ALSA）。

**常駐（Linux）**：寫一個 user service，登入後自己連上。`~/.config/systemd/user/snapclient.service`：

```ini
[Unit]
Description=收聽朗讀串流
After=network-online.target

[Service]
ExecStart=/usr/bin/snapclient --host <tailnet IP>
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now snapclient
```

伺服器沒開（`voice-out off`）時 snapclient 會一直重連，不用重啟它。Termux、macOS 沒有對應做法，要聽時手動開；
Android 要常駐就用上面的 Snapcast app。

### Windows：手動下載

winget 沒有 snapclient，選單標裝不了。官方有 Windows 版：

1. 下載 Snapcast [release](https://github.com/badaix/snapcast/releases) 的 `snapclient_win64.zip`。
2. 解開到 `$HOME\.local\opt\snapclient`。只需要 `snapclient.exe` 與同層的 `.dll`；
   跑起來說缺 `VCRUNTIME` 的 DLL 時，才裝 zip 裡附的 `vc_redist.x64.exe`。
3. 在 PowerShell 用 `&` 呼叫（路徑放在引號裡，PowerShell 要 `&` 才會執行）：

```powershell
& "$HOME\.local\opt\snapclient\snapclient.exe" --host <tailnet IP>
```

要登入後自動開，用工作排程器建一個「登入時」執行上面那行的工作（會留一個主控台視窗）。這段還沒在 Windows 實機驗過。

### iPad、iPhone

沒有原生 app。瀏覽器開 `http://<tailnet IP>:1780`（Snapweb），頁面要停在前景。
Ubuntu 24.04 的 snapserver（0.27）套件沒有附 Snapweb，網頁打不開；Ubuntu 26.04 的 0.34 有。

## Android 沒聲音

先在已配置主機 `voice-out status` 確認在跑、位址是 `100.` 開頭，app 的列表上看得到這支裝置（看得到就是連上了）。
連上了卻沒聲音，依序查：

| 查什麼 | 怎麼做 |
|---|---|
| 系統的媒體音量 | 按音量鍵後展開，拉的是「媒體」那條，不是鈴聲 |
| app 內的音量 | Snapcast app 主畫面每個 client 有自己的音量條和靜音鈕，可能是 0 或靜音 |
| 音訊引擎 | app 設定裡的音訊引擎（audio engine）換另一個再播放；有些機型某一種沒聲音 |
| 省電限制（小米、OPPO、vivo、華為等廠牌） | 系統設定 → 應用程式 → Snapcast → 省電改「無限制」、允許自動啟動、允許背景執行；不然螢幕關掉一陣子就被系統停掉 |

鎖螢幕後會不會繼續播還沒驗證；遇到會停的機型，先查上表最後一列。
