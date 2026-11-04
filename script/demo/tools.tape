# docs/tools.md 裡各工具旁邊的截圖(script/demo/record.sh 錄,在 main.tape 之後、同一台機器)
# 每張先清畫面,一張只示範一個工具:
#   bat.png  bat 看檔:語法上色、檔頭
#   fzf.png  Ctrl-R 開 fzf 歷史面板,打 bat 篩選
Output tools.gif
Set Shell bash
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 18
Set Width 1200
Set Height 600
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms

# 暖機同 main.tape;fzf 面板要的歷史在這裡寫
Hide
Type "echo ll > ~/.zsh_history && echo 'bat README.md' >> ~/.zsh_history" Enter
Type `echo "rg -n 'alias ll' home/dot_zshrc" >> ~/.zsh_history && echo 'cd ~/.local/share/chezmoi' >> ~/.zsh_history` Enter
Type "cd ~/.local/share/chezmoi && exec zsh" Enter
Sleep 8s
Ctrl+L
Sleep 500ms
Show

# 1. bat.png:印整個短檔、不用 -r 行號,被印的檔改了也不會截錯位置(sh-skip 沒有副檔名,-l sh 指定語法)
Type "bat -l sh home/.chezmoitemplates/sh-skip" Enter
Sleep 1s
Screenshot bat.png

# 2. fzf.png:清空再開 Ctrl-R
Ctrl+L
Ctrl+R
Sleep 800ms
Type "bat"
Sleep 1s
Screenshot fzf.png
Escape
Sleep 500ms
Sleep 1s
