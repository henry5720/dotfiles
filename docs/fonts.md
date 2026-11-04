# 終端機字型

字型裝在**你看畫面的那台**，跟 shell 跑在哪台無關：SSH 進雲端主機、開 WSL，畫面都是你面前那個終端機畫的。
預設用 [Hack Nerd Font](https://www.nerdfonts.com/font-downloads)；沒裝也能用，只是提示列和 `ll` 的圖示變成方框或問號。

```text
你看畫面用的是
├─ Windows Terminal（WSL、ssh）── 字型裝在 Windows（下面「Windows Terminal」）
├─ 瀏覽器（code-server、TeamSync 工作區、share-shell）── 字型裝在開瀏覽器那台
├─ macOS 的終端機 ── brew 裝
├─ Linux 桌面的終端機 ── 放進 ~/.local/share/fonts
└─ 原生 Termux ── chezmoi 自動放好，不用做事
```

## 為什麼要 Nerd Font

starship 提示列（`~/.config/starship.toml`）和 eza（`ll`、`lt`）用 Nerd Font v3 的圖示：OS 標誌、資料夾、git 分支。
一般字型沒有這些字，所以畫成方框。[Nerd Fonts](https://www.nerdfonts.com/) 是把這些圖示補進常見等寬字型的版本，
任何一套 Nerd Font v3 都行，這個 repo 統一用 Hack。

同一套字型會有三種字寬，終端機用第一種：

| 檔名 | 用途 |
|---|---|
| `HackNerdFont-*` | 終端機用這個：圖示比較大，可以超出一格 |
| `HackNerdFontMono-*` | 圖示縮成剛好一格，比較小 |
| `HackNerdFontPropo-*` | 比例字寬，給一般文件，終端機不能用 |

## 各終端機怎麼裝

### Windows Terminal

每台 Windows 做一次：

1. 下載 nerd-fonts v3.5.1 的
   [`Hack.zip`](https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Hack.zip)，解壓縮。
2. 在 `HackNerdFont-Regular.ttf` 按右鍵 →「安裝」。要粗體、斜體也正常，就把
   `HackNerdFont-Bold`、`-Italic`、`-BoldItalic` 一起裝。
3. Windows Terminal：設定 → 設定檔「預設值」→ 外觀 → 字體，選 `Hack Nerd Font` → 儲存。
   只想改 Ubuntu 那個設定檔就改在它底下。
4. 開一個新的 WSL 分頁，提示列的圖示應該正常顯示。

### 瀏覽器裡的終端機

在開瀏覽器那台裝好 Hack Nerd Font（Windows 照上面裝），再讓網頁用它：

- code-server、TeamSync 工作區：到 `chrome://settings/fonts` 把「固定寬度字型」改成 `Hack Nerd Font`，重新整理頁面。
- `share-shell` 開給別人看的頁面：照 `Hack`、`Hack Nerd Font`、`Menlo`、`Consolas` 的順序找對方裝了哪個，
  都沒有就用瀏覽器預設的等寬字型，只有圖示變方框。

### macOS

```bash
brew install --cask font-hack-nerd-font
```

再到終端機（Terminal、iTerm2）的設定把字型換成 `Hack Nerd Font`。

### Linux 桌面

```bash
mkdir -p ~/.local/share/fonts
curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Hack.tar.xz \
  | tar -xJ -C ~/.local/share/fonts
fc-cache -f
```

再到終端機的設定選 `Hack Nerd Font`。

### 原生 Termux

chezmoi apply 時把 `HackNerdFont-Regular.ttf` 放到 `~/.termux/font.ttf`，並重新載入 Termux 設定，不用做事。
不要裝 Termux:Styling：它換字型會蓋掉這個檔。要換字型改 `home/.chezmoiexternal.toml.tmpl` 第 2 段的 `url`、`path`，
同時改 `run_onchange_after_termux-reload-settings.sh.tmpl` 註解裡的 URL，讓它重新載入。

## 中文

Hack 沒有中文字。終端機遇到字型裡沒有的字，會向系統的其他字型借：Windows Terminal、瀏覽器、macOS、
Linux 桌面的終端機都這樣，所以中文本來就顯示得出來，不用另外裝。

借來的中文字形跟 Hack 不搭、寬度看起來不整齊時，有兩種改法：

- **換一套含中文的 Nerd Font**，中英文出自同一套設計：
  - [Maple Mono](https://github.com/subframe7536/maple-font) 的 `NF CN` 版：Nerd Font 圖示加中日文字，
    設計成中文剛好兩個英文字寬。macOS：`brew install --cask font-maple-mono-nf-cn`
  - [更紗黑體](https://github.com/be5invis/Sarasa-Gothic)（Sarasa Gothic）有繁中（TC）字形；
    補上 Nerd Font 圖示的版本由社群打包：[Sarasa Gothic Nerd Fonts](https://github.com/jonz94/Sarasa-Gothic-Nerd-Fonts)
    （`Sarasa Mono TC Nerd Font`）
- **只換中文那部分**：Windows Terminal 1.21 起，字型欄可以用逗號列多個字型，前一個缺的字往後找
  （[發布說明](https://devblogs.microsoft.com/commandline/windows-terminal-preview-1-21-release/)），例如 `Hack Nerd Font, Sarasa Mono TC`。
  其他終端機看它自己的文件有沒有「備用字型」設定。

兩套都是 SIL Open Font License，個人、商業都能用。

## 換別的英文字型

- [Nerd Fonts 下載頁](https://www.nerdfonts.com/font-downloads)：每一套都有預覽，下載後照上面的方法裝。
- [Google Fonts](https://fonts.google.com/)：上面的等寬字型（JetBrains Mono、Fira Code、Roboto Mono…）大多沒有圖示，
  先到 Nerd Fonts 下載頁找有沒有補好圖示的版本。
- 喜歡的字型沒有 Nerd Font 版本：裝 Nerd Fonts 的 `Symbols Nerd Font`（只有圖示）當備用字型，
  原本的字型照用（[官方說明](https://github.com/ryanoasis/nerd-fonts/wiki/Font-Substitution-&-Fallback)）。

## Helvetica 呢

Helvetica 不能當終端機字型：它是比例字型（`i` 比 `m` 窄），終端機每一格寬度固定，欄位會對不齊。
它也要付費授權，Windows、Linux 沒有內建。

終端機以外的地方（瀏覽器、編輯器的介面、文件）想要 Helvetica 的感覺，用免費的替代：

- [Inter](https://fonts.google.com/specimen/Inter)：Google Fonts 上最常被拿來替代的，為螢幕設計。
- Nimbus Sans：URW 做的 Helvetica 復刻，字形和字距最接近。Ubuntu 的 `fonts-urw-base35` 套件裡就有。

中文搭配可以用 Google Fonts 的 [Noto Sans TC](https://fonts.google.com/noto/specimen/Noto+Sans+TC)。
