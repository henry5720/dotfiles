# chrome-devtools MCP:讓 agent 開你的瀏覽器

Claude Code 和 opencode 都接了 `chrome-devtools-mcp`,agent 因此能開網頁、點按鈕、看
console、抓 network、跑 lighthouse。這份記的是**這台機器上為什麼要這樣設**,不是這個 MCP
的用法(用法看[官方 repo](https://github.com/ChromeDevTools/chrome-devtools-mcp))。

## 前置與連線

```
WSL launcher → WSL interop → Windows Chrome（獨立 profile，9222）
WSL MCP server → mirrored localhost → Windows Chrome:9222
```

需要 WSL interop 可呼叫 Windows `cmd.exe` / `powershell.exe`、Windows 已安裝 Chrome，且
`.wslconfig` 使用 `networkingMode=mirrored`（見 [`wsl/.wslconfig`](../wsl/.wslconfig)）。
launcher 會啟動 Chrome 並等 `127.0.0.1:9222` 可用；`--browser-url` 是 MCP server 的參數，
用來連該 endpoint，不是 MCP client 的通用參數。
WSL 不開 Linux Chrome，也不應把 9222 暴露到 LAN。

> ⚠️ **不要在 WSL 裝 Linux Chrome。** `npx puppeteer browsers install chrome` 會抓 80MB 到
> `~/.cache/puppeteer`,然後你有兩個瀏覽器、agent 連的還是錯的那個。方向就是錯的,設定本來
> 就是連 Windows 那台。

## 怎麼用

```bash
chrome-mcp        # 開 Windows Chrome 並開 9222;已經在跑就直接結束
```

部署自 [`home/dot_local/bin/executable_chrome-mcp`](../home/dot_local/bin/executable_chrome-mcp),
落在 `~/.local/bin/chrome-mcp`(那個目錄已經在 PATH 裡,見 `home/dot_zshrc` 第 3 節)。

**Chrome 要先跑起來，MCP client 才連得上。** 重開 Chrome 後，
Claude Code 可在 session 執行 `/mcp` 重連；其他 client 請用該 client 自己的 reconnect/restart 方法，
`/mcp` 不是所有 agent 通用指令。

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

MCP server 的定義由 [skillshare](https://github.com/runkids/skillshare) 管,清單在
agent-config repo 的 `mcp.yaml`(chrome-devtools 的版本也釘在那裡)。`skillshare sync mcp -g`
把它寫進三個 client 各自的設定檔,只動自己寫的那幾個條目:

| client | 寫進哪裡 |
|---|---|
| Claude Code | `~/.claude.json` 的 `mcpServers` |
| Codex | `~/.codex/config.toml` 的 `[mcp_servers.*]` |
| OpenCode | `~/.config/opencode/opencode.json` 的 `mcp` |

這個 repo 只剩兩件跟 chrome-devtools 有關的事:

| 檔案 | 部署到 | 管什麼 |
|---|---|---|
| [`home/dot_claude/modify_settings.json`](../home/dot_claude/modify_settings.json) | `~/.claude/settings.json` | 關掉官方 chrome-devtools plugin |
| [`home/dot_local/bin/executable_chrome-mcp`](../home/dot_local/bin/executable_chrome-mcp) | `~/.local/bin/chrome-mcp` | 開 Windows Chrome 的 9222 |

Codex 與 OpenCode 那兩份設定檔 chezmoi 還在管 provider 等其他 key,所以它們的 `modify_` 會把
skillshare 寫的 MCP 條目原樣留著。新增、改參數、升版本都改 agent-config 的 `mcp.yaml`,
**不要改這個 repo**。

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

不關掉的話它會跟 skillshare 寫的那台 MCP server 同時出現,同一組工具兩份,Claude 有一半機率挑到壞的。

官方裝法(`claude mcp add chrome-devtools npx chrome-devtools-mcp@latest`)也生不出正確設定,
少的就是 `--browser-url`,所以參數要記在 agent-config 的 `mcp.yaml`,不能靠重跑 installer。

## 排錯

| 症狀 | 原因 |
|---|---|
| `Target closed` / `Target.setDiscoverTargets` | 走到沒有 `--browser-url` 的設定了 —— 官方 plugin 又被開起來(`chezmoi apply` 修回來),或 MCP 條目被改掉(`skillshare sync mcp -g` 修回來) |
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
