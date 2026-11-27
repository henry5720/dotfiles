# herdr

## 為什麼裝

terminal 多工，同時開多個 agent。怎麼開 session、接回去見[操作已配置主機〈herdr〉](../configured-host.md#herdr)。

### 通知音怎麼播

Herdr 的通知音由**目前連線的 local client**播放。Linux 版不內建 audio backend,
而是把內建或自訂的 MP3 寫到暫存檔,再依序嘗試系統播放器:

1. `paplay`
2. `pw-play`
3. `ffplay`
4. `mpg123`
5. `mpv`

順序以 Herdr 官方 [`src/sound.rs`](https://github.com/herdrdev/herdr/blob/master/src/sound.rs)
為準。每個 player 最多執行 15 秒,失敗才換下一個。

### WSL2 的做法

WSL2 的聲音由 WSLg PulseAudio 提供,所以使用第一順位的 `paplay`:

```text
Herdr local client ──→ paplay ──→ WSLg PulseAudio ──→ Windows 音效
```

```bash
sudo apt install pulseaudio-utils
sudo apt purge mpg123
```

`pulseaudio-utils` 是 Ubuntu 24.04 官方 APT 套件。Snap Store 沒有 `paplay` 或
`pulseaudio-utils`,而且 Snap confinement 會多一層 audio interface 權限,這裡不用 Snap。

Herdr 設定在 `~/.config/herdr/config.toml`:

```toml
[ui.toast]
delivery = "herdr"

[ui.sound]
enabled = true
```

這份 config **目前不由 chezmoi 部署**,新機器要自行建立。自訂通知音時只接受 MP3,
可在 `[ui.sound]` 設定 `path`、`done_path` 或 `request_path`。

## 常用指令

### 驗證通知音

先確認實際可用的 player:

```bash
command -v paplay
command -v mpg123    # 預期找不到
```

再讓 Herdr 走完整通知流程:

```bash
herdr notification show "Herdr 音效測試" --sound done
```

成功時 `paplay` 播放後會直接結束,client log 不會新增 sound error。失敗時查:

```bash
grep 'sound playback failed' ~/.config/herdr/herdr-client.log
```

## 坑

### SSH 後沒聲音

先看 log,不要先假設通知被 SSH client 搶走。若看到:

```text
paplay exited with exit status: 1: Connection failure: Connection refused
pa_context_connect() failed: Connection refused
```

代表 Herdr 已呼叫正確的 `paplay`,但 WSLg PulseAudio endpoint 拒絕連線。只重開 Herdr
不會修好,因為壞的是 WSLg audio。保存工作後,在 Windows PowerShell 執行:

```powershell
wsl --shutdown
```

再重新開啟 WSL 與 Herdr。這個指令會停止所有 WSL process,包括 Herdr panes、dev server
與 Docker command,不能在尚未保存工作時執行。

### Windows：誰先開 herdr，決定 server 的權限

Windows 重開機後沒有 server，第一個開 herdr 的那一方決定它的權限：

| 誰先開 | server | 會怎樣 |
|---|---|---|
| 別台 `herdr --machine`、TUI 點那台（預設） | 完整管理員權限、session 0 | shell、agent、git、裝東西都能用，不跳 UAC |
| 在那台桌面用一般 terminal 跑 `herdr` | 一般權限、登入的 session | 能操作桌面；要管理員權限的事改走 ssh |

差別來自 Windows：帳號在 Administrators 群組時，從 OpenSSH 登入拿到的是完整權限、跑在沒有桌面的 session 0，
herdr 的 server 和 pane 都繼承它。Linux 沒有這個差別，經 ssh 起 server 是官方設計。

**維持預設就好**，平常從 EC2 操作不受影響。遇到下面這些才要把那一台改成從桌面起：

- 在那台桌面用一般 terminal 連 herdr，回 elevated server 拒絕 unelevated client（存取被拒）
- pane 裡開的 GUI 程式（RPA、有視窗的瀏覽器）桌面上看不到，windows-mcp 從 pane 起抓不到畫面
- pane 裡走 junction 回「未受信任的掛接點」

改法由 agent 照 agent-config 的
[`herdr-workflow` skill〈server〉](https://github.com/henry5720/agent-config/blob/main/skills/herdr-workflow/server.md) 做，
你只要在它停 server 前按一次 Enter（會關掉那台所有 pane）。改完之後重開機，又先從別台點那台，就會回到預設。

`[server] allow_unelevated_clients` 不開：它只讓一般 terminal 連得上，pane 還是完整管理員權限、session 0。

## 更多

- [herdr](https://github.com/herdrdev/herdr)：官方 README 與設定
