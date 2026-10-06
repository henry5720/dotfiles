# 瀏覽器偵錯 MCP 對照：Playwright vs chrome-devtools-mcp

這份只列事實，不做推薦。每格的來源用 `[代號]` 標示，代號對到文末「來源清單」的永久連結。

根據這份對照做的決定見 [ADR 0001](adr/0001-browser-debug-devtools-mcp-e2e-playwright.md)。

## 查證日期與版本

查證日期：2026-10-06。

| 套件 | 查到的版本 | 怎麼確認 | 讀的原始碼 |
|---|---|---|---|
| `@playwright/mcp` | 0.0.83（2026-09-28 發布） | `npm view @playwright/mcp version`、`gh release list -R microsoft/playwright-mcp` | repo tag `v0.0.83`（`f183dad`）。它的 `package.json` 依賴 `playwright@1.64.0-alpha-1790635538000` [pm-pkg]，對到 microsoft/playwright 的 commit `e8149b8`（時間戳 2026-09-28T22:45:38Z 完全相同），工具實作讀這顆 |
| `playwright` / `@playwright/test`（內含 test MCP server） | 1.63.0（2026-09-04 發布） | `npm view playwright version`、`gh release list -R microsoft/playwright` | tag `v1.63.0`（`1b025d7`） |
| `chrome-devtools-mcp` | 1.10.1（2026-09-23 發布） | `npm view chrome-devtools-mcp version`、`gh release list -R ChromeDevTools/chrome-devtools-mcp` | tag `chrome-devtools-mcp-v1.10.1`（`e52c6b5`） |

三個名字在下文的意思：

| 下文寫法 | 正式名稱與入口 |
|---|---|
| **@playwright/mcp** | npm 套件 `@playwright/mcp`，`npx @playwright/mcp@latest` 啟動 [pm-intro] |
| **Playwright test MCP** | `playwright` CLI 的隱藏子指令 `npx playwright run-test-mcp-server`，server 名稱 `Playwright Test Runner`、設定鍵 `playwright-test-runner` [pt-cmd]。`npx playwright init-agents --loop=<claude\|codex\|opencode\|vscode…>` 產生的 MCP 設定把它登記成 `playwright-test` [pt-gen-mcpjson]。給 Playwright Test Agents（planner / generator / healer，1.56 起）用 [pt-agents-doc] [pt-release] |
| **chrome-devtools-mcp** | npm 套件 `chrome-devtools-mcp`，README 標題是「Chrome DevTools for agents」，`npx chrome-devtools-mcp@latest` 啟動 [cd-readme] |

Playwright test MCP 的瀏覽器工具就是 `playwright-core` 那套 `browserTools`，外加 `intent` 參數，
而且只對「暫停中的 test」的頁面下指令（先跑 seed test 或 `test_debug` 停在錯誤處）[pt-backend]。
所以下表 Playwright test MCP 那欄常寫「同 @playwright/mcp」，差別是版本（1.63.0 vs 1.64 alpha）與瀏覽器從哪來。

## 背景

這個 repo 目前用 chrome-devtools-mcp 連 Windows Chrome 的 9222，當初選它的理由沒有紀錄。
teamsync-frontend 的 e2e 用 Playwright。這份對照用來決定平常偵錯要不要統一成一套。

| 位置 | 內容 |
|---|---|
| `home/private_dot_ssh/private_config` 第 111-122 行 | `company-ec2-chrome` 用 `RemoteForward 127.0.0.1:9222 127.0.0.1:9222`（第 119 行）把本機 Chrome 的 9222 帶到 EC2，註解寫「給那邊的 chrome-devtools MCP 用」 |
| commit `96dbf78`，`home/dot_config/opencode/private_opencode.json.tmpl` 第 94-103 行 | 當時 opencode 的 `chrome-devtools` 用 `chrome-devtools-mcp@latest --browser-url=http://127.0.0.1:9222 --no-usage-statistics --no-performance-crux` |
| commit `96dbf78`，`docs/ai-agent-setup.md` 第 218-229 行 | WSL 經 mirrored networking 連 Windows `127.0.0.1:9222`；Windows Chrome 用 `--remote-debugging-port=9222 --user-data-dir="$env:LOCALAPPDATA\ChromeDevToolsMCP"` 啟動，那個 profile 第一次要手動登入 |
| commit `62bd4b8`（`feat: chezmoi 交出 MCP，改由 skillshare 管理`） | 上一列的 opencode 樣板已刪；`docs/ai-agent-setup.md` 第 369 行說版本釘在 agent-config 的 `mcp.yaml` |
| agent-config `mcp.yaml` 第 3-13 行 [ac-mcp] | 現在的設定：`chrome-devtools-mcp@1.10.1 --browser-url=http://127.0.0.1:9222 --no-usage-statistics --no-performance-crux`，發到 claude、codex、opencode |

## 1. console 訊息

| 項目 | @playwright/mcp | Playwright test MCP | chrome-devtools-mcp |
|---|---|---|---|
| 工具 | `browser_console_messages` [pm-console-doc] | 同 @playwright/mcp（v1.63.0 那份）；planner、healer agent 有列這個工具 [pt-planner-agent] [pt-healer] | `list_console_messages`、`get_console_message`（用 `msgid` 取單筆）[cd-ref-console] |
| 過濾 | `level`：error / warning / info / debug，每級含更嚴重的級別；`all` 決定要不要含上次導覽之前的；啟動參數 `--console-level` 設預設 [pm-console-doc] [pm-opts] | 同左 | `types` 陣列（log、error、warn…還有 `issue`，即 DevTools Issues）、`pageSize`/`pageIdx` 分頁、`serviceWorkerId`、`includePreservedMessages`（最近 3 次導覽）[cd-ref-console] [cd-console-src] |
| 每筆的格式 | `[TYPE] 文字 @ url:行號`；未捕捉的 page error 輸出 `error.stack` [pa-tab-msg] | 同左 [pt-tab-msg] | 列表一行一筆；`get_console_message` 回 ID、Message、各個 Arguments、Stack trace [cd-console-snap] |
| stack trace | 一般 console 訊息只有來源 url 與行號，不含 stack；page error 有 stack [pa-tab-msg] | 同左 | `includeStackTraces` 可在列表帶 stack；`get_console_message` 回 stack 與 Error 的 `cause` 鏈 [cd-ref-console] [cd-console-snap] |
| source map | 原始碼裡未見 source map 處理（未查到相關選項） | 同左 | 有。README 寫「source-mapped stack traces」，`--sourceMaps` 預設開 [cd-readme] [cd-mcp-opts]；測試快照可見對回原始檔行號 [cd-console-snap] |
| 存檔 | `filename` 參數存成檔 [pm-console-doc] | 同左 | 未查到存檔參數 |

## 2. network 請求

| 項目 | @playwright/mcp | Playwright test MCP | chrome-devtools-mcp |
|---|---|---|---|
| 列表 | `browser_network_requests`：自頁面載入起的編號清單；預設藏起成功的靜態資源，`static: true` 才列；`filter` 用 regexp 比 URL [pa-net] | 同 @playwright/mcp；planner、healer agent 有列 [pt-healer] | `list_network_requests`：上次導覽起的請求；`resourceTypes` 過濾、分頁、`includePreservedRequests`（最近 3 次導覽）[cd-ref-net] |
| 單筆細節 | `browser_network_request` 用編號取：狀態、耗時、type、mimeType、request/response headers；body 用 `part=request-body` / `response-body` 另外取 [pa-net] [pa-net-detail] | 同左 | `get_network_request` 用 `reqid` 取 headers 與 body；body 可用 `requestFilePath` / `responseFilePath` 存檔；不給 `reqid` 時取 DevTools Network 面板目前選取的那筆 [cd-ref-net] |
| 敏感 header | 未查到遮罩選項 | 同左 | `--redactNetworkHeaders` 可遮掉部分敏感 header（預設關）[cd-config] |
| 攔截／mock | `browser_route`、`browser_route_list`、`browser_unroute`、`browser_network_state_set`（離線），要 `--caps=network` [pm-tools] | 有（test MCP 掛上全部 browser tools，不經 `--caps` 過濾）[pt-backend] [pt-browsertools] | 沒有 mock 工具；`emulate` 的 `networkConditions` 可設 Offline / 3G / 4G 節流，`extraHttpHeaders` 加 header [cd-ref-emul] |

## 3. element／accessibility snapshot

| 項目 | @playwright/mcp | Playwright test MCP | chrome-devtools-mcp |
|---|---|---|---|
| 工具 | `browser_snapshot`；另有 `browser_find` 只回符合文字的節點與上下文 [pm-snap-doc] [pm-tools] | 同 @playwright/mcp（v1.63.0 也有 `browser_find`）[pt-browsertools] | `take_snapshot`（`verbose` 取完整 a11y tree）[cd-ref-snap] |
| 格式 | YAML 式 ARIA snapshot，例如 `- button "Button 1" [ref=e2]`；`boxes` 或 `--snapshot-boxes` 加 `[box=x,y,w,h]` [pt-test-snap] [pm-snap-doc] | 同左 | 縮排文字，例如 `uid=1_1 button "Click me" focusable focused` [cd-snap-example] [cd-snapfmt] |
| 元素代號 | `ref`（`e2` 這種），點擊等工具的 `target` 填 ref，內部轉成 `aria-ref=` locator；`target` 也接受 selector [pa-snap] [pa-tab-ref] | 同左 | `uid`（`1_1` 這種），`click`、`fill`、`take_screenshot`、`get_css_styles` 都用它；文件要求永遠用最新 snapshot [cd-ref-snap] |
| 動作後自動附 snapshot | 預設會附，`--snapshot-mode none` 關掉 [pm-opts] | 未查到對應參數 | 未查到 |
| 其他 | `depth` 限制深度、`filename` 存檔 [pm-snap-doc] | 同左 | snapshot 會標出 DevTools Elements 面板目前選取的元素；`get_css_styles` 回 matched rules、繼承與 cascade [cd-ref-snap] [cd-ref-css] |

## 4. performance trace

| 項目 | @playwright/mcp | Playwright test MCP | chrome-devtools-mcp |
|---|---|---|---|
| 工具 | `browser_start_tracing` / `browser_stop_tracing`（要 `--caps=devtools`）[pm-devtools-doc] | 同名工具存在於 browser tools [pt-browsertools] | `performance_start_trace`、`performance_stop_trace`、`performance_analyze_insight` [cd-ref-perf] |
| 錄的是什麼 | Playwright trace：`browserContext.tracing.start({ screenshots, snapshots })`，產出 action log、network log、resources，給 Trace Viewer 看 [pa-tracing]。不是 Chrome Performance 面板的 trace | 同左 | Chrome DevTools performance trace；可 `reload`、`autoStop`，原始 trace 可存 `.json.gz` [cd-ref-perf] |
| 分析／insights | 無 | 無 | stop 後回 trace 摘要與「Available insight sets」，再用 `performance_analyze_insight` 看單項（例如 `LCPBreakdown`、`DocumentLatency`）；描述提到 LCP、INP、CLS [cd-ref-perf] |
| CrUX 實測資料 | 無 | 無 | 有，預設把 trace 的 URL 送 Google CrUX API 抓 field data；`--no-performance-crux` 關 [cd-readme] [cd-perf-crux] |

## 5. Lighthouse

| 項目 | @playwright/mcp | Playwright test MCP | chrome-devtools-mcp |
|---|---|---|---|
| 有沒有 | 工具清單裡沒有 [pm-tools] | 沒有 [pt-browsertools] | `lighthouse_audit` [cd-ref-lh] |
| 範圍 | — | — | accessibility、SEO、best-practices、agentic-browsing，**不含 performance**（文件叫你改用 performance trace）；`mode` navigation / snapshot；`device` desktop / mobile；輸出 JSON 與 HTML 報告 [cd-ref-lh] [cd-lh-src]。內建 `lighthouse` 13.4.1 [cd-pkg] |

## 6. 連既有 Chrome

| 項目 | @playwright/mcp | Playwright test MCP | chrome-devtools-mcp |
|---|---|---|---|
| CDP URL | `--cdp-endpoint <endpoint>`，可加 `--cdp-header`、`--cdp-timeout` [pm-opts]；實作是 `playwright.chromium.connectOverCDP`，只走 Chromium [pa-cdp] | 指令只有 `--headless`、`-c`、`--host`、`--port` 四個參數 [pt-cmd]，未查到連既有 Chrome 的方式；瀏覽器由 `playwright.config` 的 project 決定 [pt-planner] | `--browser-url`（例如 `http://127.0.0.1:9222`）或 `--ws-endpoint` + `--ws-headers` [cd-config] [cd-adv] |
| 連上後用哪個 context | 非 isolated 時用 `browser.contexts()[0]`，也就是那個 Chrome 既有的 context；`--isolated` 則開新 context [pa-ctx] | — | 用那個 Chrome 的頁面；`--autoConnect` 時可存取該 profile 所有開著的視窗 [cd-adv] |
| 不開 debug port 的連法 | `--extension`：裝「Playwright Extension」後連正在跑的 Chrome / Edge 分頁，`--profile-dir-name` 選 profile [pm-opts] [pm-profile] | — | `--autoConnect`：Chrome 144+，在 `chrome://inspect/#remote-debugging` 開啟後由 Chrome 跳視窗徵求同意 [cd-adv] |
| 其他遠端 | `--endpoint`（Playwright 自己的 bound browser endpoint）[pm-opts] [pa-cdp] | — | VM 連 host 被 Host header 擋時，文件建議 `ssh -L` 轉 9222 [cd-trouble] |

## 7. headless

| 項目 | @playwright/mcp | Playwright test MCP | chrome-devtools-mcp |
|---|---|---|---|
| 參數 | `--headless` [pm-opts] | `--headless` [pt-cmd] | `--headless` [cd-config] |
| 沒給參數時 | Linux 且沒有 `DISPLAY` 時自動 headless，其他情況 headed [pa-headless] | 有 `CI` 環境變數、或 Linux 沒有 `DISPLAY` 時 headless，否則 headed [pt-ctx-headed] | 預設 `false`（headed）[cd-config]；headless 時最大 viewport 3840x2160 [cd-config] |
| 有 headed 需求但沒螢幕 | README 建議在有 `DISPLAY` 的環境用 `--port` 跑成 HTTP server [pm-standalone] | `--port` 也可用 SSE [pt-cmd] | 未查到 |

## 8. Docker／sandbox

| 項目 | @playwright/mcp | Playwright test MCP | chrome-devtools-mcp |
|---|---|---|---|
| 官方 image | `mcr.microsoft.com/playwright/mcp`，**只支援 headless Chromium**；repo 附 `Dockerfile`（`node:lts-slim` + tini）[pm-docker] [pm-dockerfile] | 未查到 | 未查到（repo 根目錄無 Dockerfile，`server.json` 只登記 npm）[cd-server-json] |
| 關 Chrome sandbox | `--no-sandbox` / `--sandbox` [pm-opts]。沒指定時：Linux 上用下載的 Chromium（channel 未設、`chromium`、`chrome-for-testing`）會自動關 sandbox，用 `chrome` 等正式 channel 才開 [pa-sandbox] | 未查到 MCP 層參數；依 `playwright.config` 的 launch 設定 | 沒有專用參數；`--chrome-arg='--no-sandbox' --chrome-arg='--disable-setuid-sandbox'`（`--help` 範例，註明「Use with caution」）[cd-nosandbox] |
| 以 root 執行 | 未查到專門說明（Docker 範例本身帶 `--no-sandbox`）[pm-docker] | 未查到 | Chrome 不以 root 啟動；偵測到 root 且沒 `--no-sandbox` 時改丟明確錯誤，叫你在容器裡建非 root 使用者 [cd-root] [cd-trouble] |
| MCP client 自己的 sandbox | README 寫 Playwright MCP「不是 security boundary」[pm-docker] | 未查到 | Seatbelt / Linux 容器沙箱下開不了 Chrome，解法是對它關 client sandbox 或改用 `--browser-url` 連沙箱外的 Chrome [cd-trouble] |
| WSL | 未查到 | 未查到 | 在 WSL 要裝 Linux 版 Chrome；啟動 Windows 側 Chrome 會因 WSL 已知問題失敗 [cd-trouble] |

## 9. 登入狀態沿用

| 項目 | @playwright/mcp | Playwright test MCP | chrome-devtools-mcp |
|---|---|---|---|
| 預設 profile | 持久 profile，Linux 在 `~/.cache/ms-playwright/mcp-{channel}-{workspace-hash}`，不同專案自動分開 [pm-profile] | 由 test 決定（`playwright.config`、seed test）[pt-planner] | 持久 profile，`$HOME/.cache/chrome-devtools-mcp/chrome-profile`（非 stable channel 加後綴）[cd-adv] |
| 指定目錄 | `--user-data-dir` [pm-opts] | — | `--user-data-dir` [cd-config] |
| 不留痕 | `--isolated`：profile 只在記憶體 [pm-opts] | — | `--isolated`：暫存目錄，關瀏覽器就刪 [cd-config] |
| storage state 檔 | `--storage-state <path>`（搭配 isolated）；工具 `browser_storage_state` / `browser_set_storage_state` 存讀，cookie 與 localStorage 也有個別工具（`--caps=storage`）[pm-profile] [pm-tools] | 同名工具存在 [pt-browsertools]；test 本身可用 config 的 storageState（Playwright Test 一般用法，本次未讀該文件） | 未查到 storage state 匯入匯出 |
| 同時多個 client | 同一 profile 一次只能一個瀏覽器，否則報「Browser is already in use」，要 `--isolated` 或不同目錄 [pm-profile] | — | 同一 user data dir 一次只能一個瀏覽器 [cd-adv]；共用一個 server 時預設用 `pageId` 分流 [cd-adv] |
| 沿用日常 Chrome 的登入 | `--extension`（連正在跑的 Chrome/Edge）或 `--cdp-endpoint` [pm-profile] [pm-opts] | — | `--autoConnect` 或 `--browser-url`；文件說以 WebDriver 方式自己開的 Chrome 有些帳號會擋登入，這是連既有 Chrome 的理由之一 [cd-adv] |

## 其他差異

| 項目 | @playwright/mcp | Playwright test MCP | chrome-devtools-mcp |
|---|---|---|---|
| 工具數 | 預設 25 個（core 24 + `browser_tabs`）；`--caps` 開 config 1、network 4、storage 15、devtools 13、vision 6、pdf 1、testing 5 [pm-tools] | 9 個 test 專用（`planner_*` 3、`generator_*` 3、`test_list` / `test_run` / `test_debug`）+ 全部 browser tools 不經過濾 [pt-backend] | tool reference 共 58 個，分 11 類 [cd-ref-index]；其中 extensions、third-party、WebMCP、PWA、`click_at`、screencast、多數 heap 分析工具要另外打開 [cd-config]；`--slim` 只留 3 個 [cd-config] |
| 瀏覽器 | `--browser`：chrome、firefox、webkit、msedge [pm-opts] | 依 `playwright.config` projects（`test_run` 的 `projects` 參數）[pt-tools] | 官方只支援 Google Chrome 與 Chrome for Testing，其他 Chromium 系「可能可用但不保證」[cd-readme] |
| 自動化底層 | Playwright | Playwright Test runner | Puppeteer 25.11.0 [cd-readme] [cd-pkg] |
| emulation | 啟動時 `--device`、`--mobile`、`--viewport-size`、`--user-agent`、`--grant-permissions` [pm-opts]；工具 `browser_emulate_media`（color scheme、reduced motion、forced colors、contrast、print）、`browser_resize` [pm-emul-doc] [pa-emul] | v1.63.0 沒有 `browser_emulate_media`（該檔在 1.64 alpha 才出現）[pt-browsertools] | `emulate`：color scheme、CPU 節流、網路節流、geolocation、user agent、viewport（含 DPR、mobile、touch）、extra headers；`resize_page` [cd-ref-emul] |
| screenshot | `browser_take_screenshot`：png/jpeg/webp、`fullPage`、單一元素、`scale` css/device [pm-shot-doc] | 同左 | `take_screenshot`：png/jpeg/webp、`quality`、`fullPage`、單一元素（`uid`）；`--screenshotMaxWidth/Height` 縮圖 [cd-ref-shot] [cd-config] |
| heap snapshot | 無 [pm-tools] | 無 | `take_heapsnapshot` 預設可用；摘要、retainers、dominators、比較兩份等 12 個分析工具要 `--memoryDebugging` [cd-ref-mem] [cd-config] |
| 產生測試碼 | 每個動作回應附對應 Playwright 程式碼，`--codegen` 選 typescript / python / java / csharp / none [pm-opts]；`browser_start_recording` 錄使用者操作成程式碼、`browser_generate_locator`（caps）[pm-devtools-doc] [pm-testing-doc] | `generator_setup_page` → 操作 → `generator_read_log` → `generator_write_test` 寫成 test 檔 [pt-gen] | 原始碼與文件未查到產生測試碼的工具 |
| 座標（vision）模式 | `--caps=vision`：`browser_mouse_click_xy` 等 6 個 [pm-vision-doc] | 同名工具存在 [pt-browsertools] | `--experimentalVision`：`click_at(x,y)` [cd-ref-clickat] [cd-config] |
| 錄影 | `browser_start_video` / `browser_stop_video`（devtools caps）[pm-devtools-doc] | 同名工具存在 | `screencast_start` / `screencast_stop`，要 `--experimentalScreencast` 和 ffmpeg [cd-ref-screencast] [cd-config] |
| 遙測 | 未查到 | 未查到 | 預設送 usage statistics 給 Google，`--no-usage-statistics` 或設 `CI` 關；預設檢查 npm 更新 [cd-readme] |

## 未查到／待確認

- Playwright（兩種）的 console 訊息有沒有做 source map：原始碼只看到 `url:行號` 與 `error.stack`，沒找到 source map 選項；沒找到不等於確定沒有。
- `@playwright/mcp` README 的 `--caps` 說明只列 `vision, pdf, devtools` [pm-opts]，但同一份 README 的工具清單還有 `config`、`network`、`storage`、`testing` 四個 caps [pm-tools]。兩處不一致，以工具清單與原始碼 `filteredTools` 為準 [pa-tools]。
- Playwright test MCP：沒有官方文件頁（指令是 `hidden`）[pt-cmd]；Docker、sandbox、連既有 Chrome、登入狀態都只能推到「看 `playwright.config`」，MCP 層未查到對應參數。
- Playwright test MCP 對 `browserTools` 不經 `--caps` 過濾、全部掛上 [pt-backend]，但實際 agent 定義只挑了一部分 [pt-healer] [pt-planner-agent]；client 端是否全部顯示依 client 而定，未實測。
- chrome-devtools-mcp：官方 Docker image 未查到。
- chrome-devtools-mcp：console 存檔、storage state 匯入匯出、動作後自動附 snapshot，未查到。
- `@playwright/mcp` 以 root 跑時的行為說明，未查到。
- 兩邊的確切「預設啟用工具數」：@playwright/mcp 從 README 數得 25；chrome-devtools-mcp 只數了 reference 總數 58，預設啟用幾個沒有逐一核對旗標。

## 來源清單

`@playwright/mcp`（tag `v0.0.83`）

- `pm-intro`：[pm-intro]
- `pm-pkg`：[pm-pkg]
- `pm-opts`：[pm-opts]
- `pm-profile`：[pm-profile]
- `pm-standalone`：[pm-standalone]
- `pm-docker`：[pm-docker]
- `pm-dockerfile`：[pm-dockerfile]
- `pm-tools`：[pm-tools]
- `pm-console-doc`：[pm-console-doc]
- `pm-emul-doc`：[pm-emul-doc]
- `pm-snap-doc`：[pm-snap-doc]
- `pm-shot-doc`：[pm-shot-doc]
- `pm-devtools-doc`：[pm-devtools-doc]
- `pm-vision-doc`：[pm-vision-doc]
- `pm-testing-doc`：[pm-testing-doc]

`@playwright/mcp` 實際用的 playwright-core（commit `e8149b8`，即 `1.64.0-alpha-1790635538000`）

- `pa-console`：[pa-console]
- `pa-tab-msg`：[pa-tab-msg]
- `pa-tab-ref`：[pa-tab-ref]
- `pa-net`：[pa-net]
- `pa-net-detail`：[pa-net-detail]
- `pa-snap`：[pa-snap]
- `pa-tracing`：[pa-tracing]
- `pa-emul`：[pa-emul]
- `pa-tools`：[pa-tools]
- `pa-cdp`：[pa-cdp]
- `pa-ctx`：[pa-ctx]
- `pa-headless`：[pa-headless]
- `pa-sandbox`：[pa-sandbox]

Playwright test MCP（tag `v1.63.0`）

- `pt-cmd`：[pt-cmd]
- `pt-backend`：[pt-backend]
- `pt-ctx-headed`：[pt-ctx-headed]
- `pt-tools`：[pt-tools]
- `pt-planner`：[pt-planner]
- `pt-gen`：[pt-gen]
- `pt-browsertools`：[pt-browsertools]
- `pt-tab-msg`：[pt-tab-msg]
- `pt-test-snap`：[pt-test-snap]
- `pt-gen-mcpjson`：[pt-gen-mcpjson]
- `pt-healer`：[pt-healer]
- `pt-planner-agent`：[pt-planner-agent]
- `pt-agents-doc`：[pt-agents-doc]
- `pt-release`：[pt-release]

chrome-devtools-mcp（tag `chrome-devtools-mcp-v1.10.1`）

- `cd-readme`：[cd-readme]
- `cd-pkg`：[cd-pkg]
- `cd-server-json`：[cd-server-json]
- `cd-config`：[cd-config]
- `cd-adv`：[cd-adv]
- `cd-trouble`：[cd-trouble]
- `cd-ref-index`：[cd-ref-index]
- `cd-ref-clickat`：[cd-ref-clickat]
- `cd-ref-emul`：[cd-ref-emul]
- `cd-ref-perf`：[cd-ref-perf]
- `cd-ref-net`：[cd-ref-net]
- `cd-ref-console`：[cd-ref-console]
- `cd-ref-css`：[cd-ref-css]
- `cd-ref-lh`：[cd-ref-lh]
- `cd-ref-shot`：[cd-ref-shot]
- `cd-ref-snap`：[cd-ref-snap]
- `cd-ref-screencast`：[cd-ref-screencast]
- `cd-ref-mem`：[cd-ref-mem]
- `cd-mcp-opts`：[cd-mcp-opts]
- `cd-nosandbox`：[cd-nosandbox]
- `cd-root`：[cd-root]
- `cd-console-src`：[cd-console-src]
- `cd-console-snap`：[cd-console-snap]
- `cd-snapfmt`：[cd-snapfmt]
- `cd-snap-example`：[cd-snap-example]
- `cd-perf-crux`：[cd-perf-crux]
- `cd-lh-src`：[cd-lh-src]

背景用到的 agent-config

- `ac-mcp`：[ac-mcp]

[pm-intro]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L1-L17
[pm-pkg]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/package.json#L38-L46
[pm-opts]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L401-L460
[pm-profile]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L462-L511
[pm-standalone]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L802-L821
[pm-docker]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L823-L861
[pm-dockerfile]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/Dockerfile
[pm-tools]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L885-L1662
[pm-console-doc]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L915-L923
[pm-emul-doc]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L950-L960
[pm-snap-doc]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L1103-L1111
[pm-shot-doc]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L1115-L1125
[pm-devtools-doc]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L1396-L1520
[pm-vision-doc]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L1523-L1588
[pm-testing-doc]: https://github.com/microsoft/playwright-mcp/blob/v0.0.83/README.md#L1605-L1660
[pa-console]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/backend/console.ts#L20-L42
[pa-tab-msg]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/backend/tab.ts#L581-L605
[pa-tab-ref]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/backend/tab.ts#L548
[pa-net]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/backend/network.ts#L30-L102
[pa-net-detail]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/backend/network.ts#L140-L174
[pa-snap]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/backend/snapshot.ts#L25-L52
[pa-tracing]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/backend/tracing.ts#L20-L77
[pa-emul]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/backend/emulation.ts#L22-L46
[pa-tools]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/backend/tools.ts#L51-L95
[pa-cdp]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/mcp/browserFactory.ts#L60-L139
[pa-ctx]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/mcp/program.ts#L155
[pa-headless]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/mcp/config.ts#L143-L144
[pa-sandbox]: https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/mcp/config.ts#L233-L241
[pt-cmd]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright/src/program.ts#L140-L158
[pt-backend]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright/src/mcp/test/testBackend.ts#L31-L91
[pt-ctx-headed]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright/src/mcp/test/testContext.ts#L97-L107
[pt-tools]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright/src/mcp/test/testTools.ts#L20-L88
[pt-planner]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright/src/mcp/test/plannerTools.ts#L25-L45
[pt-gen]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright/src/mcp/test/generatorTools.ts#L25-L106
[pt-browsertools]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright-core/src/tools/backend/tools.ts#L49-L77
[pt-tab-msg]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright-core/src/tools/backend/tab.ts#L542-L566
[pt-test-snap]: https://github.com/microsoft/playwright/blob/v1.63.0/tests/mcp/snapshot-mode.spec.ts#L30-L55
[pt-gen-mcpjson]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright/src/agents/generateAgents.ts#L50-L59
[pt-healer]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright/src/agents/playwright-test-healer.agent.md#L6-L17
[pt-planner-agent]: https://github.com/microsoft/playwright/blob/v1.63.0/packages/playwright/src/agents/playwright-test-planner.agent.md#L6-L28
[pt-agents-doc]: https://github.com/microsoft/playwright/blob/v1.63.0/docs/src/test-agents-js.md#L9-L47
[pt-release]: https://github.com/microsoft/playwright/blob/v1.63.0/docs/src/release-notes-js.md#L844-L870
[cd-readme]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/README.md#L13-L60
[cd-pkg]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/package.json#L79-L81
[cd-server-json]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/server.json
[cd-config]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/configuration.md
[cd-adv]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/advanced-usage.md
[cd-trouble]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/troubleshooting.md#L65-L114
[cd-ref-index]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L5-L73
[cd-ref-clickat]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L189-L201
[cd-ref-emul]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L275-L304
[cd-ref-perf]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L306-L342
[cd-ref-net]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L344-L371
[cd-ref-console]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L393-L445
[cd-ref-css]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L404-L416
[cd-ref-lh]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L418-L429
[cd-ref-shot]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L447-L460
[cd-ref-snap]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L462-L474
[cd-ref-screencast]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L476-L495
[cd-ref-mem]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/tool-reference.md#L497-L665
[cd-mcp-opts]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/src/config/mcp-options.ts#L160-L170
[cd-nosandbox]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/src/config/mcp-options.ts#L403-L408
[cd-root]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/src/BrowserManager.ts#L70-L108
[cd-console-src]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/src/tools/console.ts#L13-L46
[cd-console-snap]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/tests/tools/console.test.js.snapshot#L9-L69
[cd-snapfmt]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/src/formatters/SnapshotFormatter.ts#L68
[cd-snap-example]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/tests/McpResponse.test.js.snapshot#L336-L338
[cd-perf-crux]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/src/tools/performance.ts#L225-L250
[cd-lh-src]: https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/src/tools/lighthouse.ts#L34-L80
[ac-mcp]: https://github.com/henry5720/agent-config/blob/b369230c1396be65f26e99c78e08fe0bf450af34/mcp.yaml#L3-L13
