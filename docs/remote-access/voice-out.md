# 朗讀串流：voice-out

已配置主機上的 agent 回完話，把回覆唸到你開著 Snapcast 的個人電腦（桌機、筆電、平板、手機同時聽得到）。
這份講服務本身：怎麼裝、怎麼開關、各裝置怎麼連、沒聲音時查什麼。為什麼這樣做見 spec #289。

```
已配置主機                                         個人電腦（tailnet 內）
agent 回完話 → 朗讀指令 → pipe → snapserver ══tailnet══▶ Snapcast app／snapclient → 喇叭
                                 （voice-out 開關）
```

朗讀指令（把回覆轉成語音寫進 pipe）是下一張 ticket（#291）；這份先讓服務能開、裝置能連。

## 裝

已配置主機的選裝工具選單勾 `snapserver`（之後要加見[改設定與更新](../after-install.md)），apply 時：

- 用 apt 裝 snapserver 與 ffmpeg。
- 停用並關掉套件自帶的系統服務（它監聽所有網卡、開機自動啟動）。
- 部署 user service `voice-out.service`、設定 `~/.config/snapserver/snapserver.conf`、開關指令 `voice-out`。

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

預設不啟動、不開機自動啟動，跟 code-server 一樣想聽才開。沒開的時候 agent 照常跑，朗讀指令會直接略過。

- **登出後要繼續跑**：user service 在你 ssh 全斷後會跟著停，除非帳號開了 linger：
  `sudo loginctl enable-linger "$USER"`（一次就好）。`voice-out on` 沒有 linger 時會提醒。
- **改了設定**（例如換了 tailnet IP 後 `chezmoi apply`）：`voice-out off` 再 `voice-out on` 才會套用。
- 看服務的 log：`journalctl --user -u voice-out -f`。

## port 與綁定

| port | 用途 | 綁定 |
|---|---|---|
| 1704 | 串流（snapclient、app 收音訊） | 這台的 tailnet IP |
| 1705 | 控制（app 調音量、改名稱） | 同上 |
| 1780 | 網頁（Snapweb）與 JSON-RPC | 同上 |

三個 port 都只綁 tailnet IP，沒有驗證：tailnet 內的裝置都連得到，tailnet 外連不到，不用開 security group
或公開網址。確認：`ss -ltnp | grep snapserver`，位址欄要是 `100.` 開頭，不能是 `0.0.0.0` 或 `*`。

輸入是 `~/.local/state/voice-out/snapfifo` 這個 pipe（48000 Hz、16 bit、雙聲道 PCM），朗讀指令寫進去。

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
