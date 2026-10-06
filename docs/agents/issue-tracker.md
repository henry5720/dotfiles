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
