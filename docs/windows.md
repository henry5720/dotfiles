# Windows 主機

原生 Windows 由 Windows 原生 chezmoi 管，跟 Linux 用同一個 repo。可以是 WSL 的外層，也可以沒有 WSL、
Windows 本身就是開發機。怎麼裝見[新機器設定](new-machine-setup.md#windows-主機)。

## 部署什麼

`chezmoi init` 跟其他 OS 一樣問用途、出選裝工具選單（見[用途與憑證](machine-use.md)）；勾到要憑證的工具才問憑證，
git 身分不問（Windows 不部署 `.gitconfig`）。部署的檔案只有 `home/.chezmoiignore` Windows 段白名單上的：

| repo 裡的檔案 | 部署到 | 用途 |
|---|---|---|
| `home/dot_wslconfig` | `%USERPROFILE%\.wslconfig` | WSL2 的記憶體、CPU、網路模式 |
| `home/dot_config/starship.toml` | `%USERPROFILE%\.config\starship.toml` | starship 提示列，跟 Linux 共用 |
| `home/dot_config/mise/conf.d/dotfiles.toml.tmpl` | `%USERPROFILE%\.config\mise\conf.d\dotfiles.toml` | 交給 mise 裝的 CLI 清單（zoxide 加上勾了的） |
| `home/dot_local/bin/tools.ps1.tmpl` | `%USERPROFILE%\.local\bin\tools.ps1` | `tools` 指令：重選用途與選裝工具，勾完直接裝 |
| `home/Documents/PowerShell/Profile.ps1.tmpl` | `Documents\PowerShell\Profile.ps1` | pwsh 7 的 all-hosts profile |
| `home/Documents/WindowsPowerShell/Profile.ps1.tmpl` | `Documents\WindowsPowerShell\Profile.ps1` | Windows PowerShell 5.1 的 all-hosts profile |
| `home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/modify_settings.json` | `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`（Store 版 Windows Terminal） | 只改兩個值：預設設定檔是 pwsh 7、預設字型是 Hack Nerd Font；其餘照 Terminal 自己寫的保留，兩個值都對時一個 byte 都不動 |

apply 時跑的腳本只有 `home/.chezmoiscripts/` 裡的 `.ps1`（sh 腳本不會到 Windows）：

```text
before  install-packages-windows.ps1   winget 裝 mise、pwsh 7、Windows Terminal，勾了 tailscale 也裝（已經裝了就跳過）
（部署上面的檔案）
after   install-mise.ps1               mise install：裝 dotfiles.toml 清單上的 CLI
after   zz-env-skipped.ps1             勾了 Windows 裝不了的工具時，列出略過了哪些、為什麼
```

腳本一律用 Windows PowerShell 5.1 跑、只對那個 process 繞過執行原則（`.chezmoi.toml.tmpl` 的 `[interpreters.ps1]`）：
第一次 init 時 pwsh 7 多半還沒裝，Windows client 的 5.1 預設執行原則又是 `Restricted`。裝失敗（winget、mise）只印一行、
apply 照樣跑完，照印出的指令自己補。

兩份 `Profile.ps1` 內容一樣，做的事見[裝了什麼、怎麼用](#裝了什麼怎麼用)。
chezmoi 不碰 `$PROFILE`（`Microsoft.PowerShell_profile.ps1`），機器專屬的設定（例如 API key）寫在那裡，不進 repo。
PowerShell 只從 `[Environment]::GetFolderPath('MyDocuments')` 讀 profile，Documents 在 OneDrive 裡時讀不到
chezmoi 部署的這兩份，見[Documents 移出 OneDrive](#documents-移出-onedrive)。

Terminal 的 `settings.json` 兩個值有一個不對時，那次 apply 會經過 `toPrettyJson` 整份重寫：Terminal 原本的
`//` 註解會消失、key 照字母重排。之後兩個值都對就不再動它。所以第一次 `chezmoi diff` 看到整檔重排是預期的，不是壞掉。

## 裝了什麼、怎麼用

CLI 用 mise 裝（跟 Linux 共用 `home/.chezmoidata/packages.yaml` 的 `miseTools`），app 用 winget 裝：

| 工具 | 怎麼裝 | 什麼時候裝 | 常用 |
|---|---|---|---|
| chezmoi | winget（Runbook 手動） | 裝機時 | `chezmoi update` 拿 repo 最新的設定；`chezmoi diff` 沒有輸出就是跟 repo 一致 |
| pwsh（PowerShell 7） | winget | 每台 | 主力 shell，Windows Terminal 預設開它；`powershell`（5.1）讀同一份 profile，用起來一樣 |
| Windows Terminal | winget（Win11 內建就跳過） | 每台 | |
| mise | winget | 每台 | `mise ls` 看裝了什麼；`mise install` 補裝失敗的 |
| zoxide | mise | 每台 | 跳常去的目錄：`z <目錄名片段>`。等於 Linux 上 zsh 外掛的跳目錄，Windows 的 shell 一定是 PowerShell，不用勾 |
| starship、fastfetch、eza、fzf、bat、ripgrep、vim | mise | 精簡、完整 | starship 是提示列（跟 Linux 同一份設定）；fastfetch 在互動開的 shell 印系統資訊，`pwsh -c`、ssh 執行指令不印 |
| gh、cloudflared、ttyd、ffmpeg | mise | 完整或自己勾 | |
| tailscale | winget | 完整或自己勾 | 官方 app，裝完自己開 app 登入；會跳 UAC |

zsh、btop、code-server、herdr、coding agent（claude、codex、opencode）、node、codegraph、wakatime、headless-chrome、
playwright-cli、agent-config 在 Windows 標裝不了（原因寫在選單上，`home/.chezmoitemplates/tool-env`），要用就到 WSL 裝。
勾了也不會中斷 apply，最後列出略過了哪些。

要加減工具打 `tools`（PowerShell 版，做的事跟 Linux 一樣：重問用途、重出選單、勾完直接 apply）；取消勾選不會解除安裝，
移除用 `mise uninstall <工具>` 或 `winget uninstall --id <id>`。

PowerShell 內建的 PSReadLine 給的，不用設：

| 功能 | 怎麼用 |
|---|---|
| 語法高亮 | 打字時指令、參數、字串各有顏色 |
| 補全 | `Tab` 出選單、方向鍵選（這項是 profile 改的，預設是一個一個換） |
| 灰字建議（只有 pwsh 7） | 打字時從歷史紀錄冒出灰字，`→` 接受 |
| 歷史紀錄 | 跨視窗保存；`↑` 翻、`Ctrl+R` 搜尋 |

profile 把 mise 的 shims（`%LOCALAPPDATA%\mise\shims`）和 `$HOME\.local\bin` 加進 PATH 最前面：mise 裝的工具和 `tools`
直接打名字就能跑，以前 winget 裝的同名舊版不會先被找到（不再需要就 `winget uninstall` 掉）。

## Documents 移出 OneDrive

PowerShell 從 `[Environment]::GetFolderPath('MyDocuments')` 讀 profile，chezmoi 卻固定部署到 `$HOME\Documents`。
Documents 被 OneDrive 備份時這兩個路徑不同：apply 照樣成功、也不報錯，但 PowerShell 根本不讀 chezmoi 部署的 profile。

照 Microsoft [about_Profiles](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles)
的建議，在 OneDrive 設定 →「同步與備份」→「管理備份」→ 關掉「文件」。關掉後原本的檔案留在 OneDrive，
要的自己搬回 `$HOME\Documents`。確認：

```powershell
[Environment]::GetFolderPath('MyDocuments')   # 要是 C:\Users\<你>\Documents，不是 ...\OneDrive\...
```

只刪掉 OneDrive 裡的檔案、或解除安裝 OneDrive，Documents 的位置都不會變（henry-desktop 實測），一定要在「管理備份」關掉。
OneDrive 也沒辦法只排除 `PowerShell` 一個資料夾：「選擇資料夾」是決定雲端哪些資料夾下載到這台，取消勾選等於刪掉本機那份。

## 從舊的手寫 profile 遷移

chezmoi 只部署 all-hosts 的 `Profile.ps1`；`$PROFILE` 比它晚載入，裡面若有 oh-my-posh（例如 henry-desktop 那份）
會蓋掉 starship。先看內容，機器專屬的設定（例如 API key）留下，其他刪掉；整份都不要就刪檔：

```powershell
notepad $PROFILE            # 看內容、只留機器專屬的設定
Remove-Item $PROFILE        # 整份都不要時
```

pwsh 和 `powershell`（5.1）的 `$PROFILE` 是不同檔案，兩邊都要看。

## WSL 網路：mirrored 與 NAT portproxy

### mirrored 模式（目前預設）

優先使用 `networkingMode=mirrored`；Windows 與 WSL 共用 localhost，不要同時套用下方 NAT
portproxy。設定來源：[`home/dot_wslconfig`](../home/dot_wslconfig)。

### NAT fallback：查詢實際 WSL IPv4 後再轉發

只有把 `.wslconfig` 改回 NAT 時才用。不要直接取 `hostname -I` 第一個值；多介面時請看
`ip -4 addr`，確認可達的 WSL IPv4 後人工填入 `<WSL_NAT_IP>`。
NAT 下 WSL 服務也必須監聽可達的 NAT 介面地址，不能只綁 `127.0.0.1`；改成對外監聽時注意暴露風險。

```bash
ip -4 addr
```

在**系統管理員 PowerShell** 執行；`127.0.0.1` 只讓 Windows 本機聽，若要讓 LAN 存取才
明確改成指定的 Windows listen address，並另行確認防火牆：

```powershell
netsh interface portproxy show all
$wslIp = "<WSL_NAT_IP>"
netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=3000 connectaddress=$wslIp connectport=3000
```

先確認同一 listen address/port 沒有既有規則；要更換時先依下方指令刪除舊規則，再新增。

#### 先檢查既有 rule

```powershell
netsh interface portproxy show all
```

#### 刪除單條（listenaddress/port 要和既有 rule 完全一致）

```powershell
netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=3000
```

#### 清空全部（確認 show all 後才做）

```powershell
netsh interface portproxy reset
```
