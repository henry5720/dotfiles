# Windows 主機

WSL 外面那層 Windows 由 Windows 原生 chezmoi 管，跟 Linux 用同一個 repo。怎麼裝見
[新機器設定](new-machine-setup.md#windows-主機)。

## 部署什麼

Windows 的 `chezmoi init` 什麼都不問（沒有用途、選裝工具選單、憑證、git 身分），只部署白名單上的檔案：

| repo 裡的檔案 | 部署到 | 用途 |
|---|---|---|
| `home/dot_wslconfig` | `%USERPROFILE%\.wslconfig` | WSL2 的記憶體、CPU、網路模式 |
| `home/dot_config/starship.toml` | `%USERPROFILE%\.config\starship.toml` | starship 提示列，跟 Linux 共用 |
| `home/Documents/PowerShell/Profile.ps1.tmpl` | `Documents\PowerShell\Profile.ps1` | pwsh 7 的 all-hosts profile |
| `home/Documents/WindowsPowerShell/Profile.ps1.tmpl` | `Documents\WindowsPowerShell\Profile.ps1` | Windows PowerShell 5.1 的 all-hosts profile |
| `home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/modify_settings.json` | `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`（Store 版 Windows Terminal） | 只改兩個值：預設設定檔是 pwsh 7、預設字型是 Hack Nerd Font；其餘照 Terminal 自己寫的保留，兩個值都對時一個 byte 都不動 |

兩份 `Profile.ps1` 內容一樣，做的事見[裝了什麼、怎麼用](#裝了什麼怎麼用)。
chezmoi 不碰 `$PROFILE`（`Microsoft.PowerShell_profile.ps1`），機器專屬的設定（例如 API key）寫在那裡，不進 repo。
PowerShell 只從 `[Environment]::GetFolderPath('MyDocuments')` 讀 profile，Documents 在 OneDrive 裡時讀不到
chezmoi 部署的這兩份，見[Documents 移出 OneDrive](#documents-移出-onedrive)。

Windows 沒有 `tools` 指令，要加減什麼就改 repo。

Terminal 的 `settings.json` 兩個值有一個不對時，那次 apply 會經過 `toPrettyJson` 整份重寫：Terminal 原本的
`//` 註解會消失、key 照字母重排。之後兩個值都對就不再動它。所以第一次 `chezmoi diff` 看到整檔重排是預期的，不是壞掉。

## 裝了什麼、怎麼用

[Runbook](new-machine-setup.md#windows-主機) 用 winget 裝的工具，profile 開 shell 時幫你接好：

| 工具 | 做什麼 | 常用 |
|---|---|---|
| chezmoi | 管這些設定檔 | `chezmoi update` 拿 repo 最新的設定；`chezmoi diff` 沒有輸出就是跟 repo 一致 |
| pwsh（PowerShell 7） | 主力 shell，Windows Terminal 預設開它 | `powershell`（5.1）讀同一份 profile，用起來一樣 |
| fastfetch | 開 shell 時印出系統資訊 | 互動開的 shell 才印，`pwsh -c`、ssh 執行指令不印 |
| starship | 提示列：目錄、git 分支與狀態，跟 Linux 同一份設定 | 不用打指令 |
| zoxide | 跳常去的目錄 | `z <目錄名片段>` |

PowerShell 內建的 PSReadLine 給的，不用設：

| 功能 | 怎麼用 |
|---|---|
| 語法高亮 | 打字時指令、參數、字串各有顏色 |
| 補全 | `Tab` 出選單、方向鍵選（這項是 profile 改的，預設是一個一個換） |
| 灰字建議（只有 pwsh 7） | 打字時從歷史紀錄冒出灰字，`→` 接受 |
| 歷史紀錄 | 跨視窗保存；`↑` 翻、`Ctrl+R` 搜尋 |

`$HOME\.local\bin` 也加進 PATH，放在那裡的程式直接打名字就能跑。

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
