# README「新機器」段的選單 GIF(script/demo/record.sh 錄)
# 畫面:打 README 的 Ubuntu 那行指令 →(剪掉下載 chezmoi)→ 用途按 m → 選單再勾 3 項 → Enter →(剪掉安裝)→ 完成
# 精簡預勾的項目見 home/.chezmoi.toml.tmpl 的 $lean,主 GIF 要的 zsh、eza 在裡面;
# 再勾主 GIF 要的 fastfetch,gh、claude 是示範,挑裝得快的。$lean 或選單順序改了,下面的 Down 次數要重算。
# 秘密不會問:record.sh 錄之前先寫好假值。
# 高 400:選單固定一頁 11 項(跟高度無關),壓矮讓上面 installer 的 log 推出畫面
Output menu.gif
Set Shell bash
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 18
Set Width 1440
Set Height 400
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 25ms

# 裝的是本機 repo 而不是 GitHub 上的:先把 fixture cp 成 chezmoi 的 source,
# source 已經在,畫面上那行 init 就不 clone、直接用它(跟 script/tests/e2e.sh 同一招)。
# agent-config 也換成假 remote。chezmoi 本身照樣從 get.chezmoi.io 下載。
Hide
Type "export AGENT_CONFIG_REMOTE=~/e2e-fixtures/agent-config.git" Enter
Type "mkdir -p ~/.local/share && cp -a ~/e2e-fixtures/dotfiles ~/.local/share/chezmoi && cd ~" Enter
Type "PS1='$ '" Enter
Ctrl+L
Sleep 500ms
Show

# 1. README 上 Ubuntu 那行指令
Sleep 800ms
Type `sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply henry5720`
Sleep 600ms
Enter
Sleep 300ms

# 2. 下載 chezmoi 剪掉,用途那題出來才顯示
# Wait+Screen 等提問不可靠(畫面明明有字也會逾時),用固定等待:提問會停著等輸入
Hide
Sleep 60s
Sleep 500ms
Show
Sleep 2s

# 3. 用途:停著讓灰字 f/m/c 看得到,按 m。打到唯一選項就送出,不要再按 Enter(會直接確認選單)
Type "m"
Sleep 2s

# 4. 多選:精簡已預勾 8 項,再勾 fastfetch、gh、claude
#    選單順序見 home/.chezmoitemplates/tool-menu;錄影容器是 amd64 Ubuntu,23 項全列,游標從 zsh 開始
Set TypingSpeed 120ms
Down 6
Space Sleep 400ms
Down 2
Space Sleep 400ms
Down 6
Space Sleep 1s
Enter

# 5. 安裝過程剪掉,停在完成訊息
# VHS 讀到的行尾空白會被砍掉,prompt 是 `$` 不是 `$ `
Hide
Wait+Line@40m /\$$/
Show
Sleep 3s
