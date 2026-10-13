# deja 研究：它是什麼、跟現在的歷史紀錄比多了什麼

> 研究日期：2026-10-06。回答 issue #106（map #104）。
> deja 原始碼引用都釘在 commit [`529b4b6`](https://github.com/Giammarco-Ferranti/deja/tree/529b4b62aa26aa55642cea4091a0e0e8efda095b)（`main`，2026-10-02）；
> 最新 release 是 v0.4.2（2026-09-07）。

## 結論

deja 是 **zsh-autosuggestions 的替代品**，不是歷史紀錄工具，也跟 fzf Ctrl-R、atuin 不是同一類。
它只換掉 `home/dot_zshrc` 第 6 段的「自動建議」那一行；第 4 段的內建 history 照舊要留（deja 自己也是從 `~/.zsh_history` 匯入）。
多出來的是：模糊比對、依目前目錄加權、依「上一個指令」預測下一個、空提示字元就猜下一個指令、Tab 切換候選。
代價是一支常駐 daemon + 一份明文 SQLite，而且**原生 Termux 跑不了官方 binary**（glibc 動態連結），要自己編。

| 項目 | 現況：內建 history + zsh-autosuggestions | deja |
|---|---|---|
| 類型 | 行內 ghost text 建議 | 行內 ghost text 建議（同一類，互斥） |
| 比對方式 | 前綴比對，取最近一筆 | 模糊（子序列）+ frecency + 目錄 + 指令序列加權 |
| 空提示字元 | 不建議 | 預設猜下一個指令 |
| 多個候選 | 沒有 | Tab 循環 |
| 實作 | 純 zsh 腳本 | Go binary + 常駐 daemon（Unix socket）+ SQLite |
| 資料 | `~/.zsh_history` | 另存 `~/.local/share/deja/deja.db`（明文，0600） |
| 網路／同步 | 無 | 無（只用 Unix socket；沒有同步） |
| 原生 Termux | 可（已在用） | 官方 binary 不行；要 `go build` 自己編，未驗證 |
| 維護 | 36k star，最後 push 2025-06 | 884 star，2026-04 才建立，最近 commit 2026-10-02，主要一人維護 |

## 1. deja 做什麼

README 第一段：「Deja is a smarter replacement for `zsh-autosuggestions`」，
用 fuzzy matching、directory awareness、command sequence prediction 產生 ghost text
（[README](https://github.com/Giammarco-Ferranti/deja/blob/529b4b62aa26aa55642cea4091a0e0e8efda095b/README.md)）。

- 分數 = `1.0×fuzzy + 0.4×frecency + 0.3×directory_affinity + 0.5×sequence_score`（README〈How It Works〉）。
- 有「anchoring」：歷史裡有以目前輸入開頭的指令時，只在那些裡面挑；沒有才做模糊展開（README〈Anchoring〉）。
- 空提示字元預設就顯示預測的下一個指令，可用 `deja empty off` 關掉（README〈Suppressing ghost text on an empty prompt〉）。
- 按鍵：`→` 接受全部、`Ctrl+→` 接受一個字、`Tab` 循環候選、`Ctrl+X` 本 session 關閉（README〈Key Bindings〉）。
- 有 `zsh-autosuggestions` 已載入時，deja 印一行提示後**自己退出不運作**，不會兩個並存
  （[`internal/shell/zsh.sh` L161–172](https://github.com/Giammarco-Ferranti/deja/blob/529b4b62aa26aa55642cea4091a0e0e8efda095b/internal/shell/zsh.sh#L161-L172)）。

### 要注意的 Tab 行為

Tab 預設綁給 deja 的候選循環。游標在行尾而且畫面上有 ghost 時，Tab **不會**跑原本的補全：
有多個候選就切換，只有一個候選就什麼都不做；沒有 ghost 或游標不在行尾才回到 `expand-or-complete`
（[`zsh.sh` L675–707](https://github.com/Giammarco-Ferranti/deja/blob/529b4b62aa26aa55642cea4091a0e0e8efda095b/internal/shell/zsh.sh#L675-L707)）。
我們第 6 段有 `zstyle ':completion:*' menu select`，打到一半按 Tab 想補路徑時會被 ghost 擋住。
README 給的解法是 `export DEJA_CYCLE_KEY='^N'` 把循環移走。

## 2. 怎麼裝、依賴

- Homebrew：`brew install deja`，已進 homebrew-core
  （[Formula/d/deja.rb](https://github.com/Homebrew/homebrew-core/blob/main/Formula/d/deja.rb)，從原始碼 `go build`，`CGO_ENABLED=1`）。
- curl 安裝腳本：抓 GitHub release 的 tar.gz、驗 sha256、放到 `~/.local/bin`，**還會自動 `deja import` 並往 `~/.zshrc` append 啟用區塊**
  （[`install.sh`](https://github.com/Giammarco-Ferranti/deja/blob/529b4b62aa26aa55642cea4091a0e0e8efda095b/install.sh)）。
  我們的 `~/.zshrc` 由 chezmoi 管，append 進去會在下次 apply 被蓋掉 —— 要採用的話只拿 binary，啟用那幾行寫進 `home/dot_zshrc`。
- 也提供 Oh My Zsh／zinit plugin 檔 `deja.plugin.zsh`，但它只是 source 整合腳本，binary 還是要另外裝。
- 執行期依賴：只有 zsh；binary 是 Go + `mattn/go-sqlite3`（cgo）
  （[`go.mod`](https://github.com/Giammarco-Ferranti/deja/blob/529b4b62aa26aa55642cea4091a0e0e8efda095b/go.mod)）。
- 啟動成本：`deja init zsh` 每次要 25–36 ms，README 建議直接 source 快取的 `~/.local/share/deja/init.zsh`，binary 換版時它自己在背景重產。

## 3. 資料存哪、有沒有網路

| 路徑 | 用途 |
|---|---|
| `~/.local/share/deja/deja.db` | SQLite：`commands`（指令、目錄、時間、exit code、耗時、session）、`command_stats`、`sequences` |
| `~/.local/share/deja/sock` | daemon 的 Unix socket |
| `~/.local/share/deja/init.zsh` | 產生的整合腳本 |
| `~/.local/share/deja/config` | fuzzy preset、empty 開關 |

來源：README〈Where data lives〉、[`schema.sql`](https://github.com/Giammarco-Ferranti/deja/blob/529b4b62aa26aa55642cea4091a0e0e8efda095b/internal/store/sqlc/schema.sql)。

- **沒有網路行為**：README 寫「No account. No sync server」「nothing leaves your machine」。
  原始碼裡唯一的 `net` 用法是 `net.Listen("unix", …)`／`net.DialTimeout("unix", …)`
  （[`internal/daemon/server.go` L43、L104](https://github.com/Giammarco-Ferranti/deja/blob/529b4b62aa26aa55642cea4091a0e0e8efda095b/internal/daemon/server.go#L43)），沒有 `net/http`。
  Homebrew formula 也有 `deny_network_access!`。
- **明文存放**：資料夾 0700、db 0600，但不加密（README〈Security〉）。
- 尊重 `HIST_IGNORE_SPACE`：空格開頭的指令 deja 不記（不管有沒有 setopt 都不記），也套用 `HISTORY_IGNORE`（README〈Privacy〉）。我們第 4 段已開 `HIST_IGNORE_SPACE`，行為一致。
- 已知未修：daemon 連不上、退回 subprocess 時，指令內容會放在 argv，`/proc/<pid>/cmdline` 其他帳號看得到
  （[issue #105](https://github.com/Giammarco-Ferranti/deja/issues/105)，open）。單人機器影響小。
- `deja import` 匯入的舊歷史 `Directory` 是空字串
  （[`cmd/deja/import.go` L60](https://github.com/Giammarco-Ferranti/deja/blob/529b4b62aa26aa55642cea4091a0e0e8efda095b/cmd/deja/import.go#L60)），
  所以「依目錄加權」只對裝了之後跑的指令有效。

## 4. 維護狀態

- 884 star、16 fork、13 個 open issue；repo 2026-04-07 建立，最近 commit 2026-10-02（`Dev (#123)`，尚未 release）。
- release 節奏：v0.3.1（2026-06-09）→ v0.4.2（2026-09-07），release-please 自動化。
- 貢獻者：作者 46 commits，其他人 10、6、1（`gh api repos/Giammarco-Ferranti/deja/contributors`）。實質上一人專案。
- 仍是 0.x，近兩個月還在修會讓終端卡住或誤殺 process 的 bug（#101 zinit update 卡住、#108 `--restart` 可能 SIGTERM 不相干的 process、#100 `zmodload zsh/stat` 蓋掉 `/usr/bin/stat`），都已關。
- 只支援 zsh（bash 支援是 open 的 [#121](https://github.com/Giammarco-Ferranti/deja/issues/121)）。

## 5. 原生 Termux 能不能跑

**官方 binary 不行。** release 只出 darwin／linux × amd64／arm64，linux 版用 `aarch64-linux-gnu-gcc` 以 `CGO_ENABLED=1` 編
（[`.goreleaser.yaml` L14–45](https://github.com/Giammarco-Ferranti/deja/blob/529b4b62aa26aa55642cea4091a0e0e8efda095b/.goreleaser.yaml#L14-L45)）。
下載 v0.4.2 `linux_arm64` 看 ELF（沒執行）：

```
$ file deja
ELF 64-bit LSB executable, ARM aarch64, dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, for GNU/Linux 3.7.0
$ readelf -d deja | grep NEEDED
Shared library: [libc.so.6]
Shared library: [ld-linux-aarch64.so.1]
```

原生 Termux 是 Bionic libc，沒有 `/lib/ld-linux-aarch64.so.1`，這支 binary 起不來。
termux-packages 裡也沒有 deja（`packages/deja` 404）。

剩下的路是在 Termux 裡 `pkg install golang clang` 後 `go build ./cmd/deja`。
Linux 專屬檔 `stdio_linux.go` 用 `//go:build linux`，Go 的 `android` 會滿足 `linux` build tag；`mattn/go-sqlite3` 需要 cgo + clang。
**這條沒實測**，要採用得先在 Termux 容器（`script/tests/e2e.sh termux`）裡編一次確認。
另外 `install.sh` 在 Termux 上會依 `uname -s`=Linux 去下載 glibc 版，裝得進去但跑不起來，不能用。

## 6. 跟 fzf Ctrl-R、atuin 是不是同一類

不是。三種東西各解決不同時刻：

| 工具 | 什麼時候用 | 介面 | 資料 |
|---|---|---|---|
| zsh-autosuggestions／deja | 打字當下，自動 | 行內 ghost text | 前者讀 zsh history；deja 另存 SQLite |
| fzf Ctrl-R | 主動按鍵搜尋 | 全螢幕／下拉模糊搜尋清單 | 讀 zsh history，不另存 |
| atuin | 主動按 Ctrl-R／↑ 搜尋 | 全螢幕 TUI | 取代成 SQLite，可選端對端加密同步 |

- zsh-autosuggestions 的 `history` 策略：「Chooses the most recent match from history」，就是前綴比對取最近一筆
  （[README〈Suggestion Strategy〉](https://github.com/zsh-users/zsh-autosuggestions#suggestion-strategy)）。
  它也有 `match_prev_cmd` 策略（看上一個指令），算是 deja「序列預測」的簡化版，我們沒開。
- fzf：「`CTRL-R` - Paste the selected command from history onto the command-line」（[fzf README](https://github.com/junegunn/fzf#key-bindings-for-command-line)）。
- atuin：「replaces your existing shell history with a SQLite database」、「rebind `ctrl-r` and `up` … to a full screen history search UI」、可選 encrypted sync
  （[atuin README](https://github.com/atuinsh/atuin)）。

deja 和 fzf Ctrl-R／atuin **可以並存**，按鍵不衝突（deja 不綁 Ctrl-R）；
它只跟 zsh-autosuggestions 互斥。deja 也有人提 atuin 整合（[#98](https://github.com/Giammarco-Ferranti/deja/issues/98)，open）。

## 7. 對 map #104 的意義

- 採用 deja = 刪掉 `home/.chezmoiexternal.toml.tmpl` 的 zsh-autosuggestions 和 `home/dot_zshrc` 第 6 段那兩行，換成 deja 的啟用區塊；第 4 段不動。
- 要多維護：一支 binary 的安裝管道（`packages.yaml` 沒有 apt 套件，要走 GitHub release 或 brew）、Termux 的自編流程、Tab 鍵與 `menu select` 的取捨、一個常駐 daemon。
- 跟「fzf 要不要採用」是兩件獨立的事；唯一要對齊的是 Tab：fzf 的 `**<Tab>` 補全也吃 Tab，deja 擋在前面時一樣會被吃掉。
