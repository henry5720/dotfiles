# PROTOTYPE — README 主 GIF 劇本（丟棄式，不 merge）

回答 [寫 README 主 GIF 的 tape 劇本](https://github.com/henry5720/dotfiles/issues/131)。

- `main.tape`：草稿 A（暖機歷史寫錯，autosuggestion 沒出現、還洩漏暖機指令）→ `main-a.gif`
- `main-b.tape`：草稿 B（修好暖機）→ `main-b.gif`，14 秒、197 KB、1200×700
- `main-c.tape`：草稿 C（Q1–Q5 定案版：`ll` 示範 autosuggestion、1200×600）→ `main-c.gif`，14.2 秒、257 KB
- `record.sh`：借 `script/tests/e2e.sh` 的 `setup_ubuntu`／`make_fixtures`／`bootstrap` 跑到 `init --apply`，補 vhs 0.12.1、ttyd、ffmpeg、Hack Nerd Font，裝 `fastfetch.jsonc` 後錄
- 用法：`bash demo-prototype/record.sh main-b.tape`（`REUSE=1` 沿用已建好的容器 `dotfiles-demo-proto`）
