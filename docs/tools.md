# 工具一覽

已配置主機上有哪些工具、各自最常用的一兩個指令。其餘用法照官網；這個 repo 有細節文件的，連在最後一欄。
怎麼連上已配置主機、怎麼開 agent，見[操作已配置主機](configured-host.md)。

哪些工具會裝，看那台的用途與勾選（[用途與憑證](machine-use.md)）；要加減用 `tools`。

```
shell 日常      zsh  starship  eza  fzf  bat  ripgrep  vim  fastfetch  btop
入口與連線      tailscale  code-server  ttyd  gh
coding agent    herdr  claude  codex  opencode  agent-config
agent 輔助      codegraph  headless-chrome  playwright-cli  node
其他            ffmpeg  wakatime
自寫指令        tools  ai-profile  share-shell  remote-chrome  codegraph-setup-repo
```

## shell 日常

| 工具 | 做什麼 | 常用 | 官網 |
|---|---|---|---|
| zsh | 預設 shell；打字時灰字建議、指令上色、跳常去的目錄 | `→` 接受灰字建議；`z <目錄名片段>` 跳過去 | [zsh](https://www.zsh.org/) |
| starship | 提示列：目錄、git 分支與狀態 | 不用打指令，自動顯示 | [starship](https://starship.rs/) |
| eza | 彩色、帶圖示的 ls | `ll` 詳細列表、`lt` 兩層樹狀 | [eza](https://eza.rocks/) |
| fzf | 模糊搜尋 | `Ctrl-R` 找打過的指令、`Ctrl-T` 找檔案 | [fzf](https://github.com/junegunn/fzf) |
| bat | 有語法上色的 cat | `bat <檔案>` | [bat](https://github.com/sharkdp/bat) |
| ripgrep | 全文搜尋 | `rg <關鍵字>` 搜目前資料夾底下所有檔案 | [ripgrep](https://github.com/BurntSushi/ripgrep) |
| vim | terminal 裡的文字編輯器 | `vim <檔案>`；`:wq` 存檔離開、`:q!` 不存離開 | [vim](https://www.vim.org/) |
| fastfetch | 印出系統資訊 | `fastfetch` | [fastfetch](https://github.com/fastfetch-cli/fastfetch) |
| btop | 工作管理員：CPU、記憶體、行程 | `btop`，按 `q` 離開 | [btop](https://github.com/aristocratos/btop) |

Linux 上 eza、fzf、bat、ripgrep、starship、btop 由 mise 裝，更新與移除見 [mise](mise.md)。

## 入口與連線

| 工具 | 做什麼 | 常用 | 官網 | 細節 |
|---|---|---|---|---|
| tailscale | 私人網路，連自己的機器 | `tailscale status` 看有哪些機器、名稱與 IP | [tailscale](https://tailscale.com/kb) | |
| code-server | 瀏覽器開的 VS Code | `code-server` | [code-server](https://coder.com/docs/code-server) | [code-server 遠端存取](code-server-remote.md) |
| ttyd | 把 terminal 開成網頁 | 不直接用，透過 `share-shell` | [ttyd](https://github.com/tsl0922/ttyd) | [開給訪客看](share-with-guest.md) |
| gh | GitHub CLI | `gh auth login` 登入；`gh pr list` 看 PR | [gh](https://cli.github.com/) | |

## coding agent

| 工具 | 做什麼 | 常用 | 官網 | 細節 |
|---|---|---|---|---|
| herdr | terminal 多工，同時開多個 agent | `herdr --session <名字>` | [herdr](https://github.com/herdrdev/herdr) | [操作已配置主機〈herdr〉](configured-host.md#herdr) |
| claude | Claude Code | `claude`；`claude --bg "<任務>"` 背景跑 | [Claude Code](https://code.claude.com/docs/en/overview) | [操作已配置主機〈coding agent〉](configured-host.md#coding-agent) |
| codex | Codex CLI | `codex` | [Codex CLI](https://developers.openai.com/codex/cli) | |
| opencode | OpenCode | `opencode` | [OpenCode](https://opencode.ai/docs) | [opencode 設定](opencode.md) |
| agent-config | 用 skillshare 統一管理各 agent 的 skills、MCP、全域規則 | `skillshare sync` 同步到各 agent | [skillshare](https://skillshare.runkids.cc/) | [AI agent 環境：誰管什麼](ai-agent-setup.md) |

## agent 輔助

多半是 agent 自己用，人很少直接打。

| 工具 | 做什麼 | 常用 | 官網 | 細節 |
|---|---|---|---|---|
| codegraph | 程式碼索引，給 agent 查 | `codegraph status` 看索引狀態 | [codegraph](https://github.com/colbymchenry/codegraph) | [codegraph](codegraph.md) |
| headless-chrome | 沒有畫面的 Chrome，給 agent 開網頁 | 不直接用 | [Headless Chrome](https://developer.chrome.com/docs/chromium/headless) | |
| playwright-cli | agent 點網頁、填表、截圖 | 不直接用 | [playwright-cli](https://github.com/microsoft/playwright-cli) | [playwright-cli](playwright-cli.md) |
| node | nvm＋Node LTS，給要 Node 的工具 | `node -v` | [nvm](https://github.com/nvm-sh/nvm) | |

## 其他

| 工具 | 做什麼 | 常用 | 官網 | 細節 |
|---|---|---|---|---|
| ffmpeg | 影音轉檔、抽音軌與影格 | `ffmpeg -i 輸入.mov 輸出.mp4` | [FFmpeg](https://github.com/FFmpeg/FFmpeg) | |
| wakatime | 記錄寫程式的時間 | 不用打指令，自動送 | [WakaTime](https://wakatime.com/) | [WakaTime](wakatime.md) |

## 自寫指令

放在 `~/.local/bin`，這個 repo 自己寫的，沒有官網。

| 指令 | 做什麼 | 細節 |
|---|---|---|
| `tools` | 改用途、加減選裝工具 | [裝完之後](after-install.md) |
| `codex-work`、`codex-personal`、`opencode-work`、`opencode-personal` | 用公司或個人帳號開 agent（都是 `ai-profile`） | [AI profile routing](ai-profile-routing.md) |
| `share-shell` | 把 terminal 臨時開成公網網頁給訪客，Ctrl+C 就關 | [開給訪客看](share-with-guest.md) |
| `remote-chrome` | 開一個 agent 連得到的 Chrome | agent-config 的 remote-chrome skill |
| `codegraph-setup-repo` | 幫一個 repo 建 codegraph 索引 | [codegraph](codegraph.md) |
