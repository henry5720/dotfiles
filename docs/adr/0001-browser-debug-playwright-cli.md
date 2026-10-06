# 瀏覽器偵錯平常用 playwright-cli，查部署環境的錯和效能才用 chrome-devtools-mcp

agent 操作瀏覽器時照下表挑工具。平常偵錯大多連本機 Vite dev server，所以預設用 `playwright-cli`：
headless 跑在 agent 同一台機器，登入靠 script 或 `state-save`／`state-load`，不用把 Windows Chrome 的 9222 轉發過來，
要看畫面就看它存下的截圖、影片。

| 情況 | 用什麼 |
|---|---|
| 平常偵錯：連本機 dev server，操作、看 console／network、mock API、截圖 | `playwright-cli`（`@playwright/cli`），headless |
| 連部署出去的環境（程式碼 minify 過）查前端報錯 | chrome-devtools-mcp，`--headless` 跑在同一台 |
| 查效能（performance trace、Lighthouse）、記憶體 | chrome-devtools-mcp |
| 要看 agent 在自己的 Chrome 裡操作 | chrome-devtools-mcp 連 Windows Chrome 9222（`company-ec2-chrome`） |
| 操作之後要重跑（防同一個 bug 再壞） | 寫成 Playwright e2e，寫的時候可以叫 `playwright-test` MCP 幫忙 |

## 依據：console 錯誤的位置（2026-10-06 實測）

測的是 `@playwright/cli` 0.1.22 和 chrome-devtools-mcp 1.10.1，同一支 Chrome 154 headless。

| 頁面怎麼來的 | `playwright-cli console` | chrome-devtools-mcp |
|---|---|---|
| esbuild minify + 外部 `.map` | 只有 `n (bundle.js:1:62)`，看不出是哪個函式；Chrome 沒去抓 `.map` | `computeTotal (app.ts:6:11)`，連 `setTimeout` 的 async 來源都有 |
| Vite 6 dev server（同 teamsync-frontend） | `computeTotal (/src/OrderList.tsx:21:11)`：檔名、函式名對，行號是 Vite 轉譯後的，比原始碼多 8～14 行 | 行號對回原始碼；但 try/catch 後 `console.error(e)` 的錯只給 console.error 那行，丟錯的位置和函式名不見 |

dev server 下 `playwright-cli` 的行號會偏，但有檔名和函式名就找得到。minify 過的程式碼只剩 `n`、`e` 這種名字，才非換工具不可。

各工具其他功能的對照與來源見 [瀏覽器偵錯 MCP 對照](../browser-mcp-comparison.md)。
