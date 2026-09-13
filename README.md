# dotfiles

這是個人公開 dotfiles repo,主要支援 **WSL2 上的 Ubuntu 24.04** 與純 zsh
(不使用 Oh My Zsh),用來建立日常的 shell、終端與 coding-agent 工作環境。
`Termux/Android` 與 `Windows` 內容是輔助資源,不等同於主要支援平台。

## 管理什麼

- `home/`: chezmoi source,部署家目錄設定與 templates。
- `script/ubuntu/`: Ubuntu 基底與工具安裝腳本。
- AI agent 與 OpenCode config,包含 MCP、plugin 與 agent preset。
- AI CLI 可用 `codex-work`／`codex-personal` 與 `opencode-work`／`opencode-personal` 切換。
- Git、tmux、Neovim，以及 WSL／Termux／Windows 的輔助資源。

## 新機器快速開始

### 交給 coding agent

將這段貼給已可用的 Claude Code、OpenCode、Cursor 或其他 coding agent：

```text
請讀取並依序執行這份新機器設定 Runbook：
https://raw.githubusercontent.com/henry5720/dotfiles/main/docs/new-machine-setup.md

只執行文件列出的自動化步驟並逐步驗證；遇到 sudo、秘密、OAuth、SSH key 或可選項目時先停下來問我。
不要讀取、儲存、列印或提交任何憑證。
```

這條路需要你已經有可用的 coding agent；它不能 bootstrap 第一個 agent。

### 手動設定

先準備 WSL2 Ubuntu 24.04 與可用的 `sudo`;已有設定的機器請先自行備份。先預覽
chezmoi diff,確認會改哪些檔案,再套用:

```bash
sudo snap install chezmoi --classic
chezmoi init henry5720
chezmoi diff
chezmoi apply
cd ~/.local/share/chezmoi
bash script/ubuntu/setup.sh
```

`setup.sh` 是推薦的一次性入口,會互動安裝 Ubuntu 基底與可選工具。完整人工步驟、
秘密輸入、AI agent／OmO、SSH、各 repo setup 與驗證,請照
[`docs/new-machine-setup.md`](docs/new-machine-setup.md),不要在 README 重複流程。
如果 `chezmoi diff` 出現不認得的目標或內容,先停止並處理備份／衝突,不要直接套用。
首次部署完成後,後續設定修改也一律先在 source repo 確認 diff 再 apply。

## 文件

依使用情境閱讀:

- [新機器設定](docs/new-machine-setup.md)：從 WSL 到 AI agent 與各 repo 的完整 runbook。
- [AI agent setup](docs/ai-agent-setup.md)：規則、skill、MCP、plugin、OpenCode 與 codegraph。
- [AI profile routing](docs/ai-profile-routing.md)：公司／個人 CLI 的 roots 與登入前置作業。
- [tmux workflow](docs/tmux-workflow.md)：tmux 狀態列、session 與 agent 自動化。
- [Chrome DevTools MCP](docs/chrome-devtools-mcp.md)：瀏覽器 MCP、`chrome-mcp` 與排錯。
- [code-server remote](docs/code-server-remote.md)：從其他裝置連線 code-server。
- [no-sudo setup](docs/no-sudo-setup.md)：沒有 sudo 時的限制與替代做法。
- [Herdr notifications](docs/herdr-notifications.md)：WSL2 通知音與 PulseAudio 排錯。

`docs/superpowers/` 是歷史 spec／plan,不是目前環境的主要現況文件。

## 安全與 fork

這是公開 repo。OAuth、API key、password、SSH private key 與其他憑證都不進 git;
chezmoi 的秘密放在 repo 外,SSH private key 也必須自行配置。fork 時請換成自己的
SSH 設定、OpenCode provider、agent rules,以及 Windows／Termux 的機器特定值。
秘密與新機器邊界見 [新機器設定](docs/new-machine-setup.md),repo 修改規範見
[`CLAUDE.md`](CLAUDE.md)。

## 修改這個 repo

`home/` 是 chezmoi source;修改規則與驗證方式看 [`CLAUDE.md`](CLAUDE.md),不要直接改
已部署的 `$HOME` 檔案。
