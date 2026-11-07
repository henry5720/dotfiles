# 用途與憑證

`chezmoi init` 第一題問這台的用途，第二題的選裝工具選單照用途預設勾好；憑證只問勾了的工具用得到的。
安裝步驟見[新機器設定 2.3](../new-machine-setup.md#23-一行指令裝好)，裝完要改見[改設定與更新](../after-install.md)。

## 用途

| 用途 | 代號 | 給誰 | 預設勾哪些 |
|---|---|---|---|
| 完整 | `full` | 開發主力機 | 選單上全部，扣掉這台不建議、裝不了的（見下面〈環境〉） |
| 精簡 | `minimal` | 只要 shell 體驗（每台開 shell 看到的一樣） | zsh、starship、eza、fzf、bat、ripgrep、vim、fastfetch |
| 自訂 | `custom` | 有特殊需求 | 都不勾，自己選 |

用途那題按一個字母 `f`、`m`、`c` 就送出（chezmoi 的單選輸入對到唯一選項就送出，不等 Enter），不用切輸入法；直接 Enter 是精簡。
選錯用途時在下一題的選單按 Ctrl+C，整個 init 不存檔，重來一次（Esc 會照目前勾選送出，不是取消）。config 的 `machineUse` 存代號；
以前存中文（`完整`／`精簡`／`自訂`）的機器，下次 `chezmoi init` 會換成代號，勾選不變。
第一次 init 預設停在精簡，直接 Enter 就是精簡。

選完沒改勾選，config 只認用途：之後 repo 改了這個用途的預設組合，跑 `chezmoi init` 就跟上（拉新版時用 `chezmoi update --init`，見[改設定與更新](../after-install.md)）。
改過勾選就存成自訂，照你勾的、不再跟著預設組合走。

精簡以前還有 tailscale、btop（#273 拿掉，加了 fastfetch）。存精簡的舊機器下次 `chezmoi init` 後 tools 少這兩項，但已經裝的不會解除安裝，只是不再管它們；還要 chezmoi 管就打 `tools` 勾回來（會存成自訂）。

- 原生 Termux、Windows 主機也問，流程一樣；精簡、完整扣掉那台裝不了的（見下面〈環境〉）。Windows 的精簡沒有 zsh，另外每台 Windows 都裝 zoxide（見[Windows 主機](windows.md#裝了什麼怎麼用)）。`node` 在 Termux 是 pkg 的 `nodejs-lts`、在 Windows 是 mise 的 Node LTS，都不走 nvm。
- 非 Debian 系 Linux 照樣問，走 apt 的選裝工具改用 mise 裝（見[沒有 root 的機器](no-root-machine.md)）。
- `node` 裝 nvm 與 Node LTS，給只要 Node、不要其他工具的機器；完整有、精簡沒有。勾了要 Node 的工具（codegraph、playwright-cli、opencode、wakatime）沒勾 `node` 也會一併裝。以前存著 `nvm` 的 config，下次 `chezmoi init` 換成 `node`。
- `starship` 是 zsh、bash 共用的提示列，跟 `zsh` 分開勾：只要 zsh 外掛、不要提示列，或用 bash 配 starship 都行；沒勾就是 shell 預設的提示列。以前存自訂、勾了 `zsh` 的 config（當時 zsh 附帶 p10k），下次 `chezmoi init` 自動補勾 `starship`。

選項清單與每一項的說明在 [`home/.chezmoitemplates/tool-menu`](../../home/.chezmoitemplates/tool-menu)，
用途的預設組合在 [`home/.chezmoi.toml.tmpl`](../../home/.chezmoi.toml.tmpl) 的 `$lean`。

## 環境：不建議、裝不了

選單每台都列全部工具。這台環境不建議或裝不了的，說明後面標原因，例如
`headless-chrome  沒有畫面的 Chrome,給 agent 開網頁（裝不了：Google 只出 amd64 的 .deb）`：

| 狀態 | 預設組合 | 勾了 |
|---|---|---|
| 可裝 | 照用途 | 裝 |
| 不建議 | 不勾 | 照裝 |
| 裝不了 | 不勾 | 略過；apply 照樣跑完，最後跟「沒有 root」分開列出略過了哪些、為什麼 |

目前不建議的：WSL、proot Ubuntu 的 `tailscale`（網路借外層 Windows 或 Android 那份 Tailscale，再裝一份會變成 tailnet 上兩個節點）；
WSL 的 `snapserver`（抓不到自己的 tailnet IP）。
目前裝不了的：WSL、非 amd64、非 Debian 系、macOS 的 `headless-chrome`、`playwright-cli`；原生 Termux 除了這兩項，
還有 `tailscale`（裝 Android app）、`btop`（在 root-repo）、`code-server`、`claude`、`codex`、`opencode`、`herdr`、
`agent-config`、`codegraph`（沒有 Termux 版，coding agent 到同一台平板的 proot Ubuntu 用）。
`snapserver` 只裝在有 systemd 的 Debian 系 Linux：Windows、macOS、原生 Termux、proot Ubuntu、非 Debian 系都裝不了。
Windows 主機只有 mise 裝得到的 CLI（`btop` 除外，`node` 裝 LTS）和 `tailscale` 可裝，其餘標裝不了、到 WSL 裝（見[Windows 主機](windows.md#裝了什麼怎麼用)）。
macOS 的 `tailscale` 用 brew cask 裝官方 app（`tailscale-app`）。哪個工具在哪個環境是什麼狀態、原因怎麼寫，只在
[`home/.chezmoitemplates/tool-env`](../../home/.chezmoitemplates/tool-env)；選單標註、預設組合、略過彙整都從那裡拿。

## 憑證

| 勾了 | 問 |
|---|---|
| code-server | `code-server 密碼` |
| codex 或 opencode | `codex-lb API key` |
| agent-config | `Context7 API key`（可留空） |
| wakatime | `WakaTime API key`（可留空） |

沒勾的不問、也不寫進 config；之後勾了，`tools` 會在那時問。取消勾選不刪存過的值。
Git 身分（`git user.name`、`git user.email`）每台都問，Windows 主機除外（不部署 `.gitconfig`）。
