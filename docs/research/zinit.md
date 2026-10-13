# zinit 與 chezmoi external 管 zsh 插件的差別

> 研究日期：2026-10-06。問題來源：#105（map：#104）。
> 標示：**[確認]** 讀過一手來源原文或 API 輸出；**[推論]** 從原始碼或文件推出；**[查不到]** 一手來源沒寫。

## 結論

這台機器的 zsh 啟動是 **558 ms**（不含 fastfetch），其中大約 **375 ms 是 nvm**。
`.chezmoiexternal` 管的三個插件加起來只有大約 **30 ms**。
zinit turbo 只能延後 autosuggestions 和 syntax-highlighting，p10k 要維持同步載入，所以換 zinit 最多省 **約 15–20 ms，不到 4%**。

換 zinit 的成本：多一個要自己更新的工具、installer 會想改 `.zshrc`，而且原生 Termux 上沒有實機驗證過。
不換的理由比換的理由多。要讓啟動變快，先處理 nvm（例如 `nvm.sh --no-use` 或 lazy load），效果是 zinit 的二十倍。

| 項目 | 現況（chezmoi external + 手動 source） | zinit |
|---|---|---|
| 啟動時間 | 558 ms，三個插件約 30 ms | 最多省 15–20 ms（p10k 不能 turbo） |
| 延遲載入 | 沒有 | `wait` / `lucid`（turbo） |
| 誰 clone / 更新插件 | `chezmoi apply -R`（`refreshPeriod` 沒設＝平常不更新） | `zinit update`，跟 `chezmoi update` 分開 |
| 插件目錄 | `~/.config/zsh/<插件>`，chezmoi 管 | `~/.local/share/zinit/plugins`，zinit 管 |
| 新機器 | `chezmoi init --apply` 一次到位 | 第一次開 zsh 時才 clone zinit 與插件（要連網） |
| OMZ 單檔 snippet | 沒有 | `zinit snippet OMZP::git` |
| 維護狀態 | chezmoi 本身活躍 | 有維護，但主要靠一個人（v3.17.0，2026-09-02） |
| 原生 Termux | 已在用 | 純 zsh 插件應該可以，`gh-r` 與 bin-gem-node annex 有已知問題；未實機驗證 |

## 1. 啟動時間基準（這台機器）

環境：x86_64、8 核、Ubuntu、`~/.zshrc` 與 `home/dot_zshrc` 內容相同（`cmp` 確認）。
每項先跑一次暖機，再跑 20 次取平均，用 bash 的 `date +%s%N` 計時，輸出導到 `/dev/null`。

| 量法 | 平均 | 最小 | 最大 |
|---|---|---|---|
| `zsh -i -c exit`（完整） | 564 ms | 555 | 583 |
| `zsh -i -c exit`，`PATH` 前面放一個空的 `fastfetch` | 558 ms | 549 | 576 |
| `zsh -f -c exit`（不讀 rc） | 5 ms | 5 | 5 |
| `fastfetch` 單獨 | 8 ms | 8 | 9 |

注意：fastfetch 的輸出導到 `/dev/null`，在真的終端機上它還要畫圖，實際時間可能更長，這裡只量得到下限。

### 拆開看：時間花在哪

`zmodload zsh/zprof` 包住 `source ~/.zshrc` 的結果（前幾名，單位 ms）：

| 函式 | 含子呼叫 | 佔比 |
|---|---|---|
| `nvm_auto`（nvm.sh 載入時自動 `nvm use`） | 454 | 92% |
| `nvm` | 377 | 77% |
| `compinit` | 17 | 4% |
| `_zsh_highlight_load_highlighters` | 6 | 1% |
| powerlevel10k 主題初始化 | 10 | 2% |

（zprof 本身有額外開銷，所以總和比 558 ms 大，只看比例。）

每個元件單獨用 `zsh -f -c '<source 它>'` 跑三次（每次都含約 5 ms 的 zsh 本身）：

| 元件 | 時間 | 扣掉 5 ms 的 zsh |
|---|---|---|
| nvm.sh | 375–383 ms | ~375 ms |
| compinit | 25 ms | ~20 ms |
| powerlevel10k + `~/.p10k.zsh` | 21 ms | ~16 ms |
| zsh-syntax-highlighting | 15 ms | ~10 ms |
| zsh-autosuggestions | 8 ms | ~3 ms |

zinit turbo 能延後的只有後兩項加上 compinit（`atinit"zicompinit; zicdreplay"`），上限約 **33 ms**。
如果 compinit 維持同步，只剩約 **13 ms**。
另外，p10k instant prompt 已經讓 prompt 在插件載完前就先畫出來，使用者感受到的等待本來就比 558 ms 短。

## 2. zinit 維護狀態

- **[確認]** repo 沒 archived，4871 stars，最後 push 2026-09-30，最新 release v3.17.0（2026-09-02）。
  來源：https://github.com/zdharma-continuum/zinit 、https://github.com/zdharma-continuum/zinit/releases
- **[確認]** 2025-10 之後約 100 筆 commit 裡，大約 65 筆是 vladdoster，其餘是 dependabot 和零星貢獻者。實際上主要靠一個人維護。
  來源：https://github.com/zdharma-continuum/zinit/graphs/contributors
- **[確認]** 2021 年原作者（psprint）把 zdharma 底下的 repo 全部刪掉，社群用手上的 clone 在 zdharma-continuum 重建。
  來源：https://github.com/zdharma-continuum/I_WANT_TO_HELP 、https://github.com/zdharma-continuum/zinit/issues/28
- **[確認]** 順帶一提，powerlevel10k README 開頭寫「THE PROJECT HAS VERY LIMITED SUPPORT」，但 repo 沒 archived。
  來源：https://github.com/romkatv/powerlevel10k

## 3. zinit 比現況多了什麼

### Turbo（延遲載入）

- **[確認]** `wait` 讓插件在第一個 prompt 出現後才載入；`wait'1'` 是 1 秒後；`lucid` 不印「Loaded …」。
  官方宣稱啟動快 50–80%。
  來源：https://github.com/zdharma-continuum/zinit#turbo-and-lucid 、https://zdharma-continuum.github.io/zinit/wiki/INTRODUCTION/
- **[確認]** 官方 Minimal Setup 的寫法：

  ```zsh
  zinit wait lucid light-mode for \
    atinit"zicompinit; zicdreplay" zdharma-continuum/fast-syntax-highlighting \
    atload"_zsh_autosuggest_start" zsh-users/zsh-autosuggestions
  ```

  來源：https://zdharma-continuum.github.io/zinit/wiki/Example-Minimal-Setup/
- **[確認]** zsh-syntax-highlighting 必須最後載入，而且它的官方文件寫「authors recommend manual installation over … plugin manager」。
  來源：https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md
- **[確認]** p10k README 對 zinit 只給同步寫法 `zinit ice depth=1; zinit light romkatv/powerlevel10k`，完全沒提 turbo。
  來源：https://github.com/romkatv/powerlevel10k#zinit
- **[推論]** instant prompt 已經解決「prompt 出現前要等」的問題，所以 p10k 維持同步，turbo 只用在其他插件。

### 更新與 snippet

- **[確認]** `zinit self-update`、`zinit update --all`、`zinit update --parallel`。
  來源：https://github.com/zdharma-continuum/zinit#upgrade-zinit-and-plugins
- **[確認]** `zinit snippet OMZP::git` 之類可以只載 Oh My Zsh 的單一檔案；`depth`、`ver` ice 可以控制 clone 深度和版本（不能用在 snippet）。
  來源：https://github.com/zdharma-continuum/zinit#oh-my-zsh 、https://github.com/zdharma-continuum/zinit#ice-modifiers
- 現況對照：`home/.chezmoiexternal.toml.tmpl` 第 1 段的三個 `git-repo` 沒設 `refreshPeriod`，平常 apply 不更新，要更新跑 `chezmoi apply -R`。
  **[確認]** `refreshPeriod` 預設 0＝永不自動更新；`-R` 等於 `--refresh-externals=always`。
  來源：https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/ 、https://www.chezmoi.io/reference/command-line-flags/global/

## 4. 跟 chezmoi 共存

- **[確認]** zinit 預設把自己放在 `~/.local/share/zinit/zinit.git`，插件放 `~/.local/share/zinit/plugins`，snippet 放 `~/.local/share/zinit/snippets`。
  都可以用 `zstyle ':zinit:config' home-dir` 或 `ZINIT[...]` 改。
  來源：https://github.com/zdharma-continuum/zinit#install 、https://github.com/zdharma-continuum/zinit#customizing-paths
- **[確認]** 官方 installer 預設會改 `.zshrc`，要設 `NO_EDIT` 才不改。`.zshrc` 是 chezmoi 管的，所以不能讓 installer 改（下次 apply 會蓋回去）。
  來源：https://github.com/zdharma-continuum/zinit/blob/main/scripts/install.sh
- **[確認]** chezmoi 官方文件完全沒提 zinit，只示範用 `archive` external 管 Oh My Zsh 等，並要求關掉 OMZ 的自動更新，否則跟 source state 對不上。
  來源：https://www.chezmoi.io/user-guide/include-files-from-elsewhere/
- **[推論]** 不會兩邊管同一個目錄的做法：
  - zinit 自己用 `.zshrc` 裡的 bootstrap 片段（目錄不存在就 `git clone`）裝，不跑 installer。
  - `.chezmoiexternal.toml.tmpl` 第 1 段整段刪掉，插件全交給 zinit。
  - 如果反過來想讓 chezmoi external clone zinit 本體，那只能管 `zinit.git`，`plugins/` 不能碰；這樣更新又分成兩個指令，不如全交給 zinit。
- 代價：新機器 `chezmoi init --apply` 之後插件還沒下載，第一次開 zsh 才 clone。
- 容器 e2e 也要改：`script/tests/e2e.sh` 第 167 行列了三個 external 目錄，第 179 行用 `zsh -i -c` 檢查三個插件的函式已載入。
  **[推論]** turbo 的插件要等第一個 prompt 之後才載，`zsh -i -c` 不會出 prompt，所以這項檢查在 turbo 下會失敗，要換檢查方式。
- 同理，第 1 節的 `zsh -i -c exit` 基準在 turbo 下會「看起來」更快，因為延後的插件根本沒載；要比較就得量到第一個 prompt（例如 zsh-bench），不能只比 `-c exit`。

## 5. 原生 Termux

- **[確認]** installer 需要 git（沒有就 `exit 1`），抓檔用 curl 或 wget。zsh 版本只警告不擋。
  shebang 是 `#!/usr/bin/env bash`，但官方用法是 `bash -c "$(curl …)"`，用不到 shebang。
  來源：https://github.com/zdharma-continuum/zinit/blob/main/scripts/install.sh
- **[確認]** `zinit.zsh`、`zinit-install.zsh`、`zinit-autoload.zsh` 裡寫死的 `/usr/bin/` 只有一處，在 Darwin 分支。
- **[確認]** `from"gh-r"`（下載 GitHub release 的 binary）用 `uname -s` 判斷平台，沒有 Android 判斷。
  **[推論]** Termux 的 `uname -s` 是 Linux，會挑到 glibc 版 binary，在 Android（bionic）上跑不起來。
  來源：https://github.com/zdharma-continuum/zinit/blob/main/zinit-install.zsh
- **[確認]** 已知的 Termux 問題：
  - zinit-module 不支援 Android（issue 2022 年開到現在）：https://github.com/zdharma-continuum/zinit-module/issues/6
  - zinit-annex-bin-gem-node 的 shim 在 Termux 報 `bad interpreter`，修正 PR 沒合併就關了：https://github.com/zdharma-continuum/zinit-annex-bin-gem-node/pull/14
- **[推論]** 只載 autosuggestions、syntax-highlighting、p10k 這種純 zsh 插件，在 Termux 上應該能跑。**沒有實機驗證。**

## 6. 比較輕的替代

如果將來插件變多、真的需要延遲載入，先看 antidote（把插件清單靜態產生成一個載入檔，搭 zsh-defer）：https://github.com/mattmc3/antidote 。
只想延後某幾行就用 zsh-defer：https://github.com/romkatv/zsh-defer 。

## 查不到的

- p10k 官方對「用 turbo 載入 p10k」的明確說法。
- termux-exec 會不會改寫 `/usr/bin/env` shebang。
- zinit 在原生 Termux 上實際跑的結果。
- zsh-autosuggestions 官方的 zinit 寫法（它的 INSTALL.md 沒有 zinit 段）。
