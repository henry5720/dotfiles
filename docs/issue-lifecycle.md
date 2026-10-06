# Issue 生命週期

給人看的圖。agent 照的規則不在這裡，每張圖對照的來源不同，改規則時跟對照的那份一起改：

| 圖 | 對照的規則 |
| --- | --- |
| 一般 issue | [`home/dot_claude/CLAUDE.md`](../home/dot_claude/CLAUDE.md) 的「Issue 生命週期」（部署成 `~/.claude/CLAUDE.md`） |
| spec | 上游 `/implement-spec` skill |
| runner 做 spec 的 sub-issue | agent-runner 的 code 與 README 的〈[spec 的 sub-issue 走整合分支](https://github.com/henry5720/agent-runner#spec-的-sub-issue-走整合分支)〉 |

map 的流程由上游 `wayfinder` 決定，不在這裡。

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

## runner 做 spec 的 sub-issue

sub-issue 一張一張貼 `agent-runner` label，runner 一次做一張，同一份 spec 一輪只做一張。開始做時 runner 把 sub-issue assign 給操作者，分支叫 `agent/<sub-issue 編號>`。

```mermaid
flowchart TD
  A["sub-issue<br/>貼 agent-runner"] --> B["從整合分支開分支<br/>sandbox 裡做"]
  B --> R{"結果"}
  R -- "全過" --> M{"合進整合分支"}
  M -- "沒衝突，或 merge run 解掉" --> C["更新整合分支 PR<br/>關 sub-issue"]
  M -- "merge run 解不掉" --> W["[WIP] PR<br/>sub-issue 不關"]
  R -- "檢查沒過" --> W
  R -- "needs-info、crash" --> N["留言<br/>不碰整合分支"]
```

- 整合分支是 `agent/<spec 編號>`，第一張全過或 `[WIP]` 時才從 runner 設定的 `baseBranch` 建；建之前 sub-issue 的分支也從 `baseBranch` 開。
- `[WIP]` PR 是 `agent/<sub-issue 編號>` 進整合分支，人修好、merge 後手動關 sub-issue。
- 整合分支的 draft PR 第一張全過時開、之後每張更新，只寫 `Closes #<spec>`；sub-issue 合進去就由 runner 留言關，不等 PR merge。draft 轉 ready、merge 由人決定。
- merge run 是合併有衝突時再跑一次 sandbox，讓 agent 用 `resolving-merge-conflicts` 解。解完 push 被拒（期間有人往整合分支 push）也走 `[WIP]`；merge run timeout、crash 照 crash。
