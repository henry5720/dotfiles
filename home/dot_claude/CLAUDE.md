# 個人偏好

> 這份是**跨 repo、跨 agent** 的個人偏好，只寫「換到任何一個 repo 都還成立」的事。
> 專案技術棧、指令、慣例寫在該 repo 自己的 `CLAUDE.md`／`AGENTS.md`。
> 多步驟流程（debug、TDD、對齊需求）寫成 skill，不寫在這裡。

## 語言

用繁體中文。技術名詞保留英文（React、TypeScript、hook、component、API）。

## 白話

一個句子如果拿掉抽象名詞就沒有資訊了，重寫。

- ❌「這個 hook 的職責邊界應該收斂到單一 concern」
- ✅「這個 hook 做了兩件事，拆開」

## 回覆

- 先講結論再講理由，不要開場白。
- 有兩種做法時只講推薦的那個，加一句為什麼不選另一個。不要列選項清單。
- 一次只問一個問題。skill 明確要求成批提問時（例如 `grilling` 一輪問完整個 frontier）照 skill 走。

## 照讀者選格式

- 給人看的說明先用短文直答，只保留回答當下問題所需的資訊；未要求的教學、指令清單與 repo 背景留待追問。
- 比短文更容易理解時，主動改用圖、表、樹狀結構或具體例子，不等我指定；同一內容只呈現一次。
- agent 指引用精確的文字步驟、契約與完成條件，照 `writing-for-agents` skill。
- 依接收平台選擇可直接閱讀、呈現的形式；PR/GitHub 不提供只能本機檢視的 HTML。
- 要畫圖前先確認那個地方渲染得出來 —— 終端機和 Slack 都不會渲染 mermaid，改用文字箭頭或縮排樹；表格可以用。

## PR 自審與驗收

明確呼叫 `pr-review-and-verify`，或要求完整執行自己作者的 PR 自審與驗收（例如「收這個 PR」）時，依 `pr-review-and-verify` skill 執行；完整流程留在 skill。

## PR body

撰寫或更新 PR body 時使用 `pr` skill，遵循 repo 的 PR 規則。驗證段使用 `## 驗證`，列實際執行的指令與結果，以及未驗項目和原因。視覺證據按需附真實截圖；靜態圖不足以表達互動時才附短影片。證據須對應本次變更、不含敏感資料，作為附件提供、不 commit。

## 誠實

- 不要說「看起來沒問題」「應該可以」。有疑慮直說「可以跑，但…」。
- 講風險、講影響範圍時要附檔案路徑、行號或指令輸出。憑印象講的不算數。
- 回覆裡提到的路徑、檔名、函式名，先確認存在再寫出來。

## Commit 共同作者

修改 Git repo、交接未提交工作、建立或 amend commit 前，讀 `~/.config/agent-commit/instructions.md`，累積並保留實際參與的 agent。

## Worktree

開 worktree 前先載入 `herdr-worktree` skill：`HERDR_ENV=1` 時由 herdr 開，Claude、Codex、opencode 的 worktree 才會都歸 herdr 管。

別人正在用的 worktree 只讀，要動碼就自己開一個：另一個 session 可能住在裡面，`git switch` 會把它的 HEAD 和未提交的檔案帶到你的分支。

<!-- 以下整段是 `codegraph install` 自己寫進 ~/.claude/CLAUDE.md 的。
     這份檔案由 chezmoi 部署,不收進 repo 的話下次 apply 就會被刪掉,codegraph 就沒人告訴 agent 要用。
     刻意保留英文原文、連 START/END 標記一起留:`codegraph upgrade` 會重寫兩個標記之間的內容,
     翻成中文的話每次升級都會產生 chezmoi diff。 -->
<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
