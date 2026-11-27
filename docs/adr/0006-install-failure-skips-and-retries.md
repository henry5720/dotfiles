# 選裝工具裝失敗時略過、最後列出、下次 apply 重試；基底裝失敗才停

[ADR 0004](0004-menu-lists-every-tool-environment-decides-defaults-and-skips.md) 管的是「裝不了」：選裝工具表事先算出這台裝不了，勾了就略過、apply 最後列出。
它沒管另一種情況：工具在這台裝得了，這次卻沒裝起來（網路斷、GitHub API 限流、套件管理員壞了）。這種叫**裝失敗**（GLOSSARY）。

在這之前，各 OS 處理方式不同。Linux、macOS、Termux 的 sh 腳本開了 `set -eu`，一個工具失敗就讓整個 apply 停下來；
Windows 的 `.ps1` 跟 `install-mise` 則印一行、exit 0，但不會進最後的略過彙整，也不會重試。
一台 Intel macOS 的 brew 目錄沒有寫入權限，`brew bundle` 失敗、apply 停在 `install-packages-darwin`，後面的 dotfiles 一個都沒部署（#420）。

現在的規則：

| 什麼裝失敗 | apply | 列在哪 | 下次 apply |
|---|---|---|---|
| 選裝工具（含它的依賴套件、plugin） | 繼續，那一項略過 | 彙整的「這次裝失敗」那段（`install-failed`），錯誤訊息照樣在上面的輸出 | 重跑那支腳本 |
| 基底（`packages.yaml`） | 停 | 套件管理員自己的錯誤訊息 | 照常重跑（腳本沒跑完，chezmoi 不會記成跑過） |

做法：

- 腳本失敗時呼叫 `skip_fail <工具> <怎麼補>`（`.chezmoitemplates/sh-skip`），記進彙整、留下重試標記 `~/.local/state/dotfiles/retry/<腳本>`。
- 腳本開頭 include `.chezmoitemplates/sh-retry`：渲染時用 `stat` 看標記在不在，在就多印一行帶時間的註解，腳本內容跟著變，
  `run_onchange_` 下次 apply 就會重跑。重跑一開始先刪標記，這次又失敗才再留。
- 彙整腳本 `run_after_zz-root-skipped-summary` 從只在「沒有 root、或勾了裝不了的工具」的機器渲染，改成每台 Linux、macOS、Termux 都有，因為任何機器都可能裝失敗。
- macOS 的基底只有 jq 走 brew。chezmoi 要用的 git、curl、python3 來自系統與 Xcode CLT，所以 `brew bundle` 整包（含 jq）都算選裝那一類：
  brew 壞了也不擋 apply。jq 只有 `install-wakatime` 查 plugin 時用到，#421 會把它拿出基底。

## Considered Options

| 做法 | 結果 | 為什麼 |
|---|---|---|
| 維持 `set -eu`，一個失敗就停（原本的 sh） | 不選 | 排在後面的檔案和工具全部沒裝；一台 brew 壞掉的機器連 shell 設定都拿不到 |
| 印一行、exit 0（原本的 `.ps1`、`install-mise`） | 不選 | 訊息夾在幾百行輸出中間；`run_onchange_` 記成跑過，修好之後也不會自己補裝 |
| 另外寫 log 檔給人事後看 | 不選 | 錯誤訊息本來就印在終端機；缺的是「哪幾個沒裝上」的摘要，彙整多一段就有了。要完整紀錄當下用 `chezmoi apply 2>&1 \| tee` |
| 安裝腳本改成 `run_`，每次 apply 都跑 | 不選 | `brew bundle` 每次都會先 `brew update`，很慢；只有失敗過的腳本需要重跑 |
| `skip_fail` 加重試標記，`run_onchange_` 照舊 | **選** | 沒失敗的機器行為不變；失敗過的下一次 apply 自動補 |

## 代價

- **彙整腳本每台都有。** 它是 `run_after_`，每次 apply 都跑，沒東西可印就什麼都不印。`chezmoi verify` 本來就要 `--exclude scripts`。
- **重試標記不會自己過期。** 一直裝不起來的工具（例如 Intel macOS 上某個 brew 編不過的 formula），每次 apply 都會重跑那支腳本、再列一次。
  這是刻意的：要讓它停，就取消勾選。
- **macOS 的 cask 不重試。** cask 最常見的失敗是 `/Applications` 已經有同一個 app（官網或 App Store 裝的），重試只會每次再失敗一次，所以維持印一行略過。
- **Windows 的 `.ps1` 還沒跟上。** 它們本來就不會讓 apply 停，但裝失敗還沒進彙整、也還沒重試；#422 處理，要在 Windows 實機驗。
