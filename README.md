# dotfiles

個人公開設定，主要給 **WSL2 的 Ubuntu 24.04 + 純 zsh** 使用；Termux/Android 與
Windows 內容是輔助資源。

## 這個 repo 怎麼分工

```text
home/       ──chezmoi 部署──> $HOME 設定
script/     ──安裝腳本──────> Ubuntu / Termux（依子目錄）
docs/       ──操作說明
wsl/        ──Windows 端 WSL 輔助
ai-agent/   ──手動使用的 agent persona

預設 source repo: ~/.local/share/chezmoi
```

chezmoi 是管理家目錄設定檔的工具，會依命名與 template 規則部署 `home/`，不一定原樣複製。完整用法與
檔名前綴請看 [chezmoi 官方文件](https://www.chezmoi.io/) 及
[target types](https://www.chezmoi.io/reference/target-types/)。

## 使用前

- fork 或使用前，先檢查 provider、agent rules、SSH、Windows/Termux 機器設定。
- 已有設定的機器先備份；不要未檢查就部署別人的個人 dotfiles。
- 憑證不進 git；`chezmoi init` 只在尚未有值時提示，值放在
  `~/.config/chezmoi/chezmoi.toml`。不信任或共用機器不要填真實憑證。

## 新機器快速開始

以下假設 source repo 在 `~/.local/share/chezmoi`；使用 fork 時替換 `init` 的帳號或
URL。先看 diff，確認不會覆蓋要保留的本機內容，再 apply；完整人工停點與後續設定見
[新機器設定 Runbook](docs/new-machine-setup.md)。

```bash
sudo snap install chezmoi --classic
chezmoi init henry5720       # fork 請換成自己的帳號或 repo URL
chezmoi diff                 # 先檢查，確認後才繼續
chezmoi apply

cd ~/.local/share/chezmoi
bash script/ubuntu/setup.sh  # setup → install-base → install-tools
```

`setup.sh` 是 Ubuntu 安裝入口；不要把整段命令盲目貼上後跳過 diff。缺少必要憑證的
服務不能視為可用；AI 解析的額外依賴與 model 準備方式見 Runbook。

AI CLI 的 work/personal 入口與個人設定見 [AI profile routing](docs/ai-profile-routing.md)。

## 日常修改

```text
修改 home/ → chezmoi diff → 確認 → chezmoi apply → chezmoi verify
```

```bash
cd ~/.local/share/chezmoi
# 修改 home/ 裡的檔案
chezmoi diff
chezmoi apply
chezmoi verify
```

不要直接改已部署的 `$HOME` 檔案；本機有不認得的變更時，先備份或處理衝突。

## 文件索引

- [新機器設定](docs/new-machine-setup.md)：完整的 WSL、AI agent 與各 repo runbook。
- [AI agent setup](docs/ai-agent-setup.md)：規則、skill、MCP、plugin 與 codegraph。
- [AI profile routing](docs/ai-profile-routing.md)：公司／個人 CLI 的切換與登入前置。
- [tmux workflow](docs/tmux-workflow.md)：tmux 狀態列、session 與 agent 自動化。
- [Chrome DevTools MCP](docs/chrome-devtools-mcp.md)：瀏覽器 MCP 與排錯。
- [code-server remote](docs/code-server-remote.md)：從其他裝置連線 code-server。
- [no-sudo setup](docs/no-sudo-setup.md)：沒有 sudo 時的限制與替代做法。
- [Herdr notifications](docs/herdr-notifications.md)：WSL2 通知音與 PulseAudio 排錯。

repo 修改規範與驗證方式見 [`CLAUDE.md`](CLAUDE.md)。`docs/superpowers/` 是歷史
spec/plan，不是現行文件。
