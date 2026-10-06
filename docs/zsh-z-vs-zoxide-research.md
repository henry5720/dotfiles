# zsh-z 與 zoxide 的差別

本文件回答 issue #108（map #104）。查詢時間 2026-10-06，來源都是兩個 repo 的 README、原始碼、release，
以及 Ubuntu／Debian／Termux 的套件庫。沒有在本機實測速度。

## 結論

兩者的 frecency 本質相同（都是「次數 × 越近越高的權重」，總分超過上限就整體打折），日常 `z foo` 用起來差不多。
真正的差別在三件事：

1. **互動選擇**：zoxide 內建 `zi`（叫 fzf 選）；zsh-z 沒有，只有按 Tab 出照 frecency 排序的補全選單。
2. **依賴**：zsh-z 只要 zsh，跟現在 p10k 等插件一樣用 `git-repo` external clone 就好；zoxide 要裝一個 binary，`zi` 還要 fzf ≥ 0.51。
3. **Ubuntu 24.04 的 apt 版本太舊**：noble 的 `zoxide` 是 0.9.3、`fzf` 是 0.44.1（低於 zoxide 要求的 0.51），
   要用 `zi` 就得走 zoxide 的 install.sh 和 fzf 的官方安裝方式，不能只加進 `packages.yaml`。Termux 兩個都是最新版，沒有這個問題。

## 對照表

| 項目 | zsh-z（agkozak/zsh-z） | zoxide（ajeetdsouza/zoxide） |
|---|---|---|
| 實作 | 純 zsh script，rupa/z 的移植 | Rust binary，`eval "$(zoxide init zsh)"` 產生 shell 函式 |
| 支援 shell | 只有 zsh（≥ 4.3.11） | bash、zsh、fish、nushell、PowerShell、elvish、tcsh、xonsh、POSIX |
| 排序公式 | `rank × 3.75 / (0.0001 × 秒數 + 1.25)`，連續衰減 | `score` 依上次造訪時間乘 4／2／½／¼（1 小時／1 天／1 週／更久），分段 |
| 老化 | 總分 > `ZSHZ_MAX_SCORE`（預設 9000）時全部 × 0.99，< 1 刪掉 | 總分 > `_ZO_MAXAGE`（預設 10000）時全部除到約 90%，< 1 刪掉；90 天沒用且已不存在的目錄也刪 |
| 比對 | 預設先試大小寫相符、再不分大小寫；`ZSHZ_CASE=smart` 類似 vim smartcase | 一律不分大小寫；多個關鍵字要依序出現，最後一個要對到路徑最後一段 |
| 互動選擇 | 無內建 fzf；Tab 補全照 frecency 排序 | `zi foo` 用 fzf 選；`z foo<空白><Tab>` 也會開 fzf |
| 何時記錄 | 每個 prompt（`precmd`），寫入在背景 `&!` 不卡 prompt | 預設每次換目錄（`chpwd`），前景跑一次 `zoxide add` |
| 資料檔 | `~/.z`（`path\|rank\|time` 純文字，與 rupa/z、fasd 相同格式），權限 600 | `~/.local/share/zoxide/` 二進位 db；2026-10-03 已合併改成純文字，但還沒發 release |
| 匯入舊資料 | 直接讀 rupa/z、fasd 的檔；autojump 用一行 awk 轉 | `zoxide import <z\|zsh-z\|fasd\|autojump\|z.lua\|atuin>`，自動找資料檔 |
| 速度（官方數字） | 200 筆資料、WSL2：add 1.99 ms、search 3.62 ms | README 沒有公開 benchmark |
| 維護 | 單人維護；v2.0（2026-08-14）、v2.0.1（2026-10-01）；2.4k stars、19 個 open issue | v0.10.0（2026-07-04）；39.9k stars、144 個 open issue；最後 commit 2026-10-03 |
| 原生 Termux | 跟其他 zsh 插件一樣 git clone，只用 zsh 內建 module | `pkg install zoxide`（0.10.0），fzf 0.74.4 |
| Ubuntu 24.04 apt | 不需要 | `zoxide` 0.9.3、`fzf` 0.44.1（不夠 `zi` 用） |
| 依賴 | zsh；tab 補全要 `compinit` | zoxide binary；`zi` 要 fzf ≥ 0.51；補全要放在 `compinit` 之後 |

## 細節與來源

### 排序演算法（frecency）

- zsh-z 的公式在原始碼 `zsh-z.plugin.zsh` 的 frecency routine：
  `rank=$(( 10000 * rank_field * (3.75/( (0.0001 * dx + 1) + 0.25)) ))`，`dx` 是距上次造訪的秒數。
  老化在同檔 `ZSHZ_MAX_SCORE` 那段，超過就每筆 `0.99 * rank`，rank < 1 的下次寫入時丟掉。
  來源：[zsh-z.plugin.zsh](https://github.com/agkozak/zsh-z/blob/master/zsh-z.plugin.zsh)、
  [README Settings](https://github.com/agkozak/zsh-z#settings)。README 說它是 rupa/z 的移植，資料格式相同：
  [README 開頭](https://github.com/agkozak/zsh-z#zsh-z)。
- zoxide 的分段乘數、老化與 90 天清除寫在官方 wiki：[Algorithm](https://github.com/ajeetdsouza/zoxide/wiki/Algorithm)。
  比對規則（不分大小寫、依序、最後一段要對到）同一頁的 Matching。

### 互動選擇（`zi` + fzf）

- zoxide README 的 Getting started 列出 `zi foo` 與 `z foo<SPACE><TAB>`，第 3 步寫 fzf 最低支援 v0.51.0：
  [README](https://github.com/ajeetdsouza/zoxide#getting-started)。zsh hook 裡 `zi` 呼叫 `zoxide query --interactive`：
  [templates/zsh.txt](https://github.com/ajeetdsouza/zoxide/blob/main/templates/zsh.txt)。fzf 選項用 `_ZO_FZF_OPTS` 調。
- zsh-z 原始碼和 README 都沒有 fzf；README 只提供照 frecency 排序的 Tab 補全，建議搭 `zstyle ':completion:*' menu select`：
  [README Installation](https://github.com/agkozak/zsh-z#installation)、`ZSHZ_COMPLETION` 在 [Settings](https://github.com/agkozak/zsh-z#settings)。
  要 fzf 只能自己寫（例如 `z -l foo` 的輸出餵 fzf）。

### 匯入舊資料

- zoxide：`zoxide import zsh-z` 讀 `$ZSHZ_DATA`／`$_Z_DATA`／`~/.z`，用 z 的 `path|rank|time` 格式解析：
  [src/import/zsh_z.rs](https://github.com/ajeetdsouza/zoxide/blob/main/src/import/zsh_z.rs)。
  v0.10.0 把 `import --from x` 改成 `import x` 子命令，並加了 atuin 與自動找檔：
  [v0.10.0 release](https://github.com/ajeetdsouza/zoxide/releases/tag/v0.10.0)。noble apt 的 0.9.3 還是舊語法。
- zsh-z：README 的 Migrating 段說 rupa/z、fasd 的檔可直接用，autojump 用 awk 轉：
  [Migrating from Other Tools](https://github.com/agkozak/zsh-z#migrating-from-other-tools)。
- 本 repo 目前沒有任何目錄跳轉工具（`home/dot_zshrc` 和 `home/.chezmoiexternal.toml.tmpl` 都沒有），所以兩邊都沒有舊資料要匯入；
  這項只影響「先用 zsh-z、之後換 zoxide」時能不能帶走歷史 —— 可以，用 `zoxide import zsh-z`。

### 速度

- zsh-z README 的 Performance 段：Zsh 5.9、200 筆、i7-12700 + WSL2，add 1.99 ms、search 3.62 ms、list 4.36 ms；
  v2.0 起每次 prompt 的寫入都用 `&!` 丟背景，不會讓 prompt 等：[Performance](https://github.com/agkozak/zsh-z#performance)、
  [v2.0 News](https://github.com/agkozak/zsh-z#v20-august-14-2026)。
- zoxide README 沒有 benchmark。結構上它在 shell 啟動時要跑一次 `zoxide init zsh`（fork 一個 process），
  每次換目錄在前景跑一次 `zoxide add`：[templates/zsh.txt](https://github.com/ajeetdsouza/zoxide/blob/main/templates/zsh.txt)。
  兩者沒有第一手的對比數字；要比就得在目標機器上自己量。

### 維護狀態

用 `gh api` 在 2026-10-06 取得：

| | zsh-z | zoxide |
|---|---|---|
| 最新 release | v2.0.1（2026-10-01） | v0.10.0（2026-07-04） |
| 最後 commit | 2026-10-02 | 2026-10-03（[#1288 改純文字 db](https://github.com/ajeetdsouza/zoxide/pull/1288)，未 release） |
| stars／open issues | 2,456／19 | 39,910／144 |
| 授權 | MIT | MIT |

zsh-z 也內建在 Oh My Zsh（`plugins=(z)`），但那份會比上游舊：[README Oh My Zsh](https://github.com/agkozak/zsh-z#for-oh-my-zsh-users)。

### 原生 Termux 與依賴

- zoxide：Termux 套件 0.10.0，自動追上游：
  [termux-packages/zoxide/build.sh](https://github.com/termux/termux-packages/blob/master/packages/zoxide/build.sh)；
  fzf 0.74.4：[termux-packages/fzf/build.sh](https://github.com/termux/termux-packages/blob/master/packages/fzf/build.sh)。
  install.sh 也認 Android（`uname -o` = Android → `linux-android`）：[install.sh](https://github.com/ajeetdsouza/zoxide/blob/main/install.sh)。
- zsh-z：純 zsh，只用 zsh 自帶的 `zsh/datetime`、`zsh/system`、`zsh/files` module，缺 `zsh/files` 時退回外部 `mv`/`rm`：
  [zsh-z.plugin.zsh](https://github.com/agkozak/zsh-z/blob/master/zsh-z.plugin.zsh)、
  [README News 2023-08-02](https://github.com/agkozak/zsh-z#news)。不需要任何套件，跟 p10k 一樣走 `home/.chezmoiexternal.toml.tmpl` 第 1 段即可。
- Ubuntu／Debian 的 apt 版本（[Launchpad rust-zoxide](https://launchpad.net/ubuntu/+source/rust-zoxide)、
  [Launchpad fzf](https://launchpad.net/ubuntu/+source/fzf)、[sources.debian.org rust-zoxide](https://sources.debian.org/src/rust-zoxide/)、
  [sources.debian.org fzf](https://sources.debian.org/src/fzf/)）：

  | 發行版 | zoxide | fzf | `zi` 能用 |
  |---|---|---|---|
  | Ubuntu 24.04 noble | 0.9.3 | 0.44.1 | 否（fzf < 0.51） |
  | Ubuntu 26.04 resolute | 0.9.8 | 0.67.0 | 是 |
  | Debian 13 trixie | 0.9.7 | 0.60.3 | 是 |
  | Termux | 0.10.0 | 0.74.4 | 是 |

  zoxide README 自己也劃掉 Debian／Ubuntu 的 apt 安裝，註明這兩家更新太慢、建議用 install.sh：
  [README Installation](https://github.com/ajeetdsouza/zoxide#installation)。
- 非 Debian Linux：zoxide 在 Arch、Fedora、Alpine、openSUSE 等官方庫都有，也可用 install.sh（同上）；zsh-z 只要 git clone。

## 還沒查的

- 兩者在本機（WSL、Termux）的實際啟動時間與 `z` 延遲。要列成驗收條件就得自己量（map #104 的「Not yet specified」已記這件事）。
- zoxide 純文字 db 發 release 時，舊的二進位 db 會不會自動轉換 —— PR #1288 的描述沒寫。
