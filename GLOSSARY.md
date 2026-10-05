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

**整合分支**:
一份 spec 的所有 sub-issue 先合進去、全部完成後才一次進預設分支的分支。順序做時 sub-issue 直接 commit 在上面；平行做時各自另開 worktree，做完再合回來。
_Avoid_: feature branch、母分支、spec 分支
