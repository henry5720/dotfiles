# Windows 上的 skill

Windows 主機勾了 agent-config 後，skillshare 把 agent-config 的 skill 全部同步過去（見
[Windows 主機〈agent-config（skillshare）〉](windows.md#agent-configskillshare)），但不是每支都能在 Windows 跑。
這頁列出哪些不能用、卡在哪，免得用到一半才發現。只記錄現況，修 skill 在 agent-config 的 issue 追。

盤點的前提：

- 對象是 agent-config `6579bb9` 的 49 支 skill（2026-11-19），只讀 SKILL.md 與附帶的腳本，沒有在 Windows 實機逐支跑過
- agent 是 Windows 上的 Claude Code。agent-config 會一併裝 Git for Windows，Claude Code 有它時 Bash tool 走 Git Bash
  （[官方文件](https://code.claude.com/docs/en/setup#install-on-native-windows)），所以 `bash` 腳本、`grep`、`find`、`~` 路徑都還能用；
  Git Bash 沒有的是 `python3`、`jq`、`uv`、`ss`、`/proc` 裡的行程資訊、`sudo`
- Codex、OpenCode 跑指令的 shell 不一定是 Git Bash，上面的前提對它們不一定成立，沒有另外逐支看

## 不可用

| skill | 卡在哪 | agent-config issue |
|---|---|---|
| slack-list | 腳本檔頭 `import fcntl`，Windows 的 Python 沒有這個模組，連唯讀指令都跑不了；而且要 `python3` | [#94](https://github.com/henry5720/agent-config/issues/94) |
| expose-port | 兩支腳本是 python3，用 `pgrep`、`sudo`、`SIGHUP`（Windows 沒有）。開公網網址改到 WSL 或 Linux 那台做 | [#95](https://github.com/henry5720/agent-config/issues/95) |

## 部分可用

| skill | 能用的 | 不能用的 | agent-config issue |
|---|---|---|---|
| windows-mcp | 〈使用者在那台 PowerShell 貼〉那段 | `scripts/` 全部要在 WSL 跑（`powershell.exe`、`wslpath`）；agent 就在那台 Windows 時自己跑 PowerShell 的路 SKILL.md 沒寫 | [#95](https://github.com/henry5720/agent-config/issues/95) |
| browser-access | headless（`playwright-cli open`）、使用者的獨立 profile | 接插件的 `personal-chrome-attach`（要 `python3`、`/proc`、`mkfifo`）；查 port 的 `ss -ltnp` 換 `Get-NetTCPConnection` | [#96](https://github.com/henry5720/agent-config/issues/96) |
| verify-in-browser | 用 `playwright-cli` 逐條驗、存證據 | 產報告的 `uv run scripts/render-report.py`（要 uv：勾了 agent-config、`uv` 或 windows-mcp 就由 mise 一併裝）；證據資料夾 `chmod 700` 在 NTFS 不生效 | [#96](https://github.com/henry5720/agent-config/issues/96) |
| pr-review-and-verify | 審 PR、`gh` 發 comment | 瀏覽器結果的報告靠 verify-in-browser 的 `render-report.py`，同上 | [#96](https://github.com/henry5720/agent-config/issues/96) |
| show-me | 寫 HTML、Mermaid | 開 HTML 寫的是 macOS 的 `open`，Windows 叫 agent 改用 `start` | 上游 skill，不開 |
| agent-reach | SKILL.md 的路由 | 要自己裝 agent-reach CLI（dotfiles 在哪個 OS 都不裝），在 Windows 沒驗過 | 上游 skill，不開 |

## 可用

剩下 38 支在 Windows 跟 Linux 一樣用。有前提的：

| 要先有 | skill |
|---|---|
| Git Bash（勾 agent-config 就有） | daily-worklog（`find "$HOME"`）、wizard、diagnosing-bugs 的 HITL 腳本（都是 bash） |
| mise 裝的工具（完整或自己勾） | playwright-cli（`playwright-cli`）、compress-video（`ffmpeg`；SKILL.md「沒有 ffmpeg」只寫 apt、brew）、herdr、herdr-worktree（`herdr`）、find-skills（`node` 的 `npx`） |
| 其他 | skillshare（skillshare 本體已裝；附的 `run.sh` 用不到）、pms-tracking（pms MCP） |

只靠 `git`、`gh` 或純文字的：archive-branches、ask-matt、caveman、code-review、codebase-design、
domain-modeling、grill-me、grill-with-docs、grilling、handoff、humanizer-zh、implement、implement-spec、
improve-codebase-architecture（開 HTML 已寫 Windows 的 `start`）、pr、prototype、research、retro、
setup-matt-pocock-skills、tdd、teach、to-questionnaire、to-spec、to-tickets、triage、wait-what、wayfinder、writing-for-agents。

agent-config 加了新 skill 或上面的 issue 修好後，更新這頁。
