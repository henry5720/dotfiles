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
  E --> F["merge 進 main<br/>GitHub 自動關 issue"]
  D -- "沒有，直接 commit 進 main" --> G["留言：commit、怎麼驗的<br/>手動關 issue"]
```

## spec（底下有 sub-issue）

```mermaid
flowchart TD
  S["spec"] --> BR["開 spec 分支<br/>PR 只寫 Closes spec，不列 sub-issue"]
  BR --> Q{"sub-issue 互相獨立、要平行做？"}
  Q -- "否（預設）：一個 worktree 順序做" --> ONE["做一張 sub-issue<br/>commit 進 spec 分支"]
  ONE --> C1["留言：commit、怎麼驗的<br/>手動關 sub-issue"]
  C1 --> N1{"還有 sub-issue？"}
  N1 -- "有（被它擋的那張解鎖了）" --> ONE
  Q -- "是：多個 worktree" --> MANY["每張 sub-issue 從 spec 分支切 worktree<br/>做完合回 spec 分支（整合分支）"]
  MANY --> C2["合進去時留言<br/>手動關 sub-issue"]
  C2 --> N2{"還有 sub-issue？"}
  N2 -- "有" --> MANY
  N1 -- "沒有" --> RV["code review、修完"]
  N2 -- "沒有" --> RV
  RV --> M["merge 進 main<br/>GitHub 自動關 spec"]
```

sub-issue 不列進 PR 的 `Closes`：`Closes` 只在 PR 進 main 時生效，列了就要等整條分支進 main 才關，
被它擋的 sub-issue 會一直顯示 blocked。spec 要等 merge 才關，所以 **spec 開著＝這份還沒進 main**。
