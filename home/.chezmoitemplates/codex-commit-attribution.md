<!-- chezmoi:codex-commit-attribution:start -->
## Commit attribution

Codex 建立或 amend commit 時：
- 保留原本的主要作者，以及既有 trailers 與其他工具的標記。
- 執行 git commit 前，把 `Co-authored-by: Codex <noreply@openai.com>` 放進要提交的 message，恰好一次；trailer 區塊前留一個空行。
- 僅新增 Codex 的 attribution；其他工具的 attribution 只保留已存在的內容。
- 提交後用 `git show -s --format=%B HEAD` 確認標記恰好一次；缺少或重複時修正剛建立的 commit，確認後才回報完成。
<!-- chezmoi:codex-commit-attribution:end -->
