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
- 講流程用文字箭頭（`讀設定 → 掃 repo → 產出`）。要畫圖前先確認那個地方渲染得出來 —— 終端機和 Slack 都不會渲染 mermaid。

## 誠實

- 不要說「看起來沒問題」「應該可以」。有疑慮直說「可以跑，但…」。
- 講風險、講影響範圍時要附檔案路徑、行號或指令輸出。憑印象講的不算數。
- 回覆裡提到的路徑、檔名、函式名，先確認存在再寫出來。

## Worktree

`HERDR_ENV=1` 時，開 worktree 走 herdr，不要讓 `EnterWorktree` 自己開：

```
herdr worktree create --cwd <repo> --branch <name> --base <ref> --no-focus   # 回傳 .worktree.path
EnterWorktree --path <那個 path>
```

`--cwd` 要給**主 checkout**，給 linked worktree 會回 `linked_worktree_source`。
`--base` 不給就用預設分支 —— 要疊在別人剛做好的那顆 commit 上時記得指定，不必從頭來。

開在 `~/.herdr/worktrees/<repo>/<branch>`，在 repo 外面，不會被 IDE、檔案搜尋、watcher 掃進去。
代價是順便開一個 herdr workspace，用完 `herdr worktree remove --workspace <id>` 收掉。

沒有 herdr 就用內建的 `EnterWorktree`，它固定開在 `<repo>/.claude/worktrees/`，路徑改不了。
⚠️ 已經 `EnterWorktree` 進去之後就**換不到第二個 herdr worktree**（`--path` 只認
`<repo>/.claude/worktrees/` 底下的）。要換基底就在**現在這個** worktree 裡 `git switch`。

**不要在別人正在用的 worktree 裡 `git switch`。** 長期 worktree（例如某條整合分支那份）
隨時可能有另一個 session 住在裡面，切分支會把它的 HEAD 從腳下抽走，它未提交的檔案會跟著
跑到你的分支名下。要動碼就自己開一個。

**什麼時候收**：合併完、而且在**目標分支那份 checkout** 上驗過、確定不用回去改，就收。
不要全部留到最後，worktree 和分支會越積越多。

**收掉不會弄丟東西** —— 分支 ref 住在主 checkout 的 `.git/refs/heads/`，`worktree remove`
不刪分支也不刪 commit，換個 session 一樣找得到。所以**不要為了備份去 push 葉子分支**
（推上去就永遠躺在 remote，不會有 PR 也沒人刪）；只有換裝置、換人接手、過夜離開機器才推，
合併後當天 `git push origin --delete`。

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
