{{- /* Windows 的 all-hosts PowerShell profile。pwsh 7(Documents/PowerShell)與 5.1(Documents/WindowsPowerShell)
       兩個 target 都只有呼叫這個 template 的一行,內容只寫在這裡(#254)。
       只管 Profile.ps1,不碰 $PROFILE(Microsoft.PowerShell_profile.ps1):機器專屬的設定留在那裡手寫。

       渲染出來的內容只用 ASCII:5.1 讀沒有 BOM 的檔案時用系統 ANSI 字碼頁,UTF-8 的中文會變亂碼。
       所以說明都寫在這種樣板註解裡,渲染時會拿掉。

       1. $HOME\.local\bin 加進 PATH(已經有就不重複加)
       2. Tab 用選單補全,跟 zsh 的 menu select 一樣(PSReadLine 預設是 TabCompleteNext,一個一個換);
          沒有 PSReadLine 的 host(例如 ISE)略過。
          灰字建議不設:pwsh 7.6 的 PSReadLine 預設就開(HistoryAndPlugin);5.1 的 2.0 沒有這個參數;
          而且輸出被導向(ssh 非互動、pwsh -c)時設它會丟例外,中斷整份 profile
       3. fastfetch 有裝、而且是互動開 shell 才跑,跟 zsh 一樣。profile 連 pwsh -c、-File、
          -EncodedCommand、-NonInteractive、輸出被導向都會載入,這些情況不跑,免得每個指令的輸出前面
          多一張系統資訊。參數可以縮寫(-c、-f、-noni),所以用「是不是這些參數名的開頭」判斷;
          -ec 是 -EncodedCommand 的別名。不帶 -File、直接 `pwsh script.ps1` 的寫法判斷不到
       4. starship 有裝才 init,設定讀 ~/.config/starship.toml(跟 Linux 共用)
       5. zoxide 有裝才 init(z 指令)
       fastfetch、starship、zoxide 沒裝時安靜略過。 */ -}}
$localBin = "$HOME\.local\bin"
if (($env:PATH -split ';') -notcontains $localBin) {
    $env:PATH = "$localBin;$env:PATH"
}

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

$scriptedArgs = 'command', 'file', 'encodedcommand', 'ec', 'noninteractive'
$scripted = [Environment]::GetCommandLineArgs() | Select-Object -Skip 1 | Where-Object {
    $arg = $_.TrimStart('-', '/').ToLowerInvariant()
    ($_ -match '^[-/]') -and $arg -and ($scriptedArgs | Where-Object { $_.StartsWith($arg) })
}
if (-not $scripted -and -not [Console]::IsOutputRedirected -and (Get-Command fastfetch -ErrorAction SilentlyContinue)) {
    fastfetch
}
Remove-Variable scriptedArgs, scripted

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
