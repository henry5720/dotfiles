# README 開頭的 shell 體驗截圖(script/demo/record.sh 錄,在 menu.tape 裝完的同一台機器)
# 每個畫面停住就看得懂,不用看順序,所以截圖、不錄 GIF。截四張:
#   shell.png            p10k 進 git repo 長出分支 → eza 列表 → 打到一半:語法上色 + 灰字 autosuggestion
#   shell-tools.png      bat 看檔 → rg 搜尋
#   shell-fzf.png        Ctrl-R 開 fzf 歷史面板,打 bat 篩選
#   shell-fastfetch.png  fastfetch 印完整資訊(Kernel、CPU、磁碟是錄影那台主機的)
# 用到的 zsh、eza、fzf、bat、ripgrep 是精簡預勾的,fastfetch 是 menu.tape 另外勾的。
# VHS 文件沒寫 tape 沒有 Output 能不能跑,留一個 main.gif 當丟棄檔,record.sh 不拷它。
# 截圖的檔名 record.sh 從下面的 Screenshot 行讀,加一張不用改 record.sh
Output main.gif
Set Shell bash
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 18
Set Width 1200
Set Height 700
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms

# 暖機:Set Shell zsh 不讀 rc,所以從 bash 起、exec zsh;cd 回家目錄(vhs 在 ~/demo 跑)。
# 歷史要在 bash 階段用 echo 寫好:autosuggestion 的灰字和 fzf 的歷史面板都從這裡來;
# 不用 printf '...\n',VHS 會把 \n 照字面打進去。
Hide
Type "echo ll > ~/.zsh_history && echo 'bat README.md' >> ~/.zsh_history" Enter
Type `echo "rg -n 'alias ll' home/dot_zshrc" >> ~/.zsh_history && echo 'cd ~/.local/share/chezmoi' >> ~/.zsh_history` Enter
Type "cd && exec zsh" Enter
Sleep 8s
Ctrl+L
Sleep 500ms
Show

# 1. shell.png:p10k 進 git repo、eza 列表,最後一行打到一半停住
Type "cd ~/.local/share/chezmoi" Enter
Sleep 1s
Type "ll" Enter
Sleep 1.5s
Type "bat R"
Sleep 1s
Screenshot shell.png
# Ctrl+C 取消那行後結束碼是 130,下一個 prompt 的 ❯ 會變紅、看起來像出錯;偷跑 true 歸零
Ctrl+C
Hide
Type "true" Enter
Sleep 500ms
Show

# 2. shell-tools.png:bat、rg。bat 印整個短檔、不用 -r 行號:被印的檔改了也不會截錯位置
#    (sh-skip 沒有副檔名,-l sh 指定語法)
Ctrl+L
Type "bat -l sh home/.chezmoitemplates/sh-skip" Enter
Sleep 1s
Type "rg -n 'alias ll' home/dot_zshrc" Enter
Sleep 1s
Screenshot shell-tools.png

# 3. shell-fzf.png:清空再開 Ctrl-R。錄過一次跟 bat、rg 放同一張,上面 bat 的檔頭被推出畫面
Ctrl+L
Ctrl+R
Sleep 800ms
Type "bat"
Sleep 1s
Screenshot shell-fzf.png
Escape
Sleep 500ms

# 4. shell-fastfetch.png
Ctrl+L
Type "fastfetch" Enter
Sleep 4s
Screenshot shell-fastfetch.png
# 最後一張截圖後要再等一下:tape 一結束,還沒寫出的截圖就不見了(錄過一次只缺這張)
Sleep 1s
