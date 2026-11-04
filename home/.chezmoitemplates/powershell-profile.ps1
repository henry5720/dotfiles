{{- /* Windows 的 all-hosts PowerShell profile。pwsh 7(Documents/PowerShell)與 5.1(Documents/WindowsPowerShell)
       兩個 target 都只有呼叫這個 template 的一行,內容只寫在這裡(#254)。
       只管 Profile.ps1,不碰 $PROFILE(Microsoft.PowerShell_profile.ps1):機器專屬的設定留在那裡手寫。

       渲染出來的內容只用 ASCII:5.1 讀沒有 BOM 的檔案時用系統 ANSI 字碼頁,UTF-8 的中文會變亂碼。
       所以說明都寫在這種樣板註解裡,渲染時會拿掉。

       1. $HOME\.local\bin 加進 PATH(已經有就不重複加)
       2. Tab 用選單補全,跟 zsh 的 menu select 一樣;沒有 PSReadLine 的 host(例如 ISE)略過
       3. 歷史灰字建議只在 pwsh 7 開:5.1 內建的 PSReadLine 2.0 沒有 -PredictionSource,會出紅字
       4. starship 有裝才 init,設定讀 ~/.config/starship.toml(跟 Linux 共用)
       5. zoxide 有裝才 init(z 指令)
       starship、zoxide 沒裝時安靜略過。 */ -}}
$localBin = "$HOME\.local\bin"
if (($env:PATH -split ';') -notcontains $localBin) {
    $env:PATH = "$localBin;$env:PATH"
}

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Set-PSReadLineOption -PredictionSource History
    }
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
