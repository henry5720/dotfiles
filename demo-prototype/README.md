# PROTOTYPE — README 主 GIF 劇本（丟棄式，不 merge）

回答 [寫 README 主 GIF 的 tape 劇本](https://github.com/henry5720/dotfiles/issues/131)。

- `main.tape`：草稿 A（暖機歷史寫錯，autosuggestion 沒出現、還洩漏暖機指令）→ `main-a.gif`
- `main-b.tape`：草稿 B（修好暖機）→ `main-b.gif`，14 秒、197 KB、1200×700
- `main-c.tape`：草稿 C（Q1–Q5 定案版：`ll` 示範 autosuggestion、1200×600）→ `main-c.gif`，14.2 秒、257 KB
- `record.sh`：借 `script/tests/e2e.sh` 的 `setup_ubuntu`／`make_fixtures`／`bootstrap` 跑到 `init --apply`，補 vhs 0.12.1、ttyd、ffmpeg、Hack Nerd Font，裝 `fastfetch.jsonc` 後錄
- 用法：`bash demo-prototype/record.sh main-b.tape`（`REUSE=1` 沿用已建好的容器 `dotfiles-demo-proto`）

## 選單 GIF

回答 [寫 README 選單 GIF 的 tape 劇本](https://github.com/henry5720/dotfiles/issues/159)。

- `menu.tape`：草稿 A。打 README 那行 `bash <(curl …)`（Hide 裡把 `curl` 換成讀本機 bootstrap.sh）→ 剪掉第 1–4 關 → 選單取消勾 ttyd、wakatime、opencode、document-media、ai-document-media（= e2e 的 `TOOLS_FIRST`）→ 剪掉安裝 → 停在「== 完成」。1200×400
- `menu-a-reuse.gif`：草稿 A 在已裝好的容器重錄（`REUSE=1`），13.4 秒、186 KB；apply 幾乎沒輸出，結尾比全新機器乾淨
- `menu-a-fresh.gif`：草稿 A 在全新容器錄，13.4 秒、286 KB；結尾「完成」上方是 npm 的 update notice 和 tailscale 訊息（整次錄影 343 秒，含 150 秒等選單）
- `peek-800.tape`／`peek-800.gif`／`peek-800-picked.png`：拉高到 800 的對照，選單一樣固定一頁 11 項，只多露出上面的 apt log
- `record-menu.sh`：借 `setup_ubuntu`／`make_fixtures` 建容器但**不跑 bootstrap**；先放假 key、寫好 6 個 promptString 的值（`promptStringOnce` 讀到就不問），補 vhs、ttyd、ffmpeg、Google Chrome（VHS 自己下載的 Chromium 在乾淨容器缺函式庫）、`fonts-noto-cjk`、Hack Nerd Font
- 用法：`bash demo-prototype/record-menu.sh menu.tape`（`REUSE=1` 沿用容器 `dotfiles-demo-menu`；要重出選單先刪掉 `chezmoi.toml` 的 `tools` 那行）

錄的時候踩到的：
- `Wait+Screen` 等選單會逾時（畫面明明有字），改用 Hide 裡固定 `Sleep 150s`；選單會停著等輸入
- `Wait+Line` 讀到的行尾空白被砍掉，等 prompt 要寫 `/\$$/`，不是 `/\$ $/`
- 有 TTY 時 codex 官方 installer 會從 `/dev/tty` 問「Start Codex now? [y/N]」，apply 卡住；錄影先 export `CODEX_NON_INTERACTIVE=1` 繞過。這是 repo 的 bug（e2e 用 `--no-tty` 測不到）
