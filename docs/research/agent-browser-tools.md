# coding agent 臨時驗收前端：瀏覽器工具調查

查證日期：2026-10-07。環境是 AWS EC2（Linux、沒有螢幕）、Chrome 154、node 22。

**問題**：agent 在 EC2 上改完 Vite + React 前端後，要能自己開瀏覽器點一點、看畫面、看 console 和 network，附截圖回報。
不是跑 e2e。限制：工具最多 2 個、不能吃太多 context、要擺脫「Windows Chrome 9222 轉發到 EC2」、頁面可能要 SSO、之後可能無人值守跑。

**結論**：[ADR 0001](../adr/0001-browser-tools-drive-vs-debug.md)（操作用 `playwright-cli`，查原因用 chrome-devtools-mcp）大方向不用改，
但有三處要更新：拿掉「連 Windows Chrome 9222」那一列；SSO 改用 `playwright-cli show --port` 的遠端 dashboard 登入一次再 `state-save`（實測可行）；
「snapshot 存成檔案不塞進對話」只對動作指令成立，主動下 `snapshot` 會把整棵樹印出來。細節見文末[既有文件哪裡過時](#既有文件哪裡過時)。

來源標示：**[實測]** 是這次在本機跑出來的數字；**[官方]** 是工具作者自己的文件或原始碼；**[廠商]** 是競品作者寫的比較；**[社群]** 是推文回覆。

## 1. 候選工具總表

星數、版本都是 2026-10-07 用 `gh api repos/<repo>`、`npm view` 查的。

| 工具 | 維護者 | 介面 | 瀏覽器怎麼來 | 無螢幕 Linux headless | 保留登入 | console／network | 轉成 Playwright test | 成熟度 |
|---|---|---|---|---|---|---|---|---|
| **chrome-devtools-mcp**（含 `chrome-devtools` CLI） | Google Chrome DevTools 團隊 | MCP；CLI；skill | 自己 launch，或 `--browser-url`／`--autoConnect` 接現有 Chrome [cd-cfg] | 可以，`--headless`；CLI 預設 headless [cd-cli] | `--user-data-dir` 持久 profile；沒有 storage state 匯入匯出 [cmp] | 有，console 經 source map 對回原始碼 [cmp] | 沒有 [cmp] | 53.0k★，v1.10.1（2026-09-23）；官方部落格 2026-05-19 宣布 1.0 stable [cd-blog] |
| **`@playwright/cli`**（`playwright-cli`） | Microsoft Playwright 團隊 | CLI + skill | 自己 launch；`attach --cdp`／`--extension` 接現有 Chrome [pwc-open] | 可以，預設就是 headless [pwc-headed] | `--persistent`、`--profile`、`state-save`／`state-load` [pwc-sess] | `console`、`requests`、`request <n>`、`route` mock [pwc-devtools] | `recording-start`／`recording-stop` 印出 Playwright 程式碼；每個動作回應附「Ran Playwright code」[實測] | 13.8k★，v0.1.22（2026-09-28）。版本號還是 0.x |
| **Playwright MCP**（`@playwright/mcp`） | Microsoft Playwright 團隊 | MCP | 自己 launch；`--cdp-endpoint`／`--extension` [cmp] | 可以；Linux 沒有 `DISPLAY` 會自動 headless [cmp] | 預設持久 profile、`--storage-state` [cmp] | 有 [cmp] | 每個動作附程式碼，`--codegen` [cmp] | 37.9k★，v0.0.83（2026-09-28） |
| **Playwriter** | 個人（remorses） | CLI + skill（推薦）；MCP | Chrome 擴充套件接**你正在用的 Chrome**；也能 `playwriter browser start` 開 Chrome for Testing [pw-readme] | README 沒寫 headless。遠端要在有 Chrome 的那台跑 `playwriter serve`，再用 tunnel 或 LAN 連過去 [pw-readme] | 直接用你 Chrome 裡的登入 | 要自己寫 Playwright 程式碼去聽事件 [pw-readme] | 寫的本來就是 Playwright API，可以抄去當 test，但沒有產生器 | 4.0k★，0.7.0（2026-09-16） |
| **dev-browser** | 個人（Sawyer Hood） | CLI + skill；MCP | 自己 launch，或 `--connect` 接現有 Chrome [db-readme] | 可以，`--headless` [db-readme] | 持久 profile 存在 `~/.dev-browser/v1` [db-readme] | 要在腳本裡自己做（Puppeteer API） | 1.0 改用 Puppeteer，轉不成 Playwright [db-readme] | 6.7k★。npm latest 0.2.9；1.0 還是 `next` tag 的 rc.3（2026-09-05） |
| **agent-browser** | Vercel Labs | CLI（Rust）+ skill；MCP | 自己 launch Chrome for Testing；`--auto-connect`、`connect <port>` 接現有 Chrome [ab-readme] | 可以；沒有 `DISPLAY` 又要 `--headed` 時會自己開 Xvfb [ab-readme] | `--profile`、`state save/load`、加密的 auth vault [ab-readme] | `console`、`network requests`、HAR、route mock [ab-readme] | 沒有 codegen | 43.6k★，v0.38.2（2026-10-01）。0.x，發版很密 |
| **Claude in Chrome**（`claude --chrome`） | Anthropic | 擴充套件 + 內建 MCP | 你的 Chrome（會開一個看得到的視窗）[cc-chrome] | 不行，要有在跑的 Chrome。WSL 不支援 [cc-chrome] | 直接用你 Chrome 裡的登入；碰到登入頁會停下來叫你處理 [cc-chrome] | 能讀 console [cc-chrome]；network 文件沒寫 | 沒有 | Claude Code 內建。要用 claude.ai 帳號登入；API key、Bedrock 不能用 [cc-chrome] |

其他有一定採用度的，各一行帶過：

| 工具 | 一句話 | 為什麼不列入主表 |
|---|---|---|
| browser-use／browser-harness | browser-use 117k★ 是 Python agent 框架；它的 CLI `browser-harness`（18.3k★）透過 CDP 接你的 Chrome，agent 會邊做邊寫 helper [bh-readme] | 預設接你自己的 Chrome，主打雲端瀏覽器 |
| Stagehand（Browserbase） | 25.6k★ 的 SDK，`act("click sign in")` 這類 API 背後要再叫一次 LLM，需要 OpenAI 等 API key [sh-readme] | 是給你寫 agent 用的程式庫，不是給 coding agent 驗收用的。Browserbase 的 MCP repo 已經 archived |
| gstack `/browse` | gstack（135k★）裡的瀏覽器 skill，macOS 優先開 Aside 瀏覽器，沒有 Aside 才用自己 build 的 headless Chromium [gs-readme] | 綁著整套 gstack（23 個 skill），不能單獨裝 |
| Vibium | Selenium 作者做的，WebDriver BiDi，CLI skill 加 MCP，自稱「The verification layer for coding agents」[vb-readme] | 2.9k★，只有 nightly 版 |
| BrowserMCP（`@browsermcp/mcp`） | 擴充套件型 MCP | repo 最後 push 是 2025-04 |
| hangwin/mcp-chrome | 擴充套件型 MCP，12.5k★ | 最後 push 是 2026-01 |

## 2. Token 消耗

### 2a. 常駐成本：MCP 的 tools/list [實測]

做法：用 stdio 對每個 server 送 `initialize` → `tools/list`，有 `nextCursor` 就跟到最後一頁，量 compact JSON 字元數，token 用「字元 ÷ 4」估。
腳本 `/tmp/btok/scripts/mcp-measure.mjs`（沒進 repo）。

| server | 參數 | tool 數 | tools/list 字元 | 估 token |
|---|---|---|---|---|
| chrome-devtools-mcp 1.10.1 | 預設（加 `--headless` 也一樣） | 30 | 26,398 | ~6,600 |
| chrome-devtools-mcp 1.10.1 | `--slim` | 3（navigate、evaluate、screenshot） | 964 | ~240 |
| @playwright/mcp 0.0.83 | 預設 | 25 | 20,296 | ~5,100 |
| @playwright/mcp 0.0.83 | `--caps=network,storage,devtools` | 59 | 38,367 | ~9,600 |
| playwriter 0.7.0 | 預設 | 2 | 56,347 | ~14,100 |
| agent-browser 0.38.2 `mcp` | 預設 core profile | 29 | 63,487 | ~15,900 |
| agent-browser 0.38.2 `mcp --tools all` | 共 3 頁 | 156 | 328,479 | ~82,100 |
| dev-browser 1.0.0-rc.3 `mcp --headless` | | 5 | 1,890 | ~470 |
| @browsermcp/mcp 0.1.3 | | 12 | 4,218 | ~1,050 |

- playwriter 只有 2 個工具，但 `execute` 的 description 本身就是 54k 字元的手冊。它 serverInfo 的 title 寫「No context bloat」，跟實測不符。
- **在 Claude Code 裡，上表不等於常駐成本**。Claude Code 預設開 tool search，開場只載入 tool 名稱和 server instructions，schema 要用到才載入 [cc-mcp]。
  每個 tool description 還會被截在 2,048 字元 [cc-mcp]，所以 playwriter 那份 54k 手冊在 Claude Code 裡會被截斷。
  例外：`ANTHROPIC_BASE_URL` 指到非官方 host 時 tool search 會關掉，改成全部預先載入 [cc-mcp]。這台機器沒有設這個變數。
  Codex、opencode 會不會延遲載入，這次沒查。

### 2b. 常駐成本：CLI 與 skill [實測]

skill 的 frontmatter `description` 每個 session 都載入；body 要等 skill 被觸發才載入。

| 工具 | 常駐（description） | 觸發時載入 | 另外 |
|---|---|---|---|
| `playwright-cli` skill | 77 字元（~19 token） | 15,205（~3.8k） | 10 個參考檔共 53k 字元，用到才讀。不裝 skill、只讀 `--help` 是 7,662（~1.9k） |
| `chrome-devtools` CLI skill | 134（~33） | 11,352（~2.8k） | |
| chrome-devtools-mcp 附的 MCP 用 skill | 275（~68） | 4,000（~1k） | 要另外加上 MCP schema |
| agent-browser skill | 925（~230） | 2,411（~600） | skill 只是個 stub，會叫 agent 跑 `agent-browser skills get core`，stdout 37,633（~9.4k） |
| dev-browser skill | 425（~106） | 1,353（~340） | skill 叫 agent 先讀 `dev-browser --help`：rc.3 是 29,644（~7.4k） |
| playwriter skill | 沒有 frontmatter | 70,856（~17.7k） | |

### 2c. 每步成本 [實測]

同一個本機測試頁（約 30 個互動元素：nav、5 欄表單、10 列表格、modal），數字是回到 agent context 的文字字元數。
括號內是 playwright.dev 的數字，當作大頁面的參考。

| 工具 | 開頁 | 主動要 snapshot | click | console | network 列表 | 截圖 |
|---|---|---|---|---|---|---|
| chrome-devtools-mcp（headless） | 110（150） | 2,906（11,728） | 35（88） | 237 | 144（9,170） | **直接回圖片**，1905×2053 PNG |
| `chrome-devtools` CLI | 111（151） | 2,907（11,729） | 36（89） | 238 | 145（9,100） | 存檔，只回路徑 |
| @playwright/mcp（headless） | ~350（287），只附 `.yml` 路徑 | 3,638（14,014） | ~280，只附路徑 | 184 | 81 | 存檔，**也回圖片**，1280×720 |
| `playwright-cli` | 394（331），只附路徑 | **3,639（14,014），整棵樹印到 stdout**；`--filename=x.yml` 只回 141；`find "文字"` 回 370 | 280（269） | 185 | 82 | 存檔，只回路徑（330） |
| agent-browser | 40（39） | 全樹 3,258（9,294）；`snapshot -i` 2,158（2,971） | 7 | 0 | 139（8,823） | 存檔，只回路徑（55） |
| dev-browser rc.3 | 23 | `interactive:true` 1,305；全樹 3,546 | 沒量 | 沒量 | 沒量 | 存成 jpg，回路徑和尺寸 |

- **圖片 token 是推算，不是實測**：用 Claude 的公式（寬×高 ÷ 750，長邊先縮到約 1568）推，1280×720 約 1.2k token，
  chrome-devtools-mcp 的 1905×2053 縮完約 1.6k。只回路徑的工具，agent 要自己 `Read` 圖檔才會吃這份 token。
- @playwright/mcp 0.0.83 動作後附的 snapshot 現在是寫成檔案、只附連結；只有主動呼叫 `browser_snapshot` 才回整棵樹。
  依據：`playwright-core/lib/coreBundle.js` 的 `snapshotToFile = this._includeSnapshot !== "explicit" || ...`。
- `playwright-cli` README 說 `snapshot` 預設存成檔案 [pwc-snap]，但 0.1.22 實測是整棵樹印出來，要加 `--filename` 才只回路徑。
- 沒量到：playwriter、BrowserMCP 的每步成本（兩個都要先接擴充套件）、Claude in Chrome 的 schema 和每步成本（這台 EC2 跑不了）。

### 2d. 別人做過的 benchmark [廠商]

| 來源 | 結果 | 可信度 |
|---|---|---|
| [dev-browser-eval][db-eval]（dev-browser 作者，2025-12） | 同一個任務各跑 3 次：dev-browser $0.88／29 turns、Playwright MCP $1.45／51、Playwright Skill $1.45／38、Claude Code 內建 Chrome $2.81／80 | 競品作者自己做的，n=3，版本都是 2025 年底的舊版（dev-browser 0.x、Playwright MCP 當時每個動作還回整棵 snapshot），只能看方向 |
| Playwriter README [pw-readme] | 說 Claude 擴充套件用截圖（100KB+），Playwriter 用 a11y snapshot（5–20KB） | 競品比較表，沒有附量測方法 |

## 3. 社群在說什麼

### Matt Pocock 那則推文

推文 [mp-1]（2026-01-11，1,178 讚，73 則回覆，約 9.9 萬次瀏覽）原文只有一句：「Playwright MCP + Ralph is incredible. Article coming soon」。
x.com 直接抓會回 402，內文和回覆是用 `api.fxtwitter.com` 的 status 與 conversation API 抓的。他在回覆裡講清楚用途：
「it's more like manual QA, it doesn't write tests - just affirms that its changes work」。這跟使用者要的「臨時驗收」是同一件事。

隔天那則 [mp-2]（2026-01-12，2,850 讚，約 22 萬次瀏覽）是影片〈Frontend is HARDER for AI than backend (here's how to fix it)〉[mp-video] 的宣傳。
Matt 自己在回覆列了三個工具（199 讚）：**Playwriter、dev-browser、chrome-devtools MCP**。這次沒有出現 Playwright MCP。

回覆裡大家推薦的（讚數是 2026-10-07 的數字）：

| 推薦 | 誰說的、怎麼說 |
|---|---|
| chrome-devtools-mcp | @mattiasgeniar（64 讚，第一則推文最高讚的回覆）：「Switched almost entirely to Chrome directly with MCP」；@sankalpsthakur：長 session 比 Playwright 好管 |
| Playwriter | @dctanner（25 讚）試了 6 個瀏覽器 plugin／skill，說只有 Playwriter 和 dev-browser「reliable and not context hogs」；@8am1am、@Greg__LD、@AlexisVedia 也推，理由是省 token、用同一個瀏覽器的登入 |
| dev-browser | @dctanner（同上）、@grahamcodes、@luisrudge（讓 opencode 自己測完才算做完）、@BasedCampZH |
| Claude in Chrome | 有人問為什麼不用 `/chrome`。Matt 兩次都回：他在 WSL，Claude in Chrome 不支援 WSL，所以沒試 |
| 嫌 context 太大 | @dctanner：chrome-devtools MCP「is a context hog」；@FUCORY：Playwright MCP「eat up context fast」 |
| 寫成 e2e 就好 | @tzachbonfil、@hauke_schnau 主張直接寫 Playwright e2e。Matt 回：「e2e should be saved for the REALLY IMPORTANT SHIT, not one-off assertions that a fix worked」 |
| agent-browser | 只有 1 則回覆在問，當時（2026-01）剛發布 |

影片本身沒抓到：YouTube 對這台 EC2 的 IP 要求登入（`LOGIN_REQUIRED`、yt-dlp 回「Sign in to confirm you're not a bot」），
所以拿不到逐字稿和說明欄。**「影片裡用 chrome-devtools-mcp 接 `--browserUrl http://127.0.0.1:9222`」這件事沒查到原始出處**。
能確認的只有：他在 WSL 上開發（他自己在回覆裡講的），而 chrome-devtools-mcp 官方 troubleshooting 說從 WSL 直接啟動 Windows 側的 Chrome 會失敗 [cmp]，
所以 WSL 使用者常見的做法是讓 Windows Chrome 開 9222，再用 `--browser-url` 連過去（這個 repo 以前的設定就是這樣）。兩件事吻合，但這是推論。

### 有沒有共識

**沒有一個工具勝出，但理由有共識**。大家反覆提的就兩件事：

1. **context 成本**：嫌 MCP 的 schema 和 snapshot 太大，偏好 CLI／skill、一次只回需要的東西。
2. **登入狀態**：Playwriter、dev-browser、Claude in Chrome 被推，都是因為能用你自己 Chrome 的登入。

星數最多的是 chrome-devtools-mcp（53k），其次 agent-browser（43.6k）、Playwright MCP（37.9k）。
但推文回覆裡推 Playwriter 和 dev-browser 的人，比推前三者的多。

## 4. 官方建議

| 來源 | 說法 |
|---|---|
| Anthropic，Claude Code best practices [cc-bp] | 「Give Claude a check it can run: tests, a build, a screenshot to compare」；也要 Claude 拿出證據（測試輸出、指令與結果、截圖），不要只說成功。文件說 CLI 工具是「the most context-efficient way to interact with external services」 |
| Anthropic，Claude in Chrome 文件 [cc-chrome] | 用例包含「Test a local web application」「Debug with console logs」。預設啟用會讓瀏覽器工具和說明一直佔 context，建議需要時才 `--chrome` |
| Anthropic engineering blog（2025-11-26）[an-harness] | 長時間跑的 agent 要明確叫它「use browser automation tools and do all testing as a human user would」；當時用的是 Puppeteer MCP。給了這種工具之後，agent 抓得到光看程式碼看不出來的 bug |
| Claude Code 內建 `/run`、`/verify` skill（2.1.292 隨附）[cc-run] | web app 的做法是 dev server 加 headless Chromium 的 CLI REPL（`chromium-cli`），流程是 `nav` → `wait-for` → 操作 → `screenshot` → `console --errors`。`chromium-cli` 不是公開套件：npm 上同名套件是佔位用的，說明寫「not a real npm package」。找不到時，skill 叫你用 Playwright 自己寫一個 REPL |
| Playwright 官方「Coding agents」頁 [pw-doc-cli] | `playwright-cli`「is best for coding agents (Claude Code, GitHub Copilot, etc.)」，因為不用載入大份 tool schema 和 accessibility tree；MCP 留給需要持續狀態的探索式自動化、長時間自主流程 |
| Chrome DevTools 官方 | README：只做基本瀏覽器操作就用 `--slim` [cd-readme]。1.0 部落格（2026-05-19）宣布 MCP server 和 CLI 都 stable，CLI 是「A token-efficient alternative that allows agents to batch actions into scripts」[cd-blog]。但 repo 的 `docs/cli.md`（1.10.1）還寫 **experimental** [cd-cli]，兩邊不一致 |

三家都說「CLI 比 MCP 省 context」。Anthropic 自己內建的驗收 skill 用的也是 headless 瀏覽器 + CLI REPL 的形狀。

## 5. 這個使用者的條件

| 條件 | playwright-cli | chrome-devtools-mcp | agent-browser | Playwriter／dev-browser／Claude in Chrome |
|---|---|---|---|---|
| 跑在 EC2 本機、不轉發 9222 | 可以，headless | 可以，`--headless` | 可以 | 要接 Windows 那邊的 Chrome，還是得打通網路（tunnel、轉發或擴充套件 relay） |
| SSO 登入 | **實測可行**，見下方 | headless 下沒有讓人登入的入口；沒有 storage state 匯入 | `--auto-connect` + `state save`，或 auth vault | 直接用你 Chrome 的登入，這是它們最大的優點 |
| 無人值守（issue → PR） | 可以，state 檔帶進去 | 可以 | 可以 | Claude in Chrome 要看得到的 Chrome 和 claude.ai 登入；其他兩個要你的 Chrome 開著 |
| 截圖當證據 | 存檔、回路徑；也能錄影 | 直接回圖片（吃 image token） | 存檔、回路徑；也能錄影 | — |
| 轉成 Playwright test | `recording-start`／每步附程式碼 | 沒有 | 沒有 | — |
| 跟 repo 現有 e2e（Playwright）同一套 | 是 | 不是（Puppeteer） | 不是 | — |

**SSO 實測**（2026-10-07，`@playwright/cli` 0.1.22，`DISPLAY` 清空）：

1. `playwright-cli -s=ssotest open https://example.com` 開一個 headless session。
2. `playwright-cli -s=ssotest show --port=9333 --host=127.0.0.1` 把 dashboard 當成 HTTP server 跑起來，印出 `Listening on http://127.0.0.1:9333`。
   `--port`／`--host` README 沒寫，是在原始碼看到的 [pwc-show-src]。
3. 用另一個瀏覽器打開 dashboard：看得到 `ssotest` 的即時畫面。開「interactive mode」後在網址列輸入新網址，`ssotest` 真的導覽過去了。
   用 `playwright-cli -s=ssotest eval "location.href"` 確認，回 `https://www.iana.org/help/example-domains`。

所以使用者可以 `ssh -L 9333:127.0.0.1:9333 ec2` → 在 Windows 瀏覽器開 dashboard → 自己完成一次 SSO → `state-save` 存檔，之後 agent 用 `state-load` 帶著登入跑。
**沒驗到的**：在 dashboard 的頁面區塊裡打字、點擊（README 說可以接管滑鼠鍵盤 [pwc-show]，這次只驗了網址列）；真的 SSO（含 MFA）流程；SSO cookie 多久過期。

## 6. 建議

**主力用 `playwright-cli`，chrome-devtools-mcp 改成在 EC2 本機 headless 跑，只在查原因時用。** 也就是 ADR 0001 的分工，拿掉 9222 轉發。

理由：

- **只有它同時滿足**：EC2 headless、SSO 有實測可行的路、無人值守能帶 state 檔、產出 Playwright 程式碼（跟 repo 現有 e2e 同一套）、官方維護。
- **常駐成本最低**：skill description 只佔 ~19 token，觸發時 ~3.8k [實測]。三家官方都說 coding agent 用 CLI。
- **要注意兩件事**：叫 agent 用 `snapshot --filename` 或 `find`，不要裸用 `snapshot`（整棵樹 3.6k～14k 字元進 context）[實測]；
  還有版本是 0.1.x，指令可能會變。

為什麼不選 agent-browser：每步回應最小（click 回 7 字元），登入選項最多，headless 也行。但它的 skill 一觸發就要多讀 ~9.4k token 的 `skills get core`，
比 playwright-cli 大一倍多；沒有 codegen，驗收步驟轉不成 Playwright test；0.38 版發版很密。如果哪天不在乎轉成 test，它是最接近的替代品。

為什麼不選社群推的 Playwriter、dev-browser：它們的優點是用你自己 Chrome 的登入，前提是 agent 跟 Chrome 在同一台機器。
這位使用者的 agent 在 EC2、Chrome 在 Windows，用它們還是要打通網路，等於換個方式做 9222 轉發。

chrome-devtools-mcp 留著的理由（照 ADR 0001 的實測）：minify 過的程式碼要經 source map 對回原始碼，還有 performance trace、Lighthouse，這些只有它有。
在 Claude Code 裡 MCP schema 是延遲載入，掛著不用的成本只有工具名稱。要注意它截圖會直接回 1905×2053 的圖。

## 既有文件哪裡過時

| 文件 | 原本寫 | 現在查到 |
|---|---|---|
| ADR 0001 第 7 行 | `playwright-cli`「snapshot 存成檔案不塞進對話」 | 只對動作指令（open、click）成立。主動下 `snapshot` 會把整棵樹印到 stdout，要加 `--filename` [實測] |
| ADR 0001 第 9 行 | 在我現在的 Chrome 裡查：chrome-devtools-mcp 連 Windows Chrome 9222 | 使用者想擺脫這條。SSO 可以改用 `playwright-cli show --port` 登入一次再 `state-save` [實測] |
| ADR 0001 第 14-15 行 | `chrome-devtools` CLI 是 experimental，先不用 | 官方部落格 2026-05-19 說 CLI 已 stable [cd-blog]，但 repo 文件 1.10.1 還寫 experimental [cd-cli]。兩邊不一致 |
| browser-mcp-comparison §3 | @playwright/mcp 動作後「預設會附」snapshot | 會附，但 0.0.83 附的是 `.yml` 檔案連結，不是整棵樹 [實測] |
| browser-mcp-comparison「未查到」 | chrome-devtools-mcp 預設啟用幾個工具沒核對 | 預設 30 個，`--slim` 3 個 [實測] |
| browser-mcp-comparison 版本表 | 0.0.83／1.63.0／1.10.1 | 2026-10-07 還是同樣的版本，沒過時 |

## 沒查到／待確認

- Matt Pocock 影片的逐字稿和說明欄：YouTube 擋了這台 EC2 的 IP。「他在影片裡用 `--browserUrl http://127.0.0.1:9222`」這件事沒有原始出處。
- 他說的「Article coming soon」：aihero.dev 的 sitemap 裡沒找到瀏覽器相關的文章。
- Claude in Chrome：tool schema 大小和每步成本沒量（這台沒有 Chrome 擴充套件）。另外，文件提到 `bridge.claudeusercontent.com` 這個 WebSocket bridge，
  也提到「remote sessions」，但沒寫 EC2 上的 CLI 能不能接 Windows 上的擴充套件。沒試。
- Codex、opencode 對 MCP schema 是不是延遲載入，沒查。
- playwriter 的 `--browser headless`、每步成本，沒試。
- `playwright-cli` 的 `--persistent` profile 重開後，SSO 的 session cookie 還在不在，沒驗。`state-save` 會不會存到 session cookie，也沒驗。

## 來源清單

這份調查自己做的

- `cmp`：[瀏覽器偵錯 MCP 對照](../browser-mcp-comparison.md)（2026-10-06，版本與這次相同）
- 實測腳本與原始輸出在 `/tmp/btok/`、`/tmp/btres/scripts/`，沒進 repo

Anthropic

- `cc-chrome`：https://code.claude.com/docs/en/chrome
- `cc-bp`：https://code.claude.com/docs/en/best-practices （「Give Claude a way to verify its work」「Use CLI tools」兩節）
- `cc-mcp`：https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search
- `cc-run`：Claude Code 2.1.292 隨附的 `run` skill，`examples/playwright.md`；npm `chromium-cli` 0.0.1-placeholder 的說明
- `an-harness`：https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents

Microsoft Playwright

- `pwc-headed`、`pwc-sess`、`pwc-show`：https://github.com/microsoft/playwright-cli/blob/b85c7a736bb473bf55b584e54a09ffa698d6d871/README.md#L67-L130
- `pwc-devtools`：https://github.com/microsoft/playwright-cli/blob/b85c7a736bb473bf55b584e54a09ffa698d6d871/README.md#L253-L287
- `pwc-open`：https://github.com/microsoft/playwright-cli/blob/b85c7a736bb473bf55b584e54a09ffa698d6d871/README.md#L302-L318
- `pwc-snap`：https://github.com/microsoft/playwright-cli/blob/b85c7a736bb473bf55b584e54a09ffa698d6d871/README.md#L320-L358
- `pwc-show-src`：https://github.com/microsoft/playwright/blob/e8149b8257d32dcf8f72573ecc43e72439da7080/packages/playwright-core/src/tools/cli-client/program.ts#L214-L247 （`@playwright/cli` 0.1.22 依賴的 playwright-core 1.64.0-alpha-1790635538000）
- `pw-doc-cli`：https://github.com/microsoft/playwright/blob/d469960fdfc461e2d5795a3fa48a58a52a91ecaf/docs/src/getting-started-cli.md

Chrome DevTools

- `cd-readme`：https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/README.md
- `cd-cli`：https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/cli.md
- `cd-cfg`：https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.10.1/docs/configuration.md
- `cd-blog`：https://developer.chrome.com/blog/devtools-for-agents-v1

其他工具（README，2026-10-07 的 main）

- `pw-readme`：https://github.com/remorses/playwriter/blob/33d5c5a2c5ebf702e387d94d609e038c98e0acec/README.md
- `db-readme`：https://github.com/SawyerHood/dev-browser/blob/a25e7672e199153b2f5b52a841a62436a28d925f/README.md
- `db-eval`：https://github.com/SawyerHood/dev-browser-eval/blob/0270c6c5167c8b7f1b7efcbb731ca4109a423776/benchmark-comparison.md
- `ab-readme`：https://github.com/vercel-labs/agent-browser/blob/f7c8b071343dda29477a56cb336ea76144c05496/README.md
- `bh-readme`：https://github.com/browser-use/browser-harness/blob/afbcc381b963040c19627d788e40c7e7663171ee/README.md
- `sh-readme`：https://github.com/browserbase/stagehand （README）
- `gs-readme`：https://github.com/garrytan/gstack/blob/28f1385eac65cab592fe267956f07b205271df1b/README.md
- `vb-readme`：https://github.com/VibiumDev/vibium/blob/d16a6aaae7887c80fa2f92358285ad19103e4c6d/README.md

社群

- `mp-1`：https://x.com/mattpocockuk/status/2010298867947073968 （回覆用 `https://api.fxtwitter.com/2/conversation/2010298867947073968` 抓）
- `mp-2`：https://x.com/mattpocockuk/status/2010728707997278296
- `mp-video`：https://www.youtube.com/watch?v=pSritFeoYFo
