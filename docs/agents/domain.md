# Domain docs

這是 single-context repository。

## 探索前先讀

- 根目錄 `CONTEXT.md`（如果存在）
- `docs/adr/` 中與目前工作相關的 ADR（如果存在）

檔案不存在時直接繼續，不要因為缺少它們而阻塞工作。

## 詞彙

issue title、refactor proposal、hypothesis、test name 使用
`CONTEXT.md` 已定義的 domain vocabulary；如果需要的新概念不存在，
交給 domain modeling 再決定，不要自行創造同義詞。

## ADR 衝突

如果變更與既有 ADR 衝突，要明確指出 ADR 編號與衝突原因，不要靜默覆蓋。
