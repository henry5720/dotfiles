# 用途與憑證

`chezmoi init` 第一題問這台的用途，第二題的選裝工具選單照用途預設勾好；憑證只問勾了的工具用得到的。
安裝步驟見[新機器設定 2.3](new-machine-setup.md#23-一行指令裝好)，裝完要改見[裝完之後](after-install.md)。

## 用途

| 用途 | 給誰 | 預設勾哪些 |
|---|---|---|
| 完整 | 開發主力機 | 選單上全部（WSL、非 amd64、非 Debian 系本來就不列 `headless-chrome`、`playwright-cli`；macOS 另外不列 `tailscale`） |
| 精簡 | ssh viewer、server | zsh、eza、fzf、bat、ripgrep、vim、tailscale、btop |
| 自訂 | 有特殊需求 | 都不勾，自己選 |

選完沒改勾選，config 只認用途：之後 repo 改了這個用途的預設組合，跑 `chezmoi init` 就跟上。
改過勾選就存成自訂，照你勾的、不再跟著預設組合走。

- 原生 Termux 不問，直接套精簡、濾掉 tailscale、btop。
- 非 Debian 系 Linux 照樣問，走 apt 的選裝工具改用 mise 裝（見[沒有 root 的機器](new-machine-setup.md#沒有-root-的機器)）。
- 勾了要 Node 的工具（codegraph、playwright-cli、opencode、wakatime）會一併裝 nvm 與 Node LTS，nvm 不在選單上。

選項清單與每一項的說明在 [`home/.chezmoitemplates/tool-menu`](../home/.chezmoitemplates/tool-menu)，
用途的預設組合在 [`home/.chezmoi.toml.tmpl`](../home/.chezmoi.toml.tmpl) 的 `$lean`。

## 憑證

| 勾了 | 問 |
|---|---|
| code-server | `code-server 密碼` |
| codex 或 opencode | `codex-lb API key` |
| agent-config | `Context7 API key`（可留空） |
| wakatime | `WakaTime API key`（可留空） |

沒勾的不問、也不寫進 config；之後勾了，`tools` 會在那時問。取消勾選不刪存過的值。
Git 身分（`git user.name`、`git user.email`）每台都問。
