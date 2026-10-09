## Commit attribution

opencode 建立或 amend commit 時：
- 保留原本的主要作者，以及既有 trailers 與其他工具的標記。
- commit message 的正文包含 `Generated with OpenCode.`，恰好一次；若有 trailer 區塊，標記放在區塊前，兩者留一個空行。
- 僅新增 opencode 的文字標記；其他工具的 attribution 只保留已存在的內容。
- 提交後用 `git show -s --format=%B HEAD` 確認標記恰好一次；缺少或重複時修正剛建立的 commit，確認後才回報完成。
