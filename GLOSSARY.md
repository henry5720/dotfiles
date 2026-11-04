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

**內建 subagent**:
CLI 自帶、不用寫設定就能派的 subagent，例如 Claude 的 Explore、Plan、general-purpose，Codex 的 default、explorer、worker。自己寫一個同名的原生角色會蓋掉它。
_Avoid_: 預設 subagent（Codex 有個內建 subagent 就叫 `default`）

## GUI 控制

local、remote 從操作者看：當下在操作 GUI 的那一方，agent 或人都算。同一個 GUI，agent 在 company-ec2 操作時是 remote，人坐到那台接手時對人是 local。

**操作者**:
當下在操作 GUI 的那一方，agent 或人。
_Avoid_: 使用者（指 agent 時）

**Local GUI**:
GUI app 跑在操作者所在的那台機器上。
_Avoid_: 實體機、虛擬螢幕（指放的位置時）

**Remote GUI**:
GUI app 跑在另一台有桌面的機器上，操作者經網路控制它。只講 GUI 在哪一台，不講走 tailnet 還是 Funnel。
_Avoid_: 目標機器、桌機、實體機、remote（指經 Funnel 開到公網時）

**Headless 瀏覽器**:
跑在操作者那台、沒有畫面的瀏覽器。沒有畫面，所以不算 local GUI。
_Avoid_: a1、local 瀏覽器

## 操作已配置主機

不分 local、remote：坐在前面或從別台連過去，操作方式一樣，只差第一步要不要先連過去。

**已配置主機**:
裝好這些工具、你要用它的那台。可以就是你的個人電腦，也可以是雲端主機；不管上面有沒有跑 agent。
_Avoid_: 工作機、開發機、目標機器、agent 機、遠端機器、server、主機（單獨使用時）

**個人電腦**:
人坐在前面、用來操作已配置主機的那台。可以就是已配置主機本身。
_Avoid_: 自己電腦、本機、client、local（指這個角色時）

**入口**:
從個人電腦操作已配置主機的方式：terminal ssh、VS Code Remote-SSH、瀏覽器開 code-server、別人開給你的 share-shell 網址。
_Avoid_: 連線方式（只指 ssh 時）、登入方式

## 裝機

**基底**:
每台 Linux、macOS、Termux 機器都裝、不能不勾的套件，只有 chezmoi 自己要用的 git、curl、jq、python3（Termux 另加 openssh）。Windows 主機沒有基底。
_Avoid_: 必裝、核心套件

**選裝工具**:
基底以外、要在選單上勾了才裝的工具，例如 zsh、tailscale、claude。取消勾選不會解除安裝。
_Avoid_: 外掛、optional packages、模組

**用途**:
`chezmoi init` 第一個問題的答案：完整、精簡或自訂（config 存英文代號 `full`、`minimal`、`custom`；init 時按字母 `f`、`m`、`c`）。決定選單預設勾哪些選裝工具；選完沒改勾選就只認用途，預設組合改了會跟著變。Windows 主機沒有用途，也沒有選裝工具。
_Avoid_: profile（跟 `ai-profile` 撞名）、角色、模式

**預設組合**:
一個用途預設勾好的選裝工具。完整是選單上全部，精簡是 zsh、starship、eza、fzf、bat、ripgrep、vim、tailscale、btop，自訂是空的。這台不支援的項目（WSL、ARM 的 headless-chrome、playwright-cli）不算在內。
_Avoid_: preset、套餐

**環境**:
機器本身的條件：哪種 OS、有沒有 root、是不是 WSL、什麼架構。靠偵測、不問；決定怎麼裝（apt、brew、mise、裝到家目錄），以及哪些選裝工具在這台不列。跟用途分開。
_Avoid_: 用途（兩者是分開的）、機器類型

**Windows 主機**:
WSL 外面那層 Windows，由 Windows 原生 chezmoi 管，只管 shell 體驗（PowerShell、Windows Terminal、字型、`.wslconfig`）。跟跑在它裡面的 WSL 是兩台機器，各有一份 clone、各自 `chezmoi init`。
_Avoid_: Windows 側、host

## 文件

**Runbook**:
裝一台新機器時從頭走到尾一次的步驟文件。只放裝機當下要做的事。
_Avoid_: 安裝手冊、setup guide（指裝完之後的操作時）

**日常操作**:
機器裝好之後才會做的調整，例如加減選裝工具、改憑證。不屬於 Runbook。
_Avoid_: 維運、day-2、之後的設定

**主題文件**:
針對單一工具或情境的文件，要用到那個工具或遇到那個情境時才打開。
_Avoid_: 說明書、guide

**背景與決策**:
說明為什麼這樣做的文件：ADR、選型比較、研究紀錄。不寫操作步驟。
_Avoid_: 設計文件、spec（指已定案的決定時）
