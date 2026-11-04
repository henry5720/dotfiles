# mise

Linux 上 eza、fzf 這類 CLI 工具由 [mise](https://mise.jdx.dev/) 裝到家目錄，有沒有 root 都一樣。
Termux 走 `pkg`、macOS 走 `brew`，不用這份。

## 哪些工具是 mise 裝的

```text
有勾才裝，清單看 home/.chezmoidata/packages.yaml 的 miseTools
├─ 每台 Linux：eza、fzf、bat、ripgrep、starship、btop、fastfetch、ttyd（單一執行檔）
└─ 只有 apt 用不了時（沒有 root、非 Debian 系）：vim、ffmpeg、poppler、gh、code-server
   有 root 時這幾個走 apt 或官方 .deb
```

沒有 root 時還自動處理什麼，見[沒有 root 的機器](no-root-machine.md)。

為什麼這樣分見 #231（決定）、#233（實作）。

- 清單：`~/.config/mise/conf.d/dotfiles.toml`，chezmoi 照勾選產生，別直接改
- 執行檔：`~/.local/share/mise/shims`，zsh 把它排在系統目錄前面（apt 可能有同名的舊版）
- mise 本體：`~/.local/bin/mise`

## 常用指令

| 想做什麼 | 指令 |
|---|---|
| 看裝了什麼、從哪份設定來 | `mise ls` |
| 看哪些有新版 | `mise outdated` |
| 全部更新 | `mise up`（清單寫 `latest`，會升到最新版） |
| 更新完清掉舊版 | `mise prune` |
| 某個指令實際跑哪一支 | `mise which fzf` |
| 自己另外裝一個工具 | `mise use -g <工具>`（寫進 `~/.config/mise/config.toml`，不跟 chezmoi 那份打架） |
| 移除 | 先打 `tools` 取消勾選，再 `mise uninstall <工具>`；只 uninstall 的話，清單有變時 apply 會再裝回來 |
| 更新 mise 本身 | `mise self-update` |
| 有問題先跑 | `mise doctor` |

其他指令、設定檔格式見[官方文件](https://mise.jdx.dev/)（[CLI 參考](https://mise.jdx.dev/cli/)）。

## 出問題時

| 狀況 | 怎麼辦 |
|---|---|
| apply 印「mise install 有工具沒裝好」 | 多半是 GitHub API 限流（未登入每小時 60 次）：`GITHUB_TOKEN=$(gh auth token) mise install` |
| 打指令跑到 apt 的舊版 | 開新的 zsh（舊 shell 的 PATH 沒有 shims 在前面）；再不行 `mise which <指令>` 看 |
| bash 裡找不到 eza 這類指令 | 只有 zsh 把 shims 加進 PATH；bash 用 `~/.local/share/mise/shims/<指令>` |
