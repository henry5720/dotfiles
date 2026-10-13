# PROTOTYPE — README 主 GIF 劇本草稿 C（#131 Q1–Q5 定案版）
Output main-c.gif
Set Shell bash
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 18
Set Width 1200
Set Height 600
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms

# 暖機：bash 階段寫好給 autosuggestion 的歷史，zsh 裡不跑任何指令
Hide
Type "echo ll > ~/.zsh_history && exec zsh" Enter
Sleep 8s
Ctrl+L
Sleep 500ms
Show

# 1. p10k：家目錄 → 進 git repo，prompt 長出分支
Sleep 1s
Type "cd ~/.local/share/chezmoi" Sleep 300ms Enter
Sleep 1.5s

# 2. 語法上色（打錯紅、改對綠）+ autosuggestion（灰字 ll）→ eza 列表
Type "sl" Sleep 700ms
Backspace 2 Sleep 200ms
Type "l" Sleep 1.2s
Right Sleep 400ms Enter
Sleep 2.5s

# 3. fastfetch 收尾
Ctrl+L
Type "fastfetch" Sleep 200ms Enter
Sleep 4s
