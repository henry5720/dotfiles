# Issue tracker：GitHub

這個 repo 的 issue 和 spec 都是 GitHub issue，所有操作都用 `gh` CLI。

## 慣例

- 建立：`gh issue create --title "..." --body "..."`
- 讀取：`gh issue view <number> --comments`
- 列出：`gh issue list --state open`
- 留言：`gh issue comment <number> --body "..."`
- 加 label：`gh issue edit <number> --add-label "..."`
- 關閉：`gh issue close <number> --comment "..."`

## PR 不當 triage 入口

PR 當作提需求的入口（PRs as a request surface）：否。

## Wayfinding

Wayfinder map 是帶 `wayfinder:map` label 的 GitHub issue。它的決定 ticket 是 child issue，
帶 `wayfinder:research`、`wayfinder:prototype`、`wayfinder:grilling` 或 `wayfinder:task`。

## 照 ticket 做事

`/implement`、`/implement-spec` 做 ticket 時，狀態都留在 GitHub 上（對照上游 wayfinder 的 Claim／Resolve）：

- **Claim**：`gh issue edit <n> --add-assignee @me`，動手前的第一個寫入。issue 已關、有開著的 blocker、或已有別人的 assignee 就不做，停下來問。
- **卡住**：`gh issue comment <n> --body "卡在…"`，不關、assignee 留著。
- **Resolve**：`gh issue close <n> --comment "<commit、怎麼驗的>"`。PR 或 commit message 寫了 `Closes #<n>`、會進預設分支的，交給 merge 關。
