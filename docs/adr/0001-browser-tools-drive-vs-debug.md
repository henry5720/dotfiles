# 瀏覽器工具看動作挑：操作用 playwright-cli，查原因用 chrome-devtools-mcp

兩個都裝，不設預設。agent 要碰瀏覽器時，看這次要做的動作挑工具：

| 這次要做什麼 | 用什麼 | 為什麼 |
|---|---|---|
| **操作**：點、填表、跑流程、截圖、驗證功能沒壞、mock API | `playwright-cli`（`@playwright/cli`），headless | snapshot 存成檔案不塞進對話，省 token；跑在 agent 同一台，登入靠 script 或 `state-save`／`state-load`，不用轉發 9222；要看畫面就看它存下的截圖、影片 |
| **查原因**：為什麼慢、記憶體、部署環境（minify 過）為什麼報錯 | chrome-devtools-mcp | 只有它有 performance trace + insights、Lighthouse、heap snapshot，console stack 會經 source map 對回原始碼 |
| **在我現在這個 Chrome 裡查**：要沿用登入、要看著 agent 操作 | chrome-devtools-mcp 連 Windows Chrome 9222（`company-ec2-chrome`） | 直接接手眼前的 session，不用重建狀態 |
| **要重跑的**：防同一個 bug 再壞 | 寫成 Playwright e2e，寫的時候可以叫 `playwright-test` MCP 幫忙 | 寫一次就能 `npx playwright test` 重跑，不花 token，能進 CI |

常見的接法：用 `playwright-cli` 重現 → 卡在「為什麼」就換 chrome-devtools-mcp → 修好 → 把重現步驟寫成 e2e。

省 token 是 CLI 和 MCP 的差別，不是牌子的差別：chrome-devtools-mcp 也附了 experimental 的 `chrome-devtools` CLI
（[docs/cli.md](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/cli.md)），還不成熟所以先不用。

## 依據

### 外部做法（2026-10-06 查）

都是個人部落格或廠商文章，不是官方文件。

| 來源 | 說法 |
|---|---|
| [Steve Kinney](https://stevekinney.com/writing/driving-vs-debugging-the-browser) | 「Playwright drives. Chrome DevTools debugs. Pick on the verb, not the brand.」；兩個都裝，掛著的成本比挑錯工具低 |
| [test-lab](https://www.test-lab.ai/blog/chrome-devtools-mcp-vs-playwright-mcp-cli) | 在目前的瀏覽器裡查問題用 Chrome DevTools MCP；長時間、在意成本的執行用 Playwright CLI |
| [`@playwright/cli` README](https://github.com/microsoft/playwright-cli) | coding agent 用 CLI 是「the best fit」，因為不用載入大份 tool schema 和 accessibility tree |

### console 錯誤的位置（2026-10-06 實測）

測的是 `@playwright/cli` 0.1.22 和 chrome-devtools-mcp 1.10.1，同一支 Chrome 154 headless。

| 頁面怎麼來的 | `playwright-cli console` | chrome-devtools-mcp |
|---|---|---|
| esbuild minify + 外部 `.map` | 只有 `n (bundle.js:1:62)`，看不出是哪個函式；Chrome 沒去抓 `.map` | `computeTotal (app.ts:6:11)`，連 `setTimeout` 的 async 來源都有 |
| Vite 6 dev server（同 teamsync-frontend） | `computeTotal (/src/OrderList.tsx:21:11)`：檔名、函式名對，行號是 Vite 轉譯後的，比原始碼多 8～14 行 | 行號對回原始碼；但 try/catch 後 `console.error(e)` 的錯只給 console.error 那行，丟錯的位置和函式名不見 |

所以本機 dev server 上「操作順便看 console」用 `playwright-cli` 就找得到錯在哪；minify 過的程式碼只剩 `n`、`e`，才要換 chrome-devtools-mcp。

各工具其他功能的對照與來源見 [瀏覽器偵錯 MCP 對照](../browser-mcp-comparison.md)。
