# README「新機器」段的選單 GIF(script/demo/record.sh 錄)
# 畫面:打 README 的 Ubuntu 那行指令 →(剪掉下載 chezmoi)→ 選單勾 4 項 → Enter →(剪掉安裝)→ 完成
# 選單預設都不勾。主 GIF 只需要 fastfetch,另外 3 項是示範,挑裝得快的。
# 高 400:選單固定一頁 11 項(跟高度無關),壓矮讓上面 installer 的 log 推出畫面
Output menu.gif
Set Shell bash
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 18
Set Width 1200
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

# 2. 下載 chezmoi 剪掉,選單出來才顯示
# Wait+Screen 等選單不可靠(畫面明明有字也會逾時),用固定等待:選單會停著等輸入
Hide
Sleep 60s
Sleep 500ms
Show
Sleep 1.5s

# 3. 多選:勾 fastfetch、gh、claude、codex(選單順序見 home/.chezmoi.toml.tmpl 的 $toolChoices)
Set TypingSpeed 120ms
Space Sleep 400ms
Down 2
Space Sleep 400ms
Down 7
Space Sleep 400ms
Down
Space Sleep 1s
Enter

# 4. 安裝過程剪掉,停在完成訊息
# VHS 讀到的行尾空白會被砍掉,prompt 是 `$` 不是 `$ `
Hide
Wait+Line@40m /\$$/
Show
Sleep 3s
