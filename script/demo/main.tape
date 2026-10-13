# README 開頭的主 GIF(script/demo/record.sh 錄,在選單 GIF 裝完的同一台機器)
# 畫面:p10k 進 git repo → 語法上色與 autosuggestion → eza 列表 → fastfetch 收尾
Output main.gif
Set Shell bash
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 18
Set Width 1200
Set Height 600
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms

# 暖機:Set Shell zsh 不讀 rc,所以從 bash 起、exec zsh;cd 回家目錄(vhs 在 ~/demo 跑)。
# 給 autosuggestion 的歷史要在 bash 階段用 echo 寫好:zsh 裡跑的任何指令都會變成建議跳出來;
# 不用 printf '...\n',VHS 會把 \n 照字面打進去。
Hide
Type "echo ll > ~/.zsh_history && cd && exec zsh" Enter
Sleep 8s
Ctrl+L
Sleep 500ms
Show

# 1. p10k:家目錄 → 進 git repo,prompt 長出分支
Sleep 1s
Type "cd ~/.local/share/chezmoi" Sleep 300ms Enter
Sleep 1.5s

# 2. 語法上色(打錯紅、改對綠)+ autosuggestion(灰字 ll)→ eza 列表
Type "sl" Sleep 700ms
Backspace 2 Sleep 200ms
Type "l" Sleep 1.2s
Right Sleep 400ms Enter
Sleep 2.5s

# 3. fastfetch 收尾,GIF 停在這個畫面重播
Ctrl+L
Type "fastfetch" Sleep 200ms Enter
Sleep 4s
