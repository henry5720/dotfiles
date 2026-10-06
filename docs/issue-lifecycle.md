# Issue 生命週期

給人看的圖。agent 照的是 [`home/dot_claude/CLAUDE.md`](../home/dot_claude/CLAUDE.md) 的「Issue 生命週期」
（部署成 `~/.claude/CLAUDE.md`）。兩邊是同一套規則，改規則時兩邊一起改。map 的流程由上游 `wayfinder` 決定，不在這裡。

## 一般 issue

```mermaid
flowchart TD
  A["issue 開著<br/>沒有開著的 blocker、沒有別人的 assignee"] --> B["Assign 自己"]
  B --> C["開 worktree、commit"]
  C --> D{"有開 PR？"}
  D -- "有（預設）" --> E["PR 寫 Closes #N<br/>--assignee @me"]
  E --> F["merge 進預設分支<br/>GitHub 自動關 issue"]
  D -- "沒有 PR，或 PR 不是進預設分支" --> G["留言：commit、怎麼驗的<br/>關 issue"]
```

## spec（底下有 sub-issue）

照上游 `/implement-spec`。

```mermaid
flowchart TD
  S["spec"] --> BR["開整合分支"]
  BR --> W["每張可做的 sub-issue<br/>各開 worktree 和分支"]
  W --> IM["做完後先合入<br/>整合分支最新 commit"]
  IM --> MG["merger 合回<br/>整合分支"]
  MG --> F{"第一次合回？"}
  F -- "是" --> DR["開 draft PR<br/>Closes spec 和所有 sub-issue"]
  F -- "否" --> N{"還有 sub-issue？"}
  DR --> N
  N -- "有（擋它的已合回）" --> W
  N -- "沒有" --> RV["跑 code-review<br/>修完"]
  RV --> M["draft 轉 ready、merge<br/>GitHub 關 spec 和所有 sub-issue"]
```
