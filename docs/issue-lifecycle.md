# Issue 生命週期

給人看的。agent 照的規則在 [`home/dot_claude/CLAUDE.md`](../home/dot_claude/CLAUDE.md) 的「Issue 生命週期」（部署成 `~/.claude/CLAUDE.md`），改規則時兩份一起改。

接了、卡住、做完都要在 GitHub 上看得到，人和 agent 都一樣。怎麼寫 code（worktree、分支、PR）不歸這裡管。

| 狀態 | GitHub 上看起來 | 怎麼進到這個狀態 |
| --- | --- | --- |
| 待接 | open、沒有 assignee | 開 issue |
| 進行中 | open、assign 給某人 | 確認沒有開著的 blocker、沒有別人接，assign 自己 |
| 卡住 | open、沒有 assignee | 留言寫卡在哪、unassign，回到待接 |
| 完成 | closed | 留言寫 commit 和怎麼驗的，再關 |

PR 寫了 `Closes #N` 的，PR 就是完成的紀錄，merge 時 GitHub 自動關，不用另外留言。

spec 和 agent-runner 做的 sub-issue 也照這張表；它們怎麼開分支、怎麼合，看上游 `/implement-spec` 和 agent-runner 的 [README](https://github.com/henry5720/agent-runner)。
