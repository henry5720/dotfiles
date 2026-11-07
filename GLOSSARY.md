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

**company agent**:
在 Slack 給公司同事共用的 coding agent，定義見 agent-company 的 [CONTEXT.md](https://github.com/henry5720/agent-company/blob/main/CONTEXT.md)。
_Avoid_: bot、workspace agent

## GUI 控制

local、remote 從操作者看：當下在操作 GUI 的那一方，agent 或人都算。同一個 GUI，agent 在 company-ec2 操作時是 remote，人坐到那台接手時對人是 local。

**操作者**:
當下在用某個服務的那一方，agent 或人。人要畫面，agent 要協定（CDP、MCP、ssh）。
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

**日常 profile**:
人平常用的那個 Chrome profile，帶著他的登入、passkey、裝置 SSO。agent 只能經插件或使用者同意接上，不能開 debug port。
_Avoid_: 個人瀏覽器、主 profile、本機 Chrome

**獨立 profile**:
另外開一個資料夾給 Chrome 用的 profile，跟日常 profile 分開，所以能開 debug port 給 agent 接。不管開在哪一台都叫這個名字。
_Avoid_: remote browser、遠端瀏覽器、MCP Chrome、專用 profile

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

**朗讀服務**:
已配置主機上把 agent 的回覆唸給個人電腦聽的服務，自己決定開或關。
_Avoid_: TTS 服務、語音服務、speaker

**跳過**:
只停掉正在唸的那一則回覆；排隊的照唸、朗讀服務照開。
_Avoid_: 停止、中斷（會跟「關掉朗讀服務」混在一起）

**取代**:
同一個 agent session 有新回覆要唸時，這個 session 正在唸、排隊中的舊回覆自動不唸了，只唸最新的；別的 session 的回覆不受影響。
_Avoid_: 覆蓋、打斷、跳過（跳過是人下指令停掉眼前那則）

**朗讀設定**:
每台已配置主機各自的語速、聲音、長度上限，改了從下一則回覆生效。
_Avoid_: 語音參數、TTS 設定

## 開給別人連

把一台機器上的某個 port 開給別人連時，先看連的人在不在你的 tailnet。做法見 `docs/remote-access/`。

**服務**:
跑在某一台、聽某個 port 的程式，例如瀏覽器的 debug port、網頁 shell、code-server、dev server。各自決定有沒有驗證。
_Avoid_: server（指機器時）、app（指要開出去的那個 port 時）

**連線**:
從連的那一方到服務中間怎麼走，只看雙方在不在同一台、在不在同一個 tailnet：同一台直接連，tailnet 內走 ssh 轉發或 `tailscale serve`，tailnet 外給公開網址。
_Avoid_: 遠端（「遠端」對人和 agent 指的方向不同）、隧道（指全部做法時）

**tailnet 內**:
連的人（或他的裝置）已經登入你的 tailnet。直接連 tailnet IP，用 `ssh -L`、`ssh -R` 或 `tailscale serve`，不開公網。
_Avoid_: 內網、區網、私有網路

**tailnet 外**:
連的人不在你的 tailnet，只能從公網連，要給他一個公開網址。開出去的那台加進你的 tailnet 用 Funnel，不加用 Cloudflare quick tunnel。
_Avoid_: 外網、訪客模式

**公開網址**:
Funnel 或 quick tunnel 開出來、任何人拿到都能連的 https 網址。擋陌生人的只剩 app 自己的驗證，用完要收掉。
_Avoid_: 對外入口（「入口」指從個人電腦操作已配置主機的方式）、public URL、外部連結

## 裝機

**基底**:
每台機器都裝、不能不勾的套件。Linux、macOS、Termux 只有 chezmoi 自己要用的 git、curl、jq、python3（Termux 另加 openssh）；Windows 主機是 winget 裝的 mise、pwsh 7、Windows Terminal，加上 mise 裝的 zoxide（PowerShell profile 的 `z`，Windows 的 shell 一定是 PowerShell）。
_Avoid_: 必裝、核心套件

**選裝工具**:
基底以外、要在選單上勾了才裝的工具，例如 zsh、tailscale、claude。取消勾選不會解除安裝。
_Avoid_: 外掛、optional packages、模組

**用途**:
`chezmoi init` 第一個問題的答案：完整、精簡或自訂（config 存英文代號 `full`、`minimal`、`custom`；init 時按字母 `f`、`m`、`c`）。決定選單預設勾哪些選裝工具；選完沒改勾選就只認用途，預設組合改了會跟著變。每台都問，Windows 主機也是。
_Avoid_: profile（跟 `ai-profile` 撞名）、角色、模式

**預設組合**:
一個用途預設勾好的選裝工具。完整是選單上全部，精簡是 zsh、starship、eza、fzf、bat、ripgrep、vim、fastfetch（只放 shell 體驗），自訂是空的。都扣掉這台環境「不建議」和「裝不了」的工具（例如 WSL 的 tailscale，WSL、ARM 的 headless-chrome、playwright-cli，Windows 的 zsh）；判斷有沒有改過勾選也用扣完的組合比。
_Avoid_: preset、套餐

**環境**:
機器本身的條件：哪種 OS、有沒有 root、是不是 WSL、什麼架構。靠偵測、不問；決定怎麼裝（apt、brew、mise、裝到家目錄），以及每個選裝工具在這台是可裝、不建議還是裝不了。選單每台都列全部工具，不建議、裝不了的標原因、預設不勾；不建議的勾了照裝，裝不了的勾了就略過，apply 最後列出原因。狀態與原因寫在 `home/.chezmoitemplates/tool-env`。跟用途分開。
_Avoid_: 用途（兩者是分開的）、機器類型；「不支援」「不列」（現在是列出來、標裝不了）

**Windows 主機**:
原生 Windows，由 Windows 原生 chezmoi 管；可能是 WSL 的外層，也可能沒有 WSL、本身就是開發機。跟 Linux 一樣有用途與選單，CLI 用 mise、app 用 winget 裝，安裝腳本只有 `.ps1`。有 WSL 時跟跑在它裡面的 WSL 是兩台機器，各有一份 clone、各自 `chezmoi init`。
_Avoid_: Windows 側、host

## 文件

**Runbook**:
裝一台新機器時從頭走到尾一次的步驟文件。只放裝機當下要做的事。
_Avoid_: 安裝手冊、setup guide（指裝完之後的操作時）

**日常操作**:
機器裝好之後才會做的調整，例如加減選裝工具、改憑證。不屬於 Runbook。文件標題是〈改設定與更新〉。
_Avoid_: 維運、day-2、之後的設定、裝完之後（README 那段是裝完之後的入口，不只這類文件）

**主題文件**:
針對單一工具或情境的文件，要用到那個工具或遇到那個情境時才打開。
_Avoid_: 說明書、guide

**背景與決策**:
說明為什麼這樣做的文件：ADR、選型比較、研究紀錄。不寫操作步驟。
_Avoid_: 設計文件、spec（指已定案的決定時）
