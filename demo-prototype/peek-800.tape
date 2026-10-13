# PROTOTYPE — 窺視版：只錄到選單勾完，Ctrl+C 不 apply（高 800）
# 畫面：打 README 那行指令 →（剪掉第 1–4 關）→ 選單取消勾 5 項 → Enter →（剪掉安裝）→ 完成
# 取消勾的 5 項 = 選單全部減掉 e2e 的 TOOLS_FIRST，裝完的環境就是主 GIF 要的那台。
Output peek-800.gif
Set Shell bash
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 18
Set Width 1200
Set Height 800
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 25ms

# 測試用環境變數 + 把 curl 換成本機那份 bootstrap.sh（只在這個 shell，bootstrap 裡的 curl 不受影響）
Hide
Type "export BOOTSTRAP_SKIP_GITHUB=1 BOOTSTRAP_SKIP_UPGRADE=1 BOOTSTRAP_REPO=~/e2e-fixtures/dotfiles AGENT_CONFIG_REMOTE=~/e2e-fixtures/agent-config.git" Enter
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
# 等 fastfetch：VHS 讀畫面只讀到選單前幾行，等底下的說明列（x toggle、navigate）會逾時
Hide
Wait+Screen@3m /fastfetch/
Sleep 500ms
Show
Sleep 1.5s
Screenshot peek-800-open.png

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
Screenshot peek-800-picked.png
Ctrl+C
Sleep 1s
