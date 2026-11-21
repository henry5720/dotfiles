# Hyper-V：在 Windows 上開一台 Windows VM

在一台 Windows 主機上用 Hyper-V 開 Windows 11 VM，裝好之後跟其他 Windows 主機一樣照[新機器設定](../new-machine-setup.md#windows-主機)走。
步驟是 2026-11-18 在一台 Windows 11 專業版主機上開 VM 時實際走過的；Hyper-V 本身的用法以微軟文件為準：
[Enable Hyper-V on Windows](https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/quick-start/enable-hyper-v)。

```text
先確認主機 → 開 Hyper-V（每台主機一次）→ 建 VM → 裝 Windows → 本機帳號 → 終端機（chezmoi）
```

主機上的指令都在主機的**系統管理員** PowerShell 跑（從別台 `ssh` 進主機也行，Windows 的系統管理員帳號 ssh 進去就有完整權限）。

## 先確認主機

| 條件 | 怎麼看 | 不符合時 |
|---|---|---|
| Windows 專業版、企業版或教育版 | `(Get-CimInstance Win32_OperatingSystem).Caption` | 家用版沒有 Hyper-V |
| CPU 虛擬化有開 | `systeminfo` 的「Hyper-V 需求」幾行都是「是」；顯示「偵測到 Hypervisor」也算（例如 VBS 已經開著） | 進 BIOS 開 Intel VT-x／AMD-V |
| RAM 夠 | 每台 VM 開機就吃掉設定的記憶體（固定記憶體時），主機自己至少留 8 GB | 少開一台，或改動態記憶體 |

## 開 Hyper-V（每台主機一次）

「開啟或關閉 Windows 功能」只勾 **Hyper-V**（底下「Hyper-V 平台」「Hyper-V 管理工具」都勾），確定後重開機。
「虛擬機器平台」「Windows 子系統 Linux 版」是 WSL2 用的，Hyper-V 不需要；沒要用 WSL 就別勾，WSL2 本身也是一台會吃記憶體的 VM。

完成條件：重開機後 `Get-VMSwitch` 看得到 `Default Switch`。

## 建 VM

Windows 11 ISO 從[微軟官方下載頁](https://www.microsoft.com/zh-tw/software-download/windows11)下載「multi-edition ISO」、語言、64-bit。

```powershell
$name = 'vm-1'; $iso = 'C:\ISO\Win11.iso'; $cpu = 4; $ram = 8GB; $disk = 256GB
New-VM -Name $name -Generation 2 -MemoryStartupBytes $ram -Path 'C:\HyperV' `
  -NewVHDPath "C:\HyperV\$name\$name.vhdx" -NewVHDSizeBytes $disk -SwitchName 'Default Switch'
Set-VM -Name $name -ProcessorCount $cpu -AutomaticCheckpointsEnabled $false `
  -AutomaticStartAction Start -AutomaticStopAction ShutDown
Set-VMKeyProtector -VMName $name -NewLocalKeyProtector
Enable-VMTPM -VMName $name
Add-VMDvdDrive -VMName $name -Path $iso
Set-VMFirmware -VMName $name -FirstBootDevice (Get-VMDvdDrive -VMName $name)
Get-VMIntegrationService -VMName $name | ? { $_.Id -like '*6C09BB55-D683-4DA0-8931-C9BF705F6480*' } | Enable-VMIntegrationService
```

- Gen 2＋TPM＋安全開機（Gen 2 預設 MicrosoftWindows 範本）是 Windows 11 的硬性需求。
- 磁碟是動態 VHDX，用多少才佔主機多少；裝完 Windows 加終端機工具約 27 GB。
- `AutomaticCheckpointsEnabled $false`：Windows 用戶端版的 Hyper-V 預設每次開機都建一個檢查點，越積越多。
- `AutomaticStartAction Start`：主機重開機後 VM 自己起來。
- 最後一行開「客體服務介面」，主機才能用 `Copy-VMFile` 傳檔進去（用 Id 找，因為名稱會跟著系統語言變）。

依用途調的選項：

| 選項 | 一般自用 | 無人值守的 GUI 自動化（RPA 這類） |
|---|---|---|
| 記憶體 | 動態（預設） | 固定：`Set-VM -StaticMemory`，跑到一半不會被收回 |
| 解析度 | 預設 | 固定：`Set-VMVideo -HorizontalResolution 1920 -VerticalResolution 1080 -ResolutionType Single`，座標才不會跑掉 |
| 加強工作階段 | 開（預設）：能複製貼上、拖放檔案 | 關：`Set-VMHost -EnableEnhancedSessionMode $false`（整台主機的設定）。加強工作階段走 RDP，最小化或斷線時畫面會停 |

**磁碟大小要在 Windows 安裝程式分割磁碟之前定好。** 裝到一半才 `Resize-VHD` 加大的話，磁碟已經照舊大小分割，
多出來的只會掛在後面當「未配置空間」，得在安裝程式裡把分割區全刪掉重來；裝好之後再擴更麻煩：
Windows 11 在 C 槽後面放修復分割區，擋住 C 槽延伸。

## 裝 Windows

開機要在 "Press any key to boot from CD or DVD..." 那幾秒內按鍵，錯過會停在 UEFI 的 "No operating system was loaded"。
不用盯著畫面，在主機跑這段：重開 VM，同時經 Hyper-V 的虛擬鍵盤連送空白鍵。

```powershell
Stop-VM -Name $name -TurnOff -Force; Start-VM -Name $name
$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='$name'"
$kb = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard
1..24 | % { Invoke-CimMethod -InputObject $kb -MethodName TypeKey -Arguments @{keyCode=[uint32]0x20} | Out-Null; Start-Sleep -Milliseconds 500 }
```

安裝程式裡：產品金鑰選「我沒有產品金鑰」；版本選**專業版**（家用版沒有群組原則與遠端桌面，也擋不住 Windows Update 自動重開機）；
跳出「您似乎已開始升級…」選「否」＝全新安裝；安裝位置選那整塊未配置空間。

授權：每台 VM 各要一份 Windows 授權，零售版金鑰一次只能啟用一台，不能跟主機共用。沒啟用也能用，只是有浮水印、不能改個人化設定。

## 本機帳號（不登入微軟帳號）

OOBE 停在「讓我們新增您的 Microsoft 帳戶」時：

1. 按 Shift+F10 開命令提示字元，**先用滑鼠點一下那個視窗**，再打 `start ms-cxh:localonly` 按 Enter。
   沒點的話焦點還在 OOBE，Enter 會被 OOBE 接走。
2. 出現「建立此電腦的使用者」就建本機帳號，**要設密碼**：Windows 預設不讓空白密碼的帳號從網路登入（遠端桌面、網路共用），
   排程工作也不能設成「不論使用者是否登入都執行」。

2026-11-18 在 build 26300 實測：「登入選項」裡沒有「改為加入網域」、`oobe\bypassnro` 也早就拿掉了，`ms-cxh:localonly` 還能用。
微軟一直在收這些路；新 build 也不行的話，先用臨時的微軟帳號登入，進桌面後建本機系統管理員帳號、改用它登入，再移除微軟帳號。

電腦名稱取跟 VM 一樣（`Rename-Computer -NewName <名稱> -Restart`），主機就能用 `<名稱>.mshome.net` 找到它（見下面「網路」）。

## 終端機（chezmoi）

照[新機器設定〈Windows 主機〉](../new-machine-setup.md#windows-主機)。新裝的 VM 用本機帳號時，沒有 OneDrive、也沒有舊的手寫 profile，那兩步跳過。
先 `winget install --id Git.Git -e`：chezmoi 找不到 git 時會改用內建的 git，clone 得了，但之後自己要用 git 還是得裝。

字型那步在 VM 裡不想點右鍵的話，用指令裝（效果等於右鍵「安裝」，系統管理員 PowerShell 會裝給所有使用者）：

```powershell
$ProgressPreference = "SilentlyContinue"; $d = "$env:TEMP\Hack"
Invoke-WebRequest https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Hack.zip -OutFile "$d.zip"
Expand-Archive "$d.zip" $d -Force
$f = (New-Object -ComObject Shell.Application).Namespace(0x14)
foreach ($n in "Regular","Bold","Italic","BoldItalic") { $f.CopyHere("$d\HackNerdFont-$n.ttf", 0x14) }
```

## 網路

`Default Switch` 是 NAT：

```text
區網 ──✕──→ VM                          區網只看得到主機
VM ──→ 主機（vEthernet (Default Switch)）──NAT，換成主機的區網 IP──→ 區網、網際網路
```

- VM 往外連可以：連區網的檔案分享、上網都行，對方看到的是主機的 IP。
- 區網連不進 VM：要從外面進 VM，經主機跳板，例如 VM 裝好 OpenSSH Server 後 `ssh -J <主機> <帳號>@<名稱>.mshome.net`。
- Default Switch 的網段在主機重開機後可能會變，連 VM 一律用 `<名稱>.mshome.net`，不要寫死 IP。

要改橋接（Hyper-V 叫「外部」虛擬交換器，VM 自己拿一個區網 IP）只有一個理由：區網上別的機器要**直接**連 VM。
代價是要動主機的網卡設定，切換時主機會斷網一下。

## 傳檔案

| 方向 | 怎麼做 | 要什麼 |
|---|---|---|
| 主機 → VM | 主機上 `Copy-VMFile <VM> -SourcePath <主機檔案> -DestinationPath <VM 路徑> -CreateFullPath -FileSource Host`，一次一個檔 | 客體服務介面（上面建 VM 時已開） |
| 雙向 | VM 裝 OpenSSH Server 後經主機跳板 `scp` | VM 的帳密或金鑰 |
| 雙向、常常傳 | 加強工作階段的複製貼上與拖放 | 加強工作階段開著 |

## 從主機用虛擬鍵盤操作 VM（給 agent）

VM 還沒有 ssh、又不能點它的畫面時，只能從主機經 `Msvm_Keyboard` 往 VM 打字（2026-11-18 實測）：

- 字送到 VM 裡**目前有焦點的視窗**；焦點不在終端機時字會不見，或被別的視窗接走。
- `TypeText` 是非同步的，回傳時字還沒打完；之後送的 `TypeKey`（例如 Enter）會排在那些字後面。
- `TypeText` 打不出單引號 `'`（整個被吃掉），雙引號 `"` 可以，打進去的 PowerShell 一律用雙引號。中文打得出來。
- VM 能 ssh 之後就改走 ssh。
