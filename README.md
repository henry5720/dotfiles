# dotfiles

![裝完之後的 terminal：p10k prompt、語法上色與 autosuggestion、eza、fastfetch](docs/demo/main.gif)

個人公開設定，用 [chezmoi](https://www.chezmoi.io/) 管理，以 **Ubuntu + 純 zsh** 為主；日常用在 WSL2，
也用在雲端主機與 Android 平板（原生 Termux、Termux 裡的 proot Ubuntu）。

## 支援哪些環境

| 機器 | 怎麼判斷 | chezmoi 會做什麼 |
|---|---|---|
| WSL2 Ubuntu | kernel 版本含 `microsoft` | 基底套件、zsh、選裝工具選單（不列 headless Chrome、playwright-cli） |
| 雲端主機、proot Ubuntu | 其他 Linux | 同上；amd64 才列 headless Chrome、playwright-cli |
| 原生 Termux | `chezmoi.os` 是 `android` | 基底套件、zsh、終端機字型、`authorized_keys`；**沒有**選單（開發環境放 proot Ubuntu） |

機器種類自動判斷，不用回答。Ubuntu 機器要能 `sudo`。

## 新機器

| 步驟 | 要不要做 | 怎麼做 |
|---|---|---|
| 更新系統 | 可選，跳過也裝得起來 | Ubuntu：`sudo apt update && sudo apt upgrade -y` |
| 放 SSH key | 可選，要 push 或連其他機器才需要；裝完再放也行 | 見[新機器設定 2.2](docs/new-machine-setup.md#22可選放-ssh-key) |
| 裝 chezmoi 與 dotfiles | 必做 | 下面兩行挑一行 |

```bash
# Ubuntu（WSL、雲端主機、proot Ubuntu），在家目錄跑
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply henry5720

# 原生 Termux
pkg upgrade && pkg install chezmoi && chezmoi init --apply henry5720
```

![打上面 Ubuntu 那行、在選裝工具選單取消幾項、裝完](docs/demo/menu.gif)

clone 走 HTTPS，不用 key；放了 key 之後 push 自動走 SSH。init 會問什麼、各種機器的前置、
裝完之後的 AI 工具設定、之後怎麼加減選裝工具，見[新機器設定](docs/new-machine-setup.md)。

## repo 結構

```text
.chezmoiroot          內容是 home：chezmoi 只看 home/，其餘它看不到
home/                 → 部署到 ~（chezmoi apply）
├── .chezmoi.toml.tmpl      → ~/.config/chezmoi/chezmoi.toml：憑證、Git 身分、選裝工具（init 時問）
├── .chezmoidata/           不部署：基底套件與走 apt 的選裝工具清單
├── .chezmoiexternal.toml.tmpl → ~/.config/zsh/*、Termux 的 ~/.termux/font.ttf（apply 時下載）
├── .chezmoiscripts/        不部署，apply 時執行：裝套件、裝選裝工具、換預設 shell
├── dot_zshrc、dot_p10k.zsh、dot_gitconfig.tmpl → ~/.zshrc、~/.p10k.zsh、~/.gitconfig
├── dot_config/             → ~/.config/：nvim、git hooks、zsh、fontconfig、code-server、opencode、skillshare
├── dot_claude/、dot_codex/ → ~/.claude/、~/.codex/：設定；全域規則只放 symlink，內容在 agent-config
├── dot_local/bin/          → ~/.local/bin/：自己的指令（ai-profile、chrome-mcp、share-shell…）
├── dot_local/share/fonts/  → ~/.local/share/fonts/：Termux 字型的 symlink（只在原生 Termux）
└── private_dot_ssh/        → ~/.ssh/（700）：SSH config
script/               不部署，自己手動跑
├── ubuntu/                 會改系統的：Docker（會移除衝突套件）、swap（改 /etc/fstab）
├── termux/                 平板桌面、proot Ubuntu 的使用者
├── tests/                  容器 e2e 與單元測試
└── demo/                   重錄 README 的 GIF
docs/                 說明（見下面的文件索引）
wsl/                  Windows 側參考檔，之後由 Windows 上的 chezmoi 管
```

- 檔名前綴（`dot_`、`private_`、`symlink_`、`.tmpl`…）決定部署結果，規則見
  [target types](https://www.chezmoi.io/reference/target-types/)；逐檔清單跑 `chezmoi managed`。
- skills、MCP 和全域規則（`CLAUDE.md`／`AGENTS.md`、commit 指引）的內容在 agent-config，這裡只放
  規則的 symlink（[ADR 0002](docs/adr/0002-agent-instructions-in-agent-config-placed-by-chezmoi-symlinks.md)）；見 agent-config 的
  [skill](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md)、[MCP](https://github.com/henry5720/agent-config/blob/main/docs/mcp.md)。
- `wsl/` 怎麼交給 Windows 上的 chezmoi，見
  [Wayfinder: Windows 側交給 chezmoi（PowerShell、WSL、Windows Terminal）](https://github.com/henry5720/dotfiles/issues/167)。
- 日常怎麼改、套用、同步，照 chezmoi 官方的 [daily operations](https://www.chezmoi.io/user-guide/daily-operations/)。

## fork 前要改什麼

- [ ] 安裝指令與 ssh config（`home/private_dot_ssh/private_config`）寫死 `henry5720` 帳號和 `~/.ssh/henry5720` 這把 key
- [ ] agent-config 的 remote（`home/.chezmoiscripts/run_onchange_after_install-agent-config.sh.tmpl`）
- [ ] AI provider、model 與 agent 規則（`home/dot_codex/`、`home/dot_config/opencode/`、agent-config）
- [ ] ssh config 裡的 Tailscale 主機與平板
- [ ] 已有設定的機器先備份；不要未檢查就部署別人的個人 dotfiles
- [ ] 憑證不進 git，`chezmoi init` 時才問、存在 `~/.config/chezmoi/chezmoi.toml`；不信任或共用的機器不要填真實憑證

## 文件索引

| 文件 | 什麼時候看 |
|---|---|
| [新機器設定](docs/new-machine-setup.md) | 裝新機器、放 SSH key、平板與 proot、裝完之後的 AI 工具、之後加減選裝工具 |
| [AI agent setup](docs/ai-agent-setup.md) | 改規則、plugin、codegraph、playwright-cli、opencode |
| [AI profile routing](docs/ai-profile-routing.md) | 切換公司／個人的 CLI、登入前置 |
| [chrome-mcp](https://github.com/henry5720/agent-config/blob/main/docs/skills/chrome-mcp.md)（在 agent-config） | 設定瀏覽器 MCP、轉發到 EC2、排錯 |
| [瀏覽器偵錯 MCP 對照](docs/browser-mcp-comparison.md) | 選 Playwright 還是 chrome-devtools-mcp |
| [code-server remote](docs/code-server-remote.md) | 從其他裝置連 code-server |
| [開給訪客看](docs/share-with-guest.md) | 把 shell 或 dev server 臨時開給沒有 tailscale 的人 |
| [Herdr notifications](docs/herdr-notifications.md) | WSL2 通知音、PulseAudio 排錯 |
| [WSL 常用指令](wsl/command.md) | Windows 終端機字型、port 轉發 |
| [Issue 生命週期](docs/issue-lifecycle.md) | 看 issue 從待接到完成在 GitHub 上留什麼 |
| [`CLAUDE.md`](CLAUDE.md) | 改這個 repo：檔名前綴、秘密、驗證方式（含容器 e2e） |

`docs/superpowers/`、`docs/research/` 是當時的 spec、plan 與研究紀錄，不是現行文件。
