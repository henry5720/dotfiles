# Herdr 通知音:WSL2 設定與排錯

Herdr 的通知音由**目前連線的 local client**播放。Linux 版不內建 audio backend,
而是把內建或自訂的 MP3 寫到暫存檔,再依序嘗試系統播放器:

1. `paplay`
2. `pw-play`
3. `ffplay`
4. `mpg123`
5. `mpv`

順序以 Herdr 官方 [`src/sound.rs`](https://github.com/herdrdev/herdr/blob/master/src/sound.rs)
為準。每個 player 最多執行 15 秒,失敗才換下一個。

## 這台機器的做法

WSL2 的聲音由 WSLg PulseAudio 提供,所以使用第一順位的 `paplay`:

```mermaid
flowchart LR
  H["Herdr local client"] --> P["paplay"] --> W["WSLg PulseAudio"] --> S["Windows 音效"]
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

## 驗證

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

## SSH 後沒聲音

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
