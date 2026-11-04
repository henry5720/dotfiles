# Windows 主機

WSL 外面那層 Windows 由 Windows 原生 chezmoi 管，跟 Linux 用同一個 repo。怎麼裝見
[新機器設定](new-machine-setup.md#windows-主機)。

## 部署什麼

Windows 的 `chezmoi init` 什麼都不問（沒有用途、選裝工具選單、憑證、git 身分），只部署白名單上的檔案：

| repo 裡的檔案 | 部署到 | 用途 |
|---|---|---|
| `home/dot_wslconfig` | `%USERPROFILE%\.wslconfig` | WSL2 的記憶體、CPU、網路模式 |
| `home/dot_config/starship.toml` | `%USERPROFILE%\.config\starship.toml` | starship 提示列，跟 Linux 共用 |

`.chezmoiscripts/` 裡的 `run_` 腳本一支都不跑（都是 sh、python3）。Windows 沒有 `tools` 指令；
要改 Windows 部署什麼就改 repo：白名單在 `home/.chezmoiignore` 的 Windows 段，加一個檔案要動哪幾處寫在那段的註解。

## 實機清單

改到 Windows 會部署的檔案後，在 Windows 主機的 PowerShell 跑。Linux 上的 unittest
（`script/tests/test_windows.py`）只驗得到「部署哪些檔、渲染出什麼」，下面這些要實機才知道。

| # | 什麼時候跑 | 指令 | 預期結果 |
|---|---|---|---|
| 1 | 每次 | `chezmoi apply` 之後 `chezmoi diff` | 沒有輸出 |
| 6 | 改到 `.wslconfig` 時 | `wsl --shutdown`，重開 WSL 後在 WSL 裡跑 `free -g`、`nproc`、`ip -4 addr` | 記憶體上限、CPU 數跟 `.wslconfig` 一致；`networkingMode=mirrored` 時 WSL 的網卡跟 Windows 同一個 IP |

編號照 [spec #254](https://github.com/henry5720/dotfiles/issues/254) 的實機清單；2～5 項（PowerShell profile、
Windows Terminal）等那兩樣交給 chezmoi 時補上。

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
