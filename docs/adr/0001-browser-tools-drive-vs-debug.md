# 瀏覽器工具看動作挑：操作用 playwright-cli，查原因用 chrome-devtools-mcp

兩個都裝，主力是 `playwright-cli`。agent 要碰瀏覽器時，看這次要做的動作挑工具：

| 這次要做什麼 | 用什麼 | 為什麼 |
|---|---|---|
| **驗收、操作**：改完確認剛寫的功能能動（有人或無人值守）；點、填表、跑流程、截圖、mock API | `playwright-cli`（`@playwright/cli`），headless | 跑在 agent 同一台，不用轉發 9222；登入照 script 填 `/login` 表單，或 `state-save` 存一次、之後 `state-load`，state 檔能帶進無人值守的容器；跟 frontend e2e 同一套 Playwright，驗收完要防回歸可以直接寫成 test；常駐 token 最低。主動看頁面結構用 `snapshot --filename`，裸 `snapshot` 會把整棵樹印進對話 |
| **查原因**：為什麼慢、記憶體、部署環境（minify 過）為什麼報錯 | chrome-devtools-mcp | 只有它有 performance trace + insights、Lighthouse、heap snapshot，console stack 會經 source map 對回原始碼 |
| **要重跑的**：防同一個 bug 再壞 | 寫成 Playwright e2e，寫的時候可以叫 `playwright-test` MCP 幫忙 | 寫一次就能 `npx playwright test` 重跑，不花 token，能進 CI |

常見的接法：用 `playwright-cli` 驗收 → 卡在「為什麼」就換 chrome-devtools-mcp → 修好 → 值得防回歸的才寫成 e2e，一次性的修正不寫。

company-ec2 上的 headless 瀏覽器留兩支，各做一件事（2026-11-04 實測，[#247](https://github.com/henry5720/dotfiles/issues/247)）：

- **操作**：`playwright-cli open` 自己開 Chrome。不改成一律 `attach --cdp`：attach 的 session 全部擠在同一個分頁、共用 cookie，設定檔（語系等）不生效，`state-load` 還會蓋掉 MCP 也在用的登入狀態。`attach` 只在要跟 chrome-devtools-mcp 看同一頁時用。
- **查原因**：`google-chrome --headless --remote-debugging-port=9222` 開在 9222 給 chrome-devtools-mcp（指令見 [瀏覽器](../remote-access/browser.md)）。`mcp.yaml` 各機器共用一份、寫死 `--browser-url=http://127.0.0.1:9222`，MCP 只負責接、不自己開 Chrome：Chrome 由 agent 開、用完收掉，9222 只在查原因時佔著。以前包成 `remote-chrome-headless`，#278 拿掉：只包一行指令。
- **人要看畫面、接手**：`playwright-cli show --port <port>`（只綁 127.0.0.1）+ `ssh -L`。0.1.23 開互動模式後可以在畫面上點擊、打字。

瀏覽器在人的個人電腦上時，有兩個入口，接的是不同的 Chrome：

| 入口 | 接到哪支 Chrome | 什麼時候用 | 分頁 |
|---|---|---|---|
| **CDP 9222** | 個人電腦上**獨立 profile** 的 Chrome，開 `--remote-debugging-port=9222` 再 `ssh -R` 到 company-ec2 的 9222 | 人自己要用、讓 agent 控：人看著本地視窗，agent 遠端操作 | 多個 |
| **Playwright 插件**（9555） | 人**日常 profile** 的 Chrome，`playwright-cli attach --extension=chrome` | 一定要日常 profile 裡的東西：passkey、硬體金鑰、裝置 SSO | 只有人貼網址的那一個 |

- **9222 是通用的 CDP 入口，不是 chrome-devtools-mcp 專用。** `playwright-cli attach --cdp=http://127.0.0.1:9222` 操作、chrome-devtools-mcp 查原因，兩個都能接同一支 Chrome。
  [#261](https://github.com/henry5720/dotfiles/issues/261) 拿掉這條，是當時以為它只給 chrome-devtools-mcp 用；[#278](https://github.com/henry5720/dotfiles/issues/278) 加回來，指令寫在 [瀏覽器](../remote-access/browser.md)、不另外包 script。
- **為什麼要獨立 profile**：Chrome 136 起不能對日常 profile 開 debugging port，只能另開一個 user-data-dir。那個 profile 一開始沒有人的登入，
  人在視窗裡登入一次就會留著。日常 profile 只能靠插件從裡面接出一個分頁，所以插件只是另一個入口，不是另一種工具。
- **company-ec2 的 9222 同時只有一個**：人的轉發開著時是他的獨立 profile；沒開時才開 headless 給查原因用。
  `mcp.yaml` 寫死 9222，所以 chrome-devtools-mcp 不用改設定就接得上當下佔著 9222 的那支。
- **自動化、驗收照舊用 company-ec2 上的 headless 瀏覽器**（上面那兩支）：不靠人的電腦開著，能無人值守。
- 插件那條：agent-config 的 `browser-access` skill 附的 `personal-chrome-attach` 把 relay 固定在 127.0.0.1:9555，人開 `ssh -L` 9555 的轉發、把網址貼進新分頁；
  agent 只看得到那一個分頁，用完 `detach`，Chrome 和分頁留著（2026-11-04 實測，[#248](https://github.com/henry5720/dotfiles/issues/248)）。

省 token 是 CLI 和 MCP 的差別，不是牌子的差別：chrome-devtools-mcp 也附了 `chrome-devtools` CLI
（[docs/cli.md](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/cli.md)）。官方部落格 2026-05-19 說它 stable 了，
repo 文件（1.10.1）還寫 experimental；主力已經是 `playwright-cli`，所以先不用。

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

### 其他工具與 token 消耗（2026-10-07 查、實測）

Playwright MCP、agent-browser、dev-browser、Playwriter、Claude in Chrome 等也比過，結論不變。

| 不選 | 為什麼 |
|---|---|
| Playwright MCP | 跟 `playwright-cli` 同一套實作，常駐 schema ~5.1k token，`playwright-cli` 平常只佔 skill 說明 ~19 |
| agent-browser | 每步回應最小（0.41.2 實測 snapshot 是 `playwright-cli` 的 56–80%，`-i` 只剩 25–31%），`--pin-tab` 也能跟其他 CDP client 共用 Chrome 不搶分頁；但每個 session 的 daemon 在 127.0.0.1 開一個不用驗證、回 `Access-Control-Allow-Origin: *` 的 HTTP port，company-ec2 上的其他 process 都能操作，也不能產出 Playwright 程式碼（2026-11-04 重測，[#247](https://github.com/henry5720/dotfiles/issues/247)） |
| Playwriter、dev-browser、Claude in Chrome | 賣點是接自己 Chrome 的登入；agent 在 EC2、Chrome 在 Windows，等於換個方式轉發 9222。Claude in Chrome 還要看得到的 Chrome |

登入：TeamSync 是 `/login` 帳密表單，teamsync-tutorials 的 `shared/shoot-lib.mjs` 的 `login()` 已經 headless 自動登入，
所以無人值守也登得進去。

數字、來源和哪些是實測見 [coding agent 臨時驗收前端的瀏覽器工具調查](../research/agent-browser-tools.md)；
各工具其他功能的對照見 [瀏覽器偵錯 MCP 對照](../research/browser-mcp-comparison.md)。
