# 裝法照工具的種類分，不照 OS 分；Windows 主機也完整支援 coding agent

一個選裝工具在一個環境用哪個管道裝（裝法，見 `GLOSSARY.md`），看的是工具的種類：

| 工具的種類 | 裝法 | 例子 |
|---|---|---|
| 廠商有自己的 installer，而且會自己更新 | 官方 installer（Linux、macOS 是 `install.sh`，Windows 是 `install.ps1`） | claude、codex；Linux、macOS 的 herdr |
| GitHub release 的單一執行檔 | mise | eza、fzf、bat、ripgrep、starship、gh；Windows 的 herdr |
| 要動系統的：服務、GUI app、函式庫多的 | 系統的套件管理員（apt、winget） | tailscale、Windows Terminal；有 root 的 Linux 上的 vim、ffmpeg |
| 例外 | Termux 一律 pkg、macOS 一律 brew | |

Windows 主機和 WSL 都要能完整使用 coding agent，用哪一邊由那台的選單決定（2026-11-19 的 grilling，#311）。
所以 claude、codex 在 Windows 不再標裝不了：照上表走官方 `install.ps1`，跟 Linux 同一個理由（#233：官方 installer 會自己更新）。
同一台電腦上的 Windows 和 WSL 是兩台機器，各有自己的 `~/.claude`、登入與對話紀錄，不共用；
skill、MCP、指令檔由 skillshare 在兩邊各自同步，指令檔在 Windows 沒開 Developer Mode 時是複製不是連結。

「這個工具在這個環境走哪個裝法」要收進一張表，腳本只照表跑；表上沒有裝法的環境就是裝不了，
`tool-env` 只留「不建議」和需要解釋給人看的原因。在那之前，Windows 的特例（node、herdr）還寫在 `mise-tools` 樣板裡。

## Considered Options

| 做法 | 結果 | 為什麼 |
|---|---|---|
| mise 只給沒有 root 的機器，其他走 OS 的套件管理員 | 不選 | #231 改掉的就是這個：Ubuntu 24.04 的 apt 沒有 starship、fastfetch，fzf 0.44 沒有 `fzf --zsh`；照 apt 版本挑，同一個工具在不同機器走不同的路 |
| 全部統一用 mise | 不選 | 官方 installer 那批在 Linux 會自己更新（#233），換成 mise 沒有好處；服務和 GUI app mise 裝不了 |
| Windows 的 CLI 全部改用 winget | 不選 | winget 都有這些套件、版本也新，但會變成 Windows 一份、Linux 一份兩份清單；mise 裝在使用者目錄不用管理員權限，winget 的安裝程式會不會跳 UAC 沒驗 |
| Windows 的 claude、codex 走 mise | 不選 | 實測裝得起來（claude 2.1.327、codex 0.170.0），但兩者偵測到不是官方裝法就只提示、不更新；claude 還會一直提示有新版而 `mise upgrade` 沒東西可升（anthropics/claude-code#95103）；codex 的 `codex update` 會報認不出安裝方式 |
| Windows 的 claude、codex 走 winget | 不選 | Claude Code 的 winget 套件預設不自動更新，查的當下落後 9 個小版；Codex 的官方 README 沒有列 winget |
| 照工具的種類分，claude、codex 走官方 `install.ps1` | **選** | Linux 與 Windows 同一個裝法、同一個理由；Anthropic 把 `install.ps1` 標為 Recommended |

## 代價

- **claude、codex 在 Windows 各要一支 `.ps1` 安裝腳本。** 寫的時候要先在實機跑過官方 `install.ps1`：
  這份決定下的時候兩支都還沒在 Windows 實測，也沒驗過在 chezmoi 用的 PowerShell 5.1 底下非互動執行。裝不起來就退回 mise，並回來改這份。
- **herdr 兩邊裝法不同。** Linux、macOS 走官方 installer，Windows 走 mise（#309；herdr 的 README 把 mise 列為裝法之一）。
  已經用官方 installer 裝過 herdr 的 Windows 再勾 herdr 會有兩份。
- **這張分類表沒有官方出處。** chezmoi 官方只示範到「每個 OS 一份套件清單、一支 `run_onchange_` 腳本照清單跑」；
  mise 官方只說 registry 優先用預先編好的執行檔。照種類分是把這兩者和 #231、#233 合起來的說法。
- **Windows 上的 playwright-cli、headless-chrome、code-server、zsh 仍然裝不了。** 「完整支援」指 coding agent 本體、設定、skill、MCP、codegraph、wakatime。
