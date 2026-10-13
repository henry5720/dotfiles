# PROTOTYPE — README 主 GIF 劇本草稿 A
Output main-b.gif
Set Shell bash
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 18
Set Width 1200
Set Height 700
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms

Hide
Type "echo 'git log --oneline -5' > ~/.zsh_history && exec zsh" Enter
Sleep 8s
Ctrl+L
Sleep 500ms
Show

# 1. p10k：家目錄 → 進 git repo，prompt 長出分支
Sleep 1s
Type "cd ~/.local/share/chezmoi" Sleep 300ms Enter
Sleep 1.5s

# 2. 語法上色 + autosuggestion：先打錯字變紅、改對變綠，再出現灰字建議
Type "gti" Sleep 600ms
Backspace 2 Type "it" Sleep 500ms
Type " l" Sleep 1.2s
Right Sleep 400ms Enter
Sleep 1.8s

# 3. fastfetch，停在這畫面
Ctrl+L
Type "fastfetch" Sleep 200ms Enter
Sleep 4s
