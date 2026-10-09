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
做一份 spec 時，sub-issue 先合進去、全部完成後才一次進預設分支的分支。`/implement-spec` 和 runner 都走這條；用 `/implement` 一張一張做的不走。
_Avoid_: feature branch、母分支、spec 分支

## Runner

**Runner**:
agent-runner：人不在時自己接 issue、在 sandbox 裡做、開 draft PR 的程式。只接帶 agent-runner label 的 issue，一次一張，不管 issue 是怎麼來的。
_Avoid_: bot、機器人、AFK agent

**ready-for-agent**:
issue 寫清楚了，agent 不必問人就能做。只是 triage 狀態，不代表誰會去接。
_Avoid_: 可以接了、交給 runner

**agent-runner label**:
人決定把一張 issue 交給 runner 時貼的 label；runner 只接帶這個 label 的 issue。spec 本身不貼，它的 sub-issue 要交給 runner 就一張一張貼。
_Avoid_: 用 ready-for-agent 表示交給 runner

## Agent 分工

**L1**:
跨 provider 派工的那一層：人透過 Herdr 決定開哪個 agent、叫它做什麼。agent 用 Herdr skill 叫別的 agent，只要是人當下指示的，仍然算 L1 的決定。
_Avoid_: supervisor、orchestrator agent

**L2**:
單一 CLI 裡派 subagent 的那一層，用 Claude Code、Codex 的原生功能。
_Avoid_: worker、team runtime

**Supervisor**:
自己拆任務、決定派給哪個 provider、自己驗收和重試的 agent，也就是由 agent 接手 L1。目前不採用。
_Avoid_: 把 L1 也叫 orchestrator

**工作流程 skill**:
規定一件工作照什麼步驟做的一組 skill，例如 matt-skills、Superpowers。可以替換，與 L1、L2 無關，也不決定用哪個模型。
_Avoid_: harness、框架

**原生角色**:
寫在 `~/.claude/agents/`、`~/.codex/agents/` 的 custom agent，定義某類工作用哪個模型、多少 reasoning effort、哪些工具。
_Avoid_: role（單獨使用時）、persona
