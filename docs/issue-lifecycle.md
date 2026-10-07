# Issue 生命週期

給人看的：一張 issue 在 GitHub 上會經過哪些狀態。agent 照的規則在 [`home/dot_claude/CLAUDE.md`](../home/dot_claude/CLAUDE.md) 的「Issue 生命週期」（部署成 `~/.claude/CLAUDE.md`），改規則時兩份一起改。

怎麼寫 code（worktree、分支、PR）不歸這裡管，看用的 skill 或 agent-runner。

| 狀態 | GitHub 上看起來 | 怎麼進到這個狀態 |
| --- | --- | --- |
| 待接 | open、沒有 assignee，通常貼 `ready-for-agent` | 開 issue；`/to-tickets` 拆出來的預設貼 `ready-for-agent` |
| 進行中 | open、assign 給某人 | 確認沒有開著的 blocker、沒有別人接，assign 自己 |
| 卡住 | open、assign 還在，最新留言寫卡在哪 | 留言，不關 |
| 完成 | closed | 留言寫 commit 和怎麼驗的，再關；或 PR／commit message 寫 `Closes #N`，進預設分支時 GitHub 自動關 |

spec 和 agent-runner 做的 sub-issue 也照這張表。
