# 瀏覽器偵錯用 chrome-devtools-mcp，要留下來的寫成 Playwright e2e

agent 操作瀏覽器時，用「這次的操作要不要留下來」決定工具，兩套不統一：

| 這次的操作 | 用什麼 | 為什麼 |
|---|---|---|
| 看完就丟（重現 bug、查原因、量效能） | chrome-devtools-mcp，連已登入的 Chrome 9222 | console stack 經 source map 對回原始碼，還有 performance trace + insights、Lighthouse、heap snapshot。`@playwright/mcp` 沒有這些工具 |
| 之後要重跑（防止同一個 bug 再壞） | Playwright script（e2e），寫的時候可以叫 `playwright-test` MCP 幫忙 | 寫一次就能用 `npx playwright test` 重跑，不花 token，能進 CI，每次跑的結果都一樣 |

兩套常常前後接著用：用 chrome-devtools-mcp 重現 bug、找到原因 → 修好 → 把重現步驟寫成 Playwright e2e。

**不統一成 `@playwright/mcp` 的原因**：它也能連 9222（`--cdp-endpoint`），但換過去會少掉上表第一列那些偵錯功能，多出來的 mock、storage state、產生測試碼又只有寫 e2e 時用得到。
例外：如果平常偵錯常常要假造 API 回應，就在偵錯時加上 `@playwright/mcp`，因為 chrome-devtools-mcp 沒有 mock 工具。

每項功能的來源與版本見 [瀏覽器偵錯 MCP 對照](../browser-mcp-comparison.md)。
