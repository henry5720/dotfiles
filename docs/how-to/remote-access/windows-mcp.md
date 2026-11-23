# Windows 桌面：windows-mcp

別台的 agent 要操作某台 Windows 的 GUI app（截圖、點擊、打字）時，你在那台起 Windows-MCP 的 server、把 key 交出去，
agent 再連進來。agent 怎麼做寫在 agent-config 的
[`windows-access` skill](https://github.com/henry5720/agent-config/blob/main/skills/windows-access/SKILL.md)，
這份只寫你要在那台做的事。指令都是 skill 附的 script，agent 會給你整行。

```
agent 那台（例如 company-ec2）                     那台 Windows（你登入的桌面）
windows-mcp-remote ─► 127.0.0.1:18000 ══連線══▶ 127.0.0.1:8000 ─► Windows-MCP ─► 桌面
（MCP 設定，key 讀環境變數）                       （windows-mcp-http.ps1 start 起）
```

## 走哪條

照[判準](README.md#判準)看 agent 在哪：

| agent 在哪 | 怎麼接 | 你在那台要做的 |
|---|---|---|
| 同一台（那台 WSL 裡的 Claude Code、Codex） | `mcp.yaml` 的 `windows-mcp`，用 stdio，client 用時才帶起來 | 裝好就好，不起 server、不用 key |
| tailnet 內 | agent 那台開 ssh 轉發 18000 → 你那台的 8000 | 起 server（綁 `127.0.0.1`）、交 key、收 |
| tailnet 外，那台在你的 tailnet | Funnel | 起 server（綁 `0.0.0.0`）、另開一個 PowerShell 開 Funnel、交 key、收 |
| tailnet 外，那台不在你的 tailnet | quick tunnel | 起 server（綁 `127.0.0.1`）、另開一個 PowerShell 開 cloudflared、交 key、收 |

8000 和 18000 寫在 `remote-access` skill 的
[本機 port 總表](https://github.com/henry5720/agent-config/blob/main/skills/remote-access/SKILL.md#本機-port-總表)。
agent 那台用 18000 而不是 8000，是因為它在 WSL 時自己的 8000 可能被自己的 windows-mcp 佔走。
同一時間只接一台，換一台只要換 ssh 轉發的目標，MCP 設定不用改。

## 第一次：裝 Windows-MCP

Windows-MCP 是第三方開源專案：[CursorTouch/Windows-MCP](https://github.com/CursorTouch/Windows-MCP)。
裝了 dotfiles 的 Windows 主機在 PowerShell 打 `tools` 勾 windows-mcp，勾完會 apply，見 [Windows 主機〈windows-mcp〉](../windows.md#windows-mcp)。
沒裝 dotfiles 的機器（別人的、臨時借用）照 Windows-MCP 的 README 裝。

裝好的樣子：新開一個 PowerShell 跑 `windows-mcp --help` 有輸出。走 quick tunnel 的另外要 cloudflared，見 [Cloudflare quick tunnel](README.md#cloudflare-quick-tunnel)。

## 起 server、交 key

1. **在那台桌面開 PowerShell**，跑 agent 給你的 `windows-mcp-http.ps1 start --host <位址>`（參數看 `--help`）。
   一定要在你登入的桌面跑：從 ssh 起的 server 沒有桌面，一啟動就結束。
   那台有 skillshare 時 script 已經在 `$HOME\.claude\skills\windows-access\scripts\`；沒有的話 agent 會先給你一行下載。
   它會換一把新 key、起 server、把 key 複製到剪貼簿，key 不印在畫面上。每一步做什麼看 `--help`；成功或失敗看它印的訊息，失敗時會寫要你做什麼。
2. **交 key**：把剪貼簿的 key 交給 agent 那端。agent 那端把它寫進 `~/.config/windows-mcp/auth.env`：
   資料夾權限 `700`、檔案 `600`，內容只有一行 `export WINDOWS_MCP_AUTH_KEY='<key>'`。
   `~/.zshenv` 會讀這個檔，之後新開的 session 自動帶上 key，不用手動 `export`；沒有這個檔就跳過，不報錯。
   換了 key 要更新這個檔，已經開著的 session 不會重讀，要重開。key 只放在這個檔，不寫進 MCP 設定。
   別用記事本開 `config.toml` 看 key：開在畫面上會被 agent 的截圖拍進去。
3. **連線**：tailnet 內由 agent 那台開 ssh 轉發，你不用做事。Funnel、quick tunnel 時 agent 會再給你一行，
   在另一個 PowerShell 貼上、開著別關；quick tunnel 要把印出的 `https://<隨機>.trycloudflare.com` 給 agent。
   agent 從它那邊驗：不帶 key 要 `401`、帶 key 要 `200`。

## 用完收掉

順序是先收連線、再收 server：

1. **收連線**（只有 Funnel、quick tunnel 要做）：在那個視窗按 Ctrl+C，再貼 agent 給的 `Get-Process … | Stop-Process` 那行，要印 `0`。
   只按 Ctrl+C 不夠：叫它的那一端斷掉時，`tailscale.exe`、`cloudflared.exe` 可能還在跑，網址照樣通。
   agent 會再從它那邊確認網址連不上。
2. **收 server**：跑 `windows-mcp-http.ps1 stop`。它停掉 server、換 key、設定綁回 `127.0.0.1`，交出去的那把就作廢了。
   成功或失敗看它印的訊息（`--help` 有每一步）。聽 8000 的不是 windows-mcp 時它不停那支，列出來交給你處理。
   一定先停再換：server 跑著時換的 key 不生效，舊 key 照樣能用（2026-11-05 實測），`stop` 會照這個順序做。

agent 那端以前用 `claude mcp add` 自己加過的設定（local scope，key 原文寫在裡面）：等固定的 `windows-mcp-remote`
驗證過（`/mcp` 看得到 tools），用 `claude mcp remove <名字> -s local` 收掉，再在那台跑一次 `stop` 換 key，讓舊設定裡那把作廢。

## 坑

- **quick tunnel 不支援 SSE。** Windows-MCP 用 SSE 回應；單次請求收得到（2026-11-05 實測），長時間開著的 stream 沒測過。
  走 quick tunnel 時某個操作卡住或斷線，先懷疑這個。
- **winget 裝完 cloudflared，當下的 PowerShell 找不到它。** PATH 要重開才更新；重開 PowerShell，或用完整路徑
  `& 'C:\Program Files (x86)\cloudflared\cloudflared.exe'`。
- **Funnel 收掉後 `tailscale funnel status` 印 `No serve config`，公網照樣通。** 不能拿它判斷收了沒，看行程數是 `0`（2026-11-05 實測）。

## 測過什麼

| 項目 | 狀態 |
|---|---|
| tailnet 內：company-ec2 用 `ssh -L` 18000 → 那台 8000 接 | 2026-11-11 起常用 |
| agent 那端新開的 zsh（`zsh -c`、`zsh -i`）從 `auth.env` 帶上 key；沒有這個檔時不報錯、沒有輸出 | 2026-11-23 在 company-ec2 實測 |
| quick tunnel：不帶 key `401`；帶 key 時 `initialize`、`tools/list`、`Snapshot` 都 `200` | 2026-11-05 在 henry-laptop 實測（當時手動貼指令） |
| Windows 原生 tailscale 開 Funnel：不帶 key `401`、帶 key `200` | 2026-11-05 在 henry-laptop 實測（當時手動貼指令） |
| 收掉：`Stop-Process` 後 `tailscale.exe`、`cloudflared.exe`、聽 8000 的都是 `0`，公網連不上 | 2026-11-05 在 henry-laptop 實測 |
| `windows-mcp-http.ps1` 在真的 Windows 上跑 start → 連 → stop | 未實測 |
| 用新 key 重起的 server 拒絕舊 key | 未實測 |
| 同一台 WSL 的 client 經 `mcp.yaml` 帶起 mise 裝的 windows-mcp | 未實測 |

server 本身的坑（`/mcp/` 307、`Host` 檢查、session 順序）見 skill 的
[reference.md](https://github.com/henry5720/agent-config/blob/main/skills/windows-access/reference.md)。
