# chrome-devtools MCP:讓 agent 開你的瀏覽器

Claude Code 和 opencode 都接了 `chrome-devtools-mcp`,agent 因此能開網頁、點按鈕、看
console、抓 network、跑 lighthouse。這份記的是**這台機器上為什麼要這樣設**,不是這個 MCP
的用法(用法看[官方 repo](https://github.com/ChromeDevTools/chrome-devtools-mcp))。

## 架構:WSL 這邊不開瀏覽器

```
WSL2                              Windows
┌──────────────────┐             ┌─────────────────────────┐
│ Claude / opencode│             │ chrome.exe              │
│   └─ MCP server  │──9222──────▶│   --remote-debugging-   │
│      (npx 跑的)  │             │      port=9222          │
└──────────────────┘             │   獨立 profile          │
                                 └─────────────────────────┘
```

WSL 裡沒有圖形環境可言,也沒有你登入過的 Google / 公司後台 session。所以不在 WSL 開瀏覽器,
而是叫 MCP server 用 `--browser-url` **連到 Windows 那台已經在跑的 Chrome**。

能直接打 `127.0.0.1:9222` 是因為 Windows 側 `.wslconfig` 設了
`networkingMode=mirrored`(見 [`wsl/.wslconfig`](../wsl/.wslconfig) 第 16 行)—— WSL 和 Windows 共用 localhost。
沒有這一行的話 WSL 連不到 Windows 的 loopback,要改成走 Windows 主機 IP。

> ⚠️ **不要在 WSL 裝 Linux Chrome。** `npx puppeteer browsers install chrome` 會抓 80MB 到
> `~/.cache/puppeteer`,然後你有兩個瀏覽器、agent 連的還是錯的那個。方向就是錯的,設定本來
> 就是連 Windows 那台。

## 怎麼用

```bash
chrome-mcp        # 開 Windows Chrome 並開 9222;已經在跑就直接結束
```

部署自 [`home/dot_local/bin/executable_chrome-mcp`](../home/dot_local/bin/executable_chrome-mcp),
落在 `~/.local/bin/chrome-mcp`(那個目錄已經在 PATH 裡,見 `home/dot_zshrc` 第 3 節)。

**Chrome 要先跑起來,agent 才連得上。** 順序錯了就是 MCP 連不上,重開 Chrome 後在 session 裡
打 `/mcp` 重連即可,不用重開 Claude。

script 做三件事,每件都是踩過才加的:

1. **先檢查 9222 通不通。** Chrome 已有實例時,再下一次帶參數的啟動會被**轉交給既有實例、
   新參數整組丟掉、而且不報錯**。沒這個檢查就會看到「指令跑完、沒紅字、MCP 還是連不上」。
2. **問 Windows 自己的 `%LOCALAPPDATA%`**,不寫死 `C:\Users\henry`。
3. **等 9222 真的通了才回報成功**,最多等 15 秒。

## 第一次要手動登入

用的是獨立 profile(`%LOCALAPPDATA%\ChromeDevToolsMCP`),不是你日常那個。原因有兩個:
日常 profile 開著的時候 Chrome 會忽略 `--remote-debugging-port`;而且讓 agent 碰你日常瀏覽的
登入狀態不是好主意。

代價是這個 profile 第一次是全新的,要手動登入你想讓 agent 看到的網站。之後會保留 cookie。

> ⚠️ `9222` 等於**完整瀏覽器控制權**,包含那個 profile 裡所有登入狀態。只綁 localhost,
> 不要對 LAN 或網際網路開放。

## 設定放在哪

| 檔案 | 部署到 | 管什麼 |
|---|---|---|
| [`home/modify_private_dot_claude.json`](../home/modify_private_dot_claude.json) | `~/.claude.json`(600) | Claude Code 的 `mcpServers["chrome-devtools"]` |
| [`home/dot_claude/modify_settings.json`](../home/dot_claude/modify_settings.json) | `~/.claude/settings.json` | 關掉官方 chrome-devtools plugin |
| [`home/dot_config/opencode/private_opencode.json.tmpl`](../home/dot_config/opencode/private_opencode.json.tmpl) | `~/.config/opencode/opencode.json`(600) | opencode 的 `mcp["chrome-devtools"]` |
| [`home/dot_codex/modify_private_config.toml.tmpl`](../home/dot_codex/modify_private_config.toml.tmpl) | `~/.codex/config.toml`(600) | Codex 的 `mcp_servers.chrome-devtools`、`codegraph`、`context7` |

Codex 的設定由 `modify_` 每次定向更新；它會保留 Codex 自己寫入的 user state 與其他設定。Context7 API key
可在 `chezmoi init` 時輸入或留空；留空代表匿名使用。之後可用 `chezmoi edit-config` 修改，或用
`chezmoi init --prompt` 重新回答已有 prompt。可用
`codex mcp list` / `codex mcp get <name>` 確認配置已啟用；這只驗證設定，不代表 MCP server
已完成 runtime handshake。Context7 endpoint 是 `https://mcp.context7.com/mcp`，API key 會以明文保存在本機
chezmoi 設定，部署後也會寫入 Codex 設定的 `CONTEXT7_API_KEY` header，不會進 repo。

三個 client 的 Chrome DevTools 參數刻意保持一致:

`~/.local/bin/chrome-mcp` 是 Windows Chrome 的啟動器，不是 chezmoi hook。需要時手動執行
`chrome-mcp`；它會先重用現有的 `127.0.0.1:9222` DevTools endpoint，只有 endpoint 不存在時才
啟動獨立的 `ChromeDevToolsMCP` profile。這個 profile 不共用日常 Chrome 的 cookies 或密碼。

啟動器只允許 loopback 連線；若 9222 已被其他服務占用會直接失敗，不會終止既有 Chrome。啟動後
最多等待 15 秒，逾時會回傳非零狀態，方便 shell 或 MCP 啟動流程辨識失敗。

```
--browser-url=http://127.0.0.1:9222   連 Windows 那台,不要自己開
--no-usage-statistics                 不回報使用統計
--no-performance-crux                 跑效能分析時不去 CrUX API 查別人網站的公開數據
```

### 為什麼前兩份要用 `modify_`

`~/.claude.json` 有 2200 行,裡面 99% 是 Claude Code 自己寫的狀態:開過哪些專案的絕對路徑、
帳號 email、feature flag 快取。**這個 repo 是公開的**,整份納管等於把那些推上 GitHub。
`~/.claude/settings.json` 同理,裡面有 herdr 與 codegraph 的 hook、claude-hud 的 statusLine、
一整塊機器描述。

chezmoi 的 [`modify_`](https://www.chezmoi.io/reference/target-types/#modify_-scripts) 正是為這種
情況設計的:repo 裡存的不是檔案內容,是**一小段改檔案的指令**。apply 時現有檔案從 stdin 進來,
只改指定的 key,其他原封不動。repo 裡因此只有那一段設定,沒有任何 session 狀態。

沒有選 `run_onchange_`(另一種常見做法)是因為那個只在 script 內容變動時才跑;哪天這個 key
被弄掉了它不會發現。`modify_` 每次 `chezmoi apply` 都對一遍,會自癒。

一個實作細節:Claude Code 寫出來的 JSON 是 2 空格縮排、**結尾沒有換行**,而 `jq` 會補一個。
所以 `modify_private_dot_claude.json` 用 `printf '%s' "$(...)"` 砍掉它 —— 不砍的話每次
`chezmoi diff` 都會多一行雜訊。

## 為什麼要關掉官方那個 plugin

Claude Code 內建一個 chrome-devtools plugin,設定在:

```
~/.claude/plugins/cache/claude-plugins-official/chrome-devtools-mcp/<版本>/.claude-plugin/plugin.json
```

它的 `args` 只有 `["chrome-devtools-mcp@<版本>"]` —— **沒有 `--browser-url`**。所以它會想在
WSL 自己開一個 Chrome,然後失敗:

```
Protocol error (Target.setDiscoverTargets): Target closed
```

不關掉的話它會跟自己加的那台 MCP server 同時出現,同一組工具兩份,Claude 有一半機率挑到壞的。

官方裝法(`claude mcp add chrome-devtools npx chrome-devtools-mcp@latest`)也生不出正確設定,
少的就是 `--browser-url`。**這就是為什麼這份設定值得進 repo,而 context7 那種一行
`npx ctx7 setup` 就回來的不值得** —— 判準見 [ai-agent-setup.md 的 MCP 那節](ai-agent-setup.md#3-mcp)。

## 排錯

| 症狀 | 原因 |
|---|---|
| `Target closed` / `Target.setDiscoverTargets` | 走到沒有 `--browser-url` 的設定了 —— 官方 plugin 又被開起來,或設定被蓋掉。`chezmoi apply` 修回來 |
| `chrome-mcp` 跑完沒錯誤但 MCP 連不上 | 9222 沒通。`curl 127.0.0.1:9222/json/version` 確認;不通就查 `.wslconfig` 是不是 mirrored |
| Chrome 開起來但 9222 不通 | 日常 profile 已經開著,Chrome 忽略了 `--remote-debugging-port`。關掉全部 Chrome 視窗再跑 |
| agent 看到的網站沒登入 | 獨立 profile 是新的,手動登入一次 |
| `claude mcp list` 顯示 Failed | 先確認 Chrome 在跑,再 `/mcp` 重連 |

驗證整條路通了:

```bash
chrome-mcp                                       # Chrome 起來
curl -s 127.0.0.1:9222/json/version | jq .Browser  # 看得到版本號
claude mcp list                                  # chrome-devtools 顯示 Connected
```
