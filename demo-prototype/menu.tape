# PROTOTYPE — README「怎麼裝」選單 GIF 劇本（#159 Q1–Q8 定案版；GIF 是加 NPM 那行之前錄的）
# 畫面：打 README 那行指令 →（剪掉第 1–4 關）→ 選單取消勾 5 項 → Enter →（剪掉安裝）→ 完成
# 取消勾的 5 項 = 選單全部減掉 e2e 的 TOOLS_FIRST，裝完的環境就是主 GIF 要的那台。
# 高 400：選單固定一頁 11 項（跟高度無關），壓矮讓上面錄影環境才有的 log（跳過 key、不連 GitHub）推出畫面
Output menu-a.gif
Set Shell bash
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 18
Set Width 1200
Set Height 400
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 25ms

# CODEX_NON_INTERACTIVE：有 TTY 時 codex installer 會問「Start Codex now?」卡住 apply（repo 的 bug，e2e 用 --no-tty 測不到）
# NPM_CONFIG_UPDATE_NOTIFIER：結尾「完成」上方不要出現 npm 的新版本提示（#159 Q5）
# 測試用環境變數 + 把 curl 換成本機那份 bootstrap.sh（只在這個 shell，bootstrap 裡的 curl 不受影響）
Hide
Type "export BOOTSTRAP_SKIP_GITHUB=1 BOOTSTRAP_SKIP_UPGRADE=1 BOOTSTRAP_REPO=~/e2e-fixtures/dotfiles AGENT_CONFIG_REMOTE=~/e2e-fixtures/agent-config.git CODEX_NON_INTERACTIVE=1 NPM_CONFIG_UPDATE_NOTIFIER=false" Enter
Type "curl() { cat ~/e2e-fixtures/dotfiles/script/bootstrap.sh; }" Enter
Type "PS1='$ '" Enter
Ctrl+L
Sleep 500ms
Show

# 1. README 上那行指令
Sleep 800ms
Type "bash <(curl -fsSL https://raw.githubusercontent.com/henry5720/dotfiles/main/script/bootstrap.sh)"
Sleep 600ms
Enter
Sleep 300ms

# 2. 第 1–4 關、裝 chezmoi 剪掉，選單出來才顯示
# Wait+Screen 等選單不可靠（畫面明明有字也會逾時），用固定等待：選單會停著等輸入
Hide
Sleep 150s
Sleep 500ms
Show
Sleep 1.5s
Screenshot menu-open.png

# 3. 多選：往下取消勾 ttyd、wakatime、opencode、document-media、ai-document-media
Set TypingSpeed 120ms
Down 7
Space Sleep 400ms
Down
Space Sleep 400ms
Down 3
Space Sleep 400ms
Down
Space Sleep 400ms
Down
Space Sleep 1s
Screenshot menu-picked.png
Enter

# 4. 安裝過程剪掉，停在完成訊息
# VHS 讀到的行尾空白會被砍掉，prompt 是 `$` 不是 `$ `
Hide
Wait+Line@40m /\$$/
Show
Sleep 3s
