# dotfiles

個人 dotfiles，也放跨 repo 共用的 agent 工作流程規則（全域 CLAUDE.md 由這裡部署）。這份詞彙表定的是寫規則、文件、issue 時用的詞。

## Issue 流程

**Issue**:
GitHub 上的一則 issue，是規劃與實作工作的單位。
_Avoid_: 票、單、任務、工單

**Map**:
帶 `wayfinder:map` label 的 issue，記錄一件還沒想清楚的大事要往哪走；底下的 sub-issue 都是待做的決定。
_Avoid_: 母票、地圖

**Spec**:
`/to-spec` 產出的 issue，描述一個已經決定好、要實作的功能；底下的 sub-issue 是實作步驟。
_Avoid_: 母票、需求單、PRD

**Sub-issue**:
用 GitHub 原生 sub-issue 掛在 map 或 spec 底下的 issue。
_Avoid_: 子票、子單、子任務

**Assign**:
把自己設成一個 issue 的 assignee，表示有人在做。放棄就是 unassign。上游 wayfinder 說的 claim 就是這個動作。
_Avoid_: 接、認領、claim、貼 agent-in-progress

**整合分支**:
用 `/implement-spec` 一次做完一份 spec 時，所有 sub-issue 先合進去、全部完成後才一次進預設分支的分支。sub-issue 一張一張做的（`/implement`、runner）不走整合分支，各自開 PR。順序做時 sub-issue 直接 commit 在上面；平行做時各自另開 worktree，做完再合回來。
_Avoid_: feature branch、母分支、spec 分支

## Runner

**Runner**:
agent-runner：人不在時自己接 issue、在 sandbox 裡做、開 draft PR 的程式。一次接一張 issue；接到 spec 的 sub-issue 時會把 spec 一起讀進來當背景，不跑 `/implement-spec`。
_Avoid_: bot、機器人、AFK agent

**ready-for-agent**:
issue 寫清楚了，agent 不必問人就能做。只是 triage 狀態，不代表誰會去接。
_Avoid_: 可以接了、交給 runner

**agent-runner label**:
人決定把一張 issue 交給 runner 時貼的 label；runner 只接帶這個 label 的 issue。spec 本身不貼，它的 sub-issue 要交給 runner 就一張一張貼。
_Avoid_: 用 ready-for-agent 表示交給 runner
