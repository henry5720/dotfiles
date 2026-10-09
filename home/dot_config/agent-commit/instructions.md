# Commit 共同作者

只記實際留下修改、或其建議已被採用的 agent；單純開過工具不算。只記工具身分，model、effort 與用量交給其他工具。

## 身分

- Claude Code：`Co-authored-by: Claude Code <noreply@anthropic.com>`
- Codex：`Co-authored-by: Codex <noreply@openai.com>`
- OpenCode：`Generated with OpenCode.`（正文標記；目前沒有已確認的官方共同作者 email）
- 其他 agent：沿用該工具已確認的 attribution；email 未確認時使用正文文字標記。

## 交接與提交

1. 在目前 worktree 用 `git rev-parse --git-path agent-coauthors` 取得待提交名單路徑。名單每行一個上述標記，只放 Git 本機資料，不加入 index。
2. 留下貢獻後，在交接或結束回覆前，把自身標記追加到名單；已有相同標記時略過。替其他 agent 記錄時，須有實際貢獻的依據。
3. commit 前，合併名單、本次提交者的貢獻與 message 既有標記。保留主要作者與其他 trailers；共同作者放尾端 trailer 區塊，正文標記放區塊前。共同作者按 email 去重，正文標記各一次。
4. 提交成功後，用 `git show -s --format=%B HEAD` 確認所有本次參與者都留下標記。缺漏或重複時修正剛建立的 commit，驗證後才回報完成；commit 失敗時保留名單。
5. 本次工作全部提交且 worktree 沒有剩餘修改時，刪除名單。部分提交時只加入能確認參與本次變更的 agent，保留名單供後續提交；無法確認時先釐清歸屬。工作全部丟棄時刪除名單；新工作開始前先確認名單是否仍對應目前修改。

同一 worktree 交接共用名單；不同 worktree 各自保留。跨 worktree 接手時，把相關共同作者一併交接。amend 保留原有標記；squash 彙整被合併 commits 的標記。
