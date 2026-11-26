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

### Windows 桌面的 terminal 連不上 herdr

症狀：在 Windows 桌面開一般 terminal 跑 `herdr`，回 elevated server 拒絕 unelevated client（存取被拒）；
或 pane 的提示列是 Administrator、GUI 程式看不到、junction 顯示「未受信任的掛接點」。

原因：帳號在 Administrators 群組，從 OpenSSH 登入拿到的是完整（elevated）權限，跑在 session 0。
從別台 `herdr --machine` 或 `herdr machine add` 經 ssh 把 server 拉起來，server 和每個 pane 都繼承這個權限。
Linux 沒有這個問題，經 ssh 起 server 是官方設計。

所以 Windows 的 herdr server 要在那台登入桌面後，從一般 terminal 跑 `herdr` 起。
`[server] allow_unelevated_clients` 不開：它讓一般權限的 client 操作 elevated server，等於開一條提權的路，pane 也還是 elevated。

已經是 elevated 的 server，修法（停用各 client 的 profile、停 server、從桌面重起）見 agent-config 的
[`herdr-workflow` skill〈server〉](https://github.com/henry5720/agent-config/blob/main/skills/herdr-workflow/server.md)。

## 更多

- [herdr](https://github.com/herdrdev/herdr)：官方 README 與設定
