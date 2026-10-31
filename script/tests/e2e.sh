#!/bin/bash
# 容器 e2e:在全新容器裡照 README「新機器」那兩行官方指令裝 chezmoi、從本機 repo
# `chezmoi init --apply`,檢查機器上看得到的結果。
#
# 用法:
#   bash script/tests/e2e.sh [ubuntu|termux]     # 預設 ubuntu
#
# 環境變數:
#   E2E_TAG=<字串>   容器名與映像 tag 的後綴,平行跑時避免撞名(預設 local)
#   E2E_KEEP=1       跑完不刪容器,方便 `docker exec -it <容器> bash` 進去看
#
# 測的是 repo 的工作目錄(含未 commit 的修改),不經過 GitHub:
# 工作目錄在主機上包成一個暫時的 git repo 放進容器,先 cp 成 chezmoi 的 source(~/.local/share/chezmoi),
# 再照抄 README 那行:source 已經在,chezmoi init 就不 clone,直接用它渲染、apply。
# (不把路徑直接給 init:clone 本機路徑要外部 git,連 go-git 也是,但全新機器還沒有 git。
#  真的從 GitHub clone 那段由「chezmoi init henry5720 猜出 HTTPS」那項檢查驗。)
# 機器上不放 SSH key(新機器本來就可以沒有);Termux 那段之後才放假 key 測 authorized_keys。
# 秘密類 prompt 用 --promptString 給假值。
#
# 要加檢查項目:改下面「目標:<目標>」那一段的 scenario_<目標>,其他地方不用動。
# 要加選裝工具:TOOL_CHECK 加一行,再決定 scenario_ubuntu 裡勾不勾(TOOLS_FIRST／check_no_tool)。
# step  = 前提步驟,失敗就整個停(後面的檢查沒有意義)
# check = 檢查項目,失敗會記下來、印出輸出,繼續跑下一項
set -uo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
TARGET=${1:-ubuntu}
TAG=${E2E_TAG:-local}
IMAGE="dotfiles-e2e-$TARGET:$TAG"
CTR="dotfiles-e2e-$TARGET-$TAG"
FAILED=()

# 建映像與容器(setup_ubuntu)、fixtures(make_fixtures)、cleanup、red/green/bold
# 跟錄影共用,在 container.sh。
. "$REPO/script/tests/container.sh"

# ===============================================================
# 共用工具
# ===============================================================
# 在容器裡以一般使用者執行(login shell,~/.local/bin 會在 PATH 上)。
# 輸出存進 $OUT,呼叫端決定要不要印。CTR_USER／CTR_HOME 由 setup_<目標> 設定。
in_ctr() {
  OUT=$(docker exec -u "$CTR_USER" -w "$CTR_HOME" "$CTR" bash -lc "$1" 2>&1)
}

step() {  # step <描述> <容器內指令>
  bold "▶ $1"
  if in_ctr "$2"; then
    return 0
  fi
  red "✗ 前提步驟失敗:$1"
  red "  指令:$2"
  printf '%s\n' "$OUT" | tail -n 40 | sed 's/^/  │ /'
  exit 1
}

check() {  # check <描述> <容器內指令>
  if in_ctr "$2"; then
    green "  ✓ $1"
  else
    red "  ✗ $1"
    red "    指令:$2"
    printf '%s\n' "$OUT" | tail -n 20 | sed 's/^/    │ /'
    FAILED+=("$1")
  fi
}

# 印出「照 README 裝新機器」的容器內指令,交給 step／check 執行。多給的參數轉給 chezmoi init。
# 跟 README 只差在:先放好 source(見檔頭);Termux 的 pkg 加 -y(README 那行會問 Y/n)。
install_cmd() {  # install_cmd <輸出 log> [chezmoi init 參數...]
  local log=$1; shift
  local pre="set -o pipefail; export AGENT_CONFIG_REMOTE=$FIX/agent-config.git; mkdir -p ~/.local/share && cp -a $FIX/dotfiles ~/.local/share/chezmoi && cd ~"
  local args; args="henry5720 $(printf '%q ' "$@")"
  if [ "$TARGET" = termux ]; then
    # --force-confold:升級遇到改過的設定檔保留現有的,不跳 dpkg 的互動問題
    echo "$pre && export DEBIAN_FRONTEND=noninteractive && { pkg upgrade -y -o Dpkg::Options::=--force-confold && pkg install -y chezmoi && chezmoi init --apply $args; } 2>&1 | tee $log"
  else
    # 在家目錄跑:/lb 裝到「目前目錄」的 .local/bin
    echo "$pre && { sh -c \"\$(curl -fsLS get.chezmoi.io/lb)\" -- init --apply $args; } 2>&1 | tee $log"
  fi
}

# 兩個目標共用:git 的 HTTPS clone、SSH push。
GH_HTTPS=https://github.com/henry5720
check_git_remotes() {
  check "沒放 SSH key 也裝完(~/.ssh/henry5720 不存在)" "[ ! -e ~/.ssh/henry5720 ]"
  check "gitconfig 有 url.git@github.com:.pushInsteadOf = https://github.com/" \
    "[ \"\$(git config --global --get url.git@github.com:.pushInsteadOf)\" = https://github.com/ ]"
  # 不連網:git 自己算出 fetch／push 各用哪個 URL。Termux 沒有 /tmp,用 $TMPDIR
  check "HTTPS remote 的 fetch 不改寫、push 改寫成 git@github.com:" \
    "d=\${TMPDIR:-/tmp}/pio; rm -rf \$d && git init -q \$d && git -C \$d remote add origin $GH_HTTPS/dotfiles.git && [ \"\$(git -C \$d remote get-url origin)\" = $GH_HTTPS/dotfiles.git ] && [ \"\$(git -C \$d remote get-url --push origin)\" = git@github.com:henry5720/dotfiles.git ]"
  # e2e 用 AGENT_CONFIG_REMOTE 換成假 remote,這裡另外看沒換時的預設值,並確認不帶 key 真的 clone 得到
  check "agent-config 腳本預設 remote 是 HTTPS,而且不用 key 就讀得到" \
    "url=\$(chezmoi execute-template --override-data '{\"tools\":[\"agent-config\"]}' < ~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_after_install-agent-config.sh.tmpl | sed -n 's/^remote=\\\${AGENT_CONFIG_REMOTE:-\\(.*\\)}\$/\\1/p') && echo \"\$url\" && [ \"\$url\" = $GH_HTTPS/agent-config.git ] && GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false git ls-remote \"\$url\" HEAD | grep -q HEAD"
}

# 秘密類 prompt 的假值。--promptString 的 key 是「提示文字」不是資料名稱,
# 所以要跟 home/.chezmoi.toml.tmpl 的提示文字一字不差;漏了會在 init 時看到 EOF 和那句提示。
INIT_FLAGS=(
  --promptString 'code-server 密碼=e2e'
  --promptString 'codex-lb API key=e2e'
  --promptString 'Context7 API key（可留空）='
  --promptString 'WakaTime API key（可留空）='
  --promptString 'git user.name=e2e'
  --promptString 'git user.email=e2e@example.com'
)

# ===============================================================
# 共用檢查
# ===============================================================
# zsh 環境:兩個目標共用。預設 shell 怎麼查各平台不同,由呼叫端給指令。
ZSH_EXTERNALS=(powerlevel10k zsh-autosuggestions zsh-z zsh-syntax-highlighting)

# zsh_ok <zsh 指令> [tty]:印出一段容器內指令 —— 在 zsh -i 裡跑它,要回傳 0、stderr 要是空的。
# docker exec 沒有終端機;給 tty 就改在 pty 裡跑(zshrc 的 fzf 整合只在有終端機時載入)。
# termux-docker 沒有 Android 系統 library,.zshrc 開頭的 fastfetch 一定 link 失敗(真機不會),
# 只濾掉這一種訊息,其他 stderr 照樣算錯。zsh 指令裡不能有單引號。
zsh_ok() {
  local run=""
  [ "${2:-}" = tty ] && run="python3 -I $FIX/zsh-tty.py "
  echo "if ! err=\$(${run}zsh -i -c '$1' 2>&1 >/dev/null); then echo \"zsh 回傳非 0:\$err\"; false; else err=\$(printf '%s\\n' \"\$err\" | grep -v 'CANNOT LINK EXECUTABLE \"fastfetch\"'); [ -z \"\$err\" ] || { echo \"\$err\"; false; }; fi"
}

# check_alias <描述> <alias 名> <zsh 條件>:條件裡用 $a 代表 alias 展開的結果(沒定義是「未定義」)
check_alias() {
  check "$1" "$(zsh_ok "a=\${aliases[$2]-未定義}; [[ $3 ]] || { print -ru2 -- \"實際:$2 → \$a\"; false }")"
}

# Codex 權限三個 key 由 modify_ 釘死(#148);不測 sandbox 行為,容器裡的結果不代表實機。
check_codex_permissions() {
  check "modify_ 產物:~/.codex/config.toml 權限是 on-request + workspace-write + auto_review" \
    "python3 -c 'import tomllib,sys; c=tomllib.load(open(sys.argv[1],\"rb\")); assert (c[\"approval_policy\"],c[\"sandbox_mode\"],c[\"approvals_reviewer\"])==(\"on-request\",\"workspace-write\",\"auto_review\")' ~/.codex/config.toml"
}

check_zsh_env() {  # check_zsh_env <印出預設 shell 路徑的容器內指令>
  check "預設 shell 是 zsh" "[ \"\$($1)\" = \"\$(command -v zsh)\" ]"
  for d in "${ZSH_EXTERNALS[@]}"; do
    check "~/.config/zsh/$d 是 git clone" "git -C ~/.config/zsh/$d rev-parse --is-inside-work-tree"
  done
  check "~/.p10k.zsh 已部署" "grep -q POWERLEVEL9K_LEFT_PROMPT_ELEMENTS ~/.p10k.zsh"
  # 沒有 tty 時 p10k 本來就不會跑 wizard,所以另外確認:p10k 有載入、設定檔有被讀到、stderr 是空的。
  # 這項沒有終端機,也守住「沒終端機時 fzf 整合不載入、不印 can't change option: zle」。
  check "zsh -i -c exit 不出錯、p10k 與插件有載入、設定檔有讀到" \
    "$(zsh_ok '(( ${+functions[p10k]} && ${+functions[_zsh_autosuggest_start]} && ${+functions[zshz]} && ${+ZSH_HIGHLIGHT_VERSION} )) && [[ -n $POWERLEVEL9K_LEFT_PROMPT_ELEMENTS ]]')"
  # stderr 是空的也守住 `fzf --zsh`:吃到沒有 --zsh 的舊版 fzf 會在這裡報錯。
  check "(有 tty)zsh -i -c exit 不出錯、fzf 整合有載入" \
    "$(zsh_ok '[[ -n $TTY ]] && (( ${+functions[fzf-history-widget]} ))' tty)"
  # ls、grep 只加顏色;ll 等有 eza 才用 eza(兩邊都有裝 eza)
  check_alias "ll 展開含 eza" ll '$a == *eza*'
  check_alias "ls 展開是 ls --color=auto(沒換成 eza)" ls '$a == "ls --color=auto"'
  check_alias "grep 展開是 grep --color=auto" grep '$a == "grep --color=auto"'
  # bat、rg 有裝,但不蓋掉 cat、grep(參數意思不同)
  check_alias "cat 沒被換成 bat" cat '$a != *bat*'
  check_alias "grep 沒被換成 rg" grep '" $a " != *" rg "*'
  # wizard 是在第一次畫 prompt 時跳出來,`zsh -i -c` 不畫 prompt,所以要真的開互動 shell:
  # 用 python 的 pty 模擬終端機(兩邊都有 python3),等輸出停下來再送 exit。
  # wizard 會吃掉那個 exit 繼續等輸入,30 秒後砍掉,輸出裡有 wizard 字樣就算失敗。
  check "互動 zsh(有 tty)不跳 p10k wizard、正常 exit" \
    "out=\$(python3 - <<'PY'
import os, pty, select, signal, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.execvp('zsh', ['zsh', '-i'])
out, sent, end = b'', False, time.time() + 30
while time.time() < end:
    if select.select([fd], [], [], 1)[0]:
        try:
            d = os.read(fd, 4096)
        except OSError:
            break
        if not d:
            break
        out += d
    elif not sent:
        os.write(fd, b'exit\n')
        sent = True
for _ in range(30):
    if os.waitpid(pid, os.WNOHANG)[0]:
        break
    time.sleep(0.1)
else:
    os.kill(pid, signal.SIGKILL)
    out += b'[ZSH-DID-NOT-EXIT]'
sys.stdout.write(out.decode(errors='replace'))
PY
); echo \"\$out\" | tail -n 15; ! grep -qiE 'configuration wizard|ZSH-DID-NOT-EXIT' <<<\"\$out\""
}

# 選裝工具選單。--promptMultichoice 的 key 也是「提示文字」,值用 / 分隔。
TOOLS_PROMPT='選裝工具（空白鍵勾選，Enter 確定）'
# 選單上的選項是「工具名 + 說明」(home/.chezmoitemplates/tool-menu),--promptMultichoice 要給這串。
# menu_choice a/b → 「$TOOLS_PROMPT=a 的選單文字/b 的選單文字」;排版要跟 .chezmoi.toml.tmpl 的 printf 一樣。
menu_choice() {
  local t out=() line
  for t in ${1//\// }; do
    line=$(grep -m1 "^$t " "$REPO/home/.chezmoitemplates/tool-menu") || { echo "tool-menu 沒有 $t" >&2; return 1; }
    out+=("$(printf '%-16s %s' "$t" "${line#"$t "}")")
  done
  (IFS=/; echo "$TOOLS_PROMPT=${out[*]}")
}
# 第一次 init 只勾這些;ttyd、wakatime、opencode 故意不勾,之後模擬 edit-config 補勾 wakatime。
# ffmpeg、mupdf-tools、pandoc 一般用不到、相依套件一大串,不在這裡實裝,只做下面的渲染檢查。
TOOLS_FIRST=fastfetch/btop/gh/nvm/code-server/tailscale/herdr/claude/codex/codegraph/headless-chrome/playwright-cli/agent-config

# agent-config 的預設 remote 是 GitHub 的 HTTPS(check_git_remotes 驗)。安裝測試用
# AGENT_CONFIG_REMOTE 換成 $FIX/agent-config.git(見 make_fixtures),內容可控、不受上游變動影響;
# skillshare 本身照樣從網路裝、照樣 init/install/sync。

# 每個工具「裝好了」從外面怎麼看。這裡是獨立的期望值,不從安裝腳本抄。
declare -A TOOL_CHECK=(
  [fastfetch]="command -v fastfetch"
  [btop]="dpkg-query -W -f='\${Status}' btop | grep -q 'install ok installed'"
  # gh 要是官方 apt 源那版(有 pin),不是 Ubuntu 套件庫的舊版
  [gh]="command -v gh && [ -f /etc/apt/preferences.d/github-cli ] && apt-cache policy gh | grep -A1 '^ \*\*\*' | grep -q cli.github.com"
  [nvm]=". ~/.nvm/nvm.sh && node --version"
  [code-server]="command -v code-server"
  [tailscale]="command -v tailscale"
  [herdr]="command -v herdr"
  [ttyd]="command -v ttyd"
  # 官方位置:~/.wakatime/wakatime-cli 是指到 wakatime-cli-linux-<arch> 的 symlink
  [wakatime]="[ -L ~/.wakatime/wakatime-cli ] && ~/.wakatime/wakatime-cli --version"
  [claude]="command -v claude && claude --version"
  [codex]="command -v codex && codex --version"
  [opencode]="command -v opencode || [ -x ~/.opencode/bin/opencode ]"
  [ffmpeg]="dpkg-query -W -f='\${Status}' ffmpeg 2>/dev/null | grep -q 'install ok installed'"
  [mupdf-tools]="dpkg-query -W -f='\${Status}' mupdf-tools 2>/dev/null | grep -q 'install ok installed'"
  [pandoc]="dpkg-query -W -f='\${Status}' pandoc 2>/dev/null | grep -q 'install ok installed'"
  # npm 全域套件裝在 nvm 的 Node 底下,bash -l 不會載入 nvm(那是 .zshrc 的事)
  [codegraph]=". ~/.nvm/nvm.sh && codegraph --version"
  # 真的能 headless 開頁,而且中文／emoji 字型在
  [headless-chrome]="google-chrome --headless --no-sandbox --disable-gpu --dump-dom 'data:text/html,<p>e2e-ok</p>' 2>/dev/null | grep -q e2e-ok && [ \$(dpkg-query -W -f='\${Status}\\n' fonts-noto-cjk fonts-noto-color-emoji 2>/dev/null | grep -c 'install ok installed') = 2 ]"
  # 用 headless-chrome 裝的那支 Chrome 真的開得了頁(它預設找 /opt/google/chrome/chrome,不會自己下載)。
  # 容器擋 user namespace,Chrome sandbox 起不來,所以關掉(同上面 headless-chrome 的 --no-sandbox)
  [playwright-cli]=". ~/.nvm/nvm.sh && playwright-cli --version && PLAYWRIGHT_MCP_SANDBOX=false playwright-cli -s=e2e open 'data:text/html,<title>e2e-ok</title>' | grep -q e2e-ok; r=\$?; playwright-cli -s=e2e close >/dev/null 2>&1; [ \$r = 0 ]"
  # skillshare 從假 remote init 完:repo 在、skill 連進 Claude、MCP 寫進 Claude 的設定;extras 把 CLAUDE.md 連到 AGENTS.md
  [agent-config]="command -v skillshare && [ -d ~/.config/skillshare/.git ] && [ -r ~/.claude/skills/e2e-hello/SKILL.md ] && grep -q e2e-mcp ~/.claude.json && [ -L ~/.claude/CLAUDE.md ] && grep -q e2e-agents ~/.claude/CLAUDE.md"
)
check_tool()     { check "選裝工具 $1 已安裝" "${TOOL_CHECK[$1]}"; }
check_no_tool()  { check "選裝工具 $1 沒有安裝" "! { ${TOOL_CHECK[$1]}; }"; }

# 各 agent／編輯器的官方 WakaTime plugin:wakatime 和那個工具都勾了才裝(#172、#173、#174)。
# 從 agent 自己的 plugin 清單看,不看檔案位置。
declare -A WAKA_PLUGIN=(
  [claude]="claude plugin list --json | jq -e 'any(.[]; .id == \"claude-code-wakatime@wakatime\")'"
  [codex]="codex plugin list --json | jq -e 'any(.installed[]?; .pluginId == \"codex-cli-wakatime@wakatime\")'"
  [code-server]="code-server --list-extensions | grep -qix wakatime.vscode-wakatime"
)
check_waka_plugin()    { check "$1 的 WakaTime plugin 已安裝" "${WAKA_PLUGIN[$1]}"; }
check_no_waka_plugin() { check "$1 的 WakaTime plugin 沒有安裝" "! { ${WAKA_PLUGIN[$1]}; }"; }

# 選裝腳本在 chezmoi 裡的名字(scriptState 的 name、dry-run 的 diff 標頭)。從 TOOL_CHECK 產生,
# 加工具時不用再改這裡。名字帶腳本所在的 .chezmoiscripts/;codegraph 的腳本叫 npm-install-codegraph,
# 所以檔名前綴是 (npm-)?install-。
TOOL_SCRIPT_RE="\\.chezmoiscripts/(npm-)?install-($(IFS="|"; echo "${!TOOL_CHECK[*]}"))"

# ===============================================================
# 目標:ubuntu(代表 WSL、雲端主機、proot Ubuntu)
# ===============================================================
# setup_ubuntu 在 container.sh(錄影也用它)。

# 基底套件:跟 home/.chezmoidata/packages.yaml 是兩份獨立的期望值,刻意不從 yaml 讀,
# 不然 yaml 少列一個測試也照樣過。
UBUNTU_BASE=(zsh git curl vim build-essential unzip jq python3)

# 預設安裝的命令列工具:Linux 由 run_onchange_after_install-cli-tools 從 GitHub release 下載到 ~/.local/bin。
CLI_TOOLS=(eza fzf bat rg)

check_cli_tools() {
  for t in "${CLI_TOOLS[@]}"; do
    check "~/.local/bin/$t 能執行(--version exit 0)" "~/.local/bin/$t --version"
  done
  # 沒裝到要安靜略過(下載失敗、架構不支援):把 binary 藏起來模擬,檢查完放回去
  local hide="" unhide=""
  for t in "${CLI_TOOLS[@]}"; do
    hide+="mv ~/.local/bin/$t ~/.local/bin/$t.e2e-hidden && "
    unhide+="mv ~/.local/bin/$t.e2e-hidden ~/.local/bin/$t && "
  done
  step "藏起 ~/.local/bin 的 ${CLI_TOOLS[*]}" "${hide}true"
  check "藏起後 zsh -i -c exit 不出錯" "$(zsh_ok 'true')"
  check "藏起後(有 tty)zsh -i -c exit 不出錯" "$(zsh_ok '[[ -n $TTY ]]' tty)"
  check_alias "藏起後 ll 退回 ls -alF" ll '$a == "ls -alF"'
  check_alias "藏起後 la 退回 ls -A" la '$a == "ls -A"'
  check_alias "藏起後 l 退回 ls -CF" l '$a == "ls -CF"'
  check_alias "藏起後 lt 沒定義" lt '$a == 未定義'
  step "放回 ~/.local/bin 的 ${CLI_TOOLS[*]}" "${unhide}true"
}

# 容器裡做不到、刻意不驗的事:
# - tailscale:容器 PID 1 不是 systemd,`systemctl enable --now tailscaled` 一定會跳過。
#   只驗 tailscale 有裝、而且安裝腳本有印出「跳過 systemd」的訊息(證明走到了那個分支、沒有失敗)。
#   真的啟用 tailscaled 要在有 systemd 的機器上人工確認。
# - nvm／code-server／herdr／fastfetch／wakatime 都會連網抓上游 installer 或 release;
#   上游掛掉測試就會紅,這是預期的(它就是要驗真的裝得起來)。
scenario_ubuntu() {
  step "全新機器跑 README 的官方安裝指令,init --apply(選單只勾一部分)" \
    "$(install_cmd '~/e2e-init.log' --no-tty "${INIT_FLAGS[@]}" --promptMultichoice "$(menu_choice "$TOOLS_FIRST")")"
  check "chezmoi 裝在 ~/.local/bin,家目錄沒多出 bin/" "[ -x ~/.local/bin/chezmoi ] && [ ! -e ~/bin ]"
  check_git_remotes
  # 真的連 GitHub(HTTPS,不用 key):README 那行給的是 henry5720,chezmoi 自己猜 URL。
  # 只 init 不 apply,source 與 config 放 /tmp,不碰上面裝好的那份;config 樣板是 GitHub main 上那份。
  # 這時套件腳本已經裝了 git;--use-builtin-git 強制走內建 go-git,跟還沒有 git 的新機器一樣。
  check "chezmoi init henry5720 猜出 HTTPS 的 GitHub URL、push 走 SSH" \
    "rm -rf /tmp/guess && chezmoi --source /tmp/guess/src --config /tmp/guess/chezmoi.toml --use-builtin-git true init --no-tty --promptDefaults $(printf '%q ' "${INIT_FLAGS[@]}") henry5720 </dev/null && [ \"\$(git -C /tmp/guess/src remote get-url origin)\" = $GH_HTTPS/dotfiles.git ] && [ \"\$(git -C /tmp/guess/src remote get-url --push origin)\" = git@github.com:henry5720/dotfiles.git ]"

  bold "▶ 第一次 apply 之後"
  for p in "${UBUNTU_BASE[@]}"; do
    check "基底套件 $p 已安裝" "dpkg-query -W -f='\${Status}' $p | grep -q 'install ok installed'"
  done
  for t in ${TOOLS_FIRST//\// }; do check_tool "$t"; done
  check_no_tool ttyd
  check_no_tool wakatime
  check_no_tool opencode
  check_no_tool ffmpeg
  check_no_tool mupdf-tools
  check_no_tool pandoc
  # agent 有裝、wakatime 沒勾:不裝 plugin
  for a in "${!WAKA_PLUGIN[@]}"; do check_no_waka_plugin "$a"; done
  check "tools 指令部署成可執行檔" "[ -x ~/.local/bin/tools ]"
  # skillshare 的設定(modify_config.yaml.tmpl)是 modify_ 檔案,所有 after_ 腳本都在檔案部署之後跑。
  # 腳本找不到 config.yaml 會失敗;apply 有跑完、上面 agent-config 的檢查過了,就代表順序對。
  check "agent-config 用的是 chezmoi 放的 skillshare 設定(targets 有 claude、codex)" \
    "grep -q 'path: ~/.claude/skills' ~/.config/skillshare/config.yaml && [ -e ~/.agents/skills/e2e-hello ]"
  check "tailscale 在沒有 systemd 時跳過啟用,而不是失敗" "grep -q 'PID 1 不是 systemd' ~/e2e-init.log"
  check "zshrc 沒被 installer 改動(nvm 等不能往 ~/.zshrc 追加)" "chezmoi verify ~/.zshrc"
  # Termux 用 .chezmoiignore 排除這支;Ubuntu 上要照常跑(scriptState 記下它的名字就是跑完了)。
  check "移除 chezmoi MCP 的 python 腳本有跑" \
    "chezmoi state dump --format json | jq -e '[.scriptState[].name] | index(\".chezmoiscripts/remove-chezmoi-mcp.py\")'"
  # Termux 字型三件套只給 android;Ubuntu 上什麼都不多。
  check "沒有 ~/.termux/font.ttf" "[ ! -e ~/.termux/font.ttf ] && [ ! -L ~/.termux/font.ttf ]"
  # 全新容器原本沒有這個目錄,chezmoi 也不該為了 android 的 symlink 建出空目錄。
  check "沒有 ~/.local/share/fonts(連空目錄都不建)" "[ ! -e ~/.local/share/fonts ]"
  check "reload 腳本沒跑(渲染成空的)" \
    "! chezmoi state dump --format json | jq -e '[.scriptState[].name] | index(\".chezmoiscripts/termux-reload-settings.sh\")'"
  check_codex_permissions
  check_zsh_env "getent passwd \$(id -un) | cut -d: -f7"
  check_cli_tools

  bold "▶ 第二次 init／apply"
  check "再 init 一次不問選單(沒給任何 prompt 旗標也能跑完)" "chezmoi init --no-tty"
  check "選擇沒變" "grep -qF 'tools = [\"fastfetch\", \"btop\", \"gh\", \"nvm\", \"code-server\", \"tailscale\", \"herdr\", \"claude\", \"codex\", \"codegraph\", \"headless-chrome\", \"playwright-cli\", \"agent-config\"]' ~/.config/chezmoi/chezmoi.toml"
  check "沒有腳本待跑(chezmoi status 無 R)" "! chezmoi status | grep -E '^.?R'"
  check "換 shell 腳本已記為跑過、第二次不會再跑" \
    "chezmoi state dump --format json | jq -e '[.scriptState[].name] | index(\".chezmoiscripts/set-default-shell.sh\")' && ! chezmoi status | grep -q set-default-shell"
  check "第二次 apply exit 0、apt 沒被呼叫" \
    "before=\$(grep -c '^Commandline:' /var/log/apt/history.log); chezmoi apply --no-tty && [ \"\$(grep -c '^Commandline:' /var/log/apt/history.log)\" = \"\$before\" ]"
  check "chezmoi verify 通過" "chezmoi verify"

  # tools = init --prompt + apply。--prompt 只重問選單:憑證與 git 身分已經存過就不問,
  # 所以不給任何 prompt 旗標也不會卡在 stdin。--promptDefaults = 選單直接 Enter(保留現在的勾選)。
  bold "▶ tools 直接 Enter,憑證、git 身分與選單保留原值"
  step "記下現在的 tools" "grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml > /tmp/tools-before"
  check "tools --no-tty --promptDefaults(不給憑證旗標)exit 0" \
    "~/.local/bin/tools --no-tty --promptDefaults </dev/null"
  check "codeServerPassword 保留 e2e" "grep -qx '    codeServerPassword = \"e2e\"' ~/.config/chezmoi/chezmoi.toml"
  check "gitUserName 保留 e2e" "grep -qx '    gitUserName = \"e2e\"' ~/.config/chezmoi/chezmoi.toml"
  check "gitUserEmail 保留 e2e@example.com" "grep -qx '    gitUserEmail = \"e2e@example.com\"' ~/.config/chezmoi/chezmoi.toml"
  check "tools 保留原本的勾選" "grep -qxFf /tmp/tools-before ~/.config/chezmoi/chezmoi.toml"
  check "之後沒有腳本待跑" "! chezmoi status | grep -E '^.?R'"

  # 不經選單、直接用 chezmoi edit-config 改 [data] tools 那一行再 apply,也要能裝。
  # edit-config 只是開編輯器,這裡直接 sed config 模擬。
  bold "▶ edit-config 在 tools 多加 wakatime"
  # 模擬以前裝過 zsh 外掛的機器:clone 還在,apply 之後要被 .chezmoiremove 清掉、zsh 不再載入
  step "放一份舊的 zsh 外掛 clone" \
    "mkdir -p ~/.config/zsh/wakatime-zsh-plugin && echo '_wakatime_heartbeat() { :; }' > ~/.config/zsh/wakatime-zsh-plugin/wakatime.plugin.zsh"
  step "config 的 tools 加上 wakatime" \
    "sed -i 's/^    tools = \\[\\(.*\\)\\]\$/    tools = [\\1, \"wakatime\"]/' ~/.config/chezmoi/chezmoi.toml && grep -q '\"wakatime\"\\]\$' ~/.config/chezmoi/chezmoi.toml"
  check "只有 wakatime 的安裝腳本待跑" \
    "[ \"\$(chezmoi status | grep -E '^.?R')\" = \"\$(chezmoi status | grep -E '^.?R.*install-wakatime')\" ] && chezmoi status | grep -qE '^.?R.*install-wakatime'"
  check "apply exit 0" "chezmoi apply --no-tty"
  check_tool wakatime
  # zsh 外掛不再裝(#176):不 clone、zshrc 也不載入
  check "沒有 clone zsh 的 WakaTime 外掛" "[ ! -e ~/.config/zsh/wakatime-zsh-plugin ]"
  check "zsh 沒載入 WakaTime 外掛" "$(zsh_ok '(( ! ${+functions[_wakatime_heartbeat]} ))')"
  # claude 等 agent 第一次就勾了,補勾 wakatime 之後 plugin 才裝上
  for a in "${!WAKA_PLUGIN[@]}"; do check_waka_plugin "$a"; done
  check "plugin 寫進的設定跟 modify_ 不打架(chezmoi verify 通過)" "chezmoi verify"
  check_codex_permissions
  check "modify_ 釘的 chrome-devtools plugin 開關還在" \
    "jq -e '.enabledPlugins[\"chrome-devtools-mcp@claude-plugins-official\"] == false' ~/.claude/settings.json"
  # run_onchange_ 內容沒變就不會再跑,所以直接把渲染出來的腳本再跑一次
  check "wakatime 腳本重跑 exit 0、plugin 都跳過不重裝" \
    "out=\$(chezmoi execute-template < ~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_after_install-wakatime.sh.tmpl | sh 2>&1) && echo \"\$out\" && ! grep -q 'Successfully' <<<\"\$out\" && [ \"\$(grep -c 'plugin 已安裝,跳過' <<<\"\$out\")\" = ${#WAKA_PLUGIN[@]} ]"
  check_no_tool ttyd
  check "之後再 apply 沒有腳本待跑" "! chezmoi status | grep -E '^.?R'"
  check "之後 init(不帶 --prompt、不給任何 prompt 旗標)不問、tools 不變" \
    "chezmoi init --no-tty </dev/null && grep -q '^    tools = .*\"wakatime\"\\]\$' ~/.config/chezmoi/chezmoi.toml && grep -qF '\"agent-config\", \"wakatime\"]' ~/.config/chezmoi/chezmoi.toml"

  bold "▶ 套件清單加一個套件"
  step "yaml 的 ubuntu 清單加上 tree" "sed -i '/^    - python3\$/a\\    - tree' ~/.local/share/chezmoi/home/.chezmoidata/packages.yaml"
  check "套件腳本待跑(chezmoi status 有 R)" "chezmoi status | grep -E '^.?R.*install-packages'"
  check "apply exit 0" "chezmoi apply --no-tty"
  check "只裝了 tree" "tail -n 20 /var/log/apt/history.log | grep '^Commandline:' | tail -n 1 | grep -qx 'Commandline: apt-get install -y tree'"
  check "tree 已安裝" "dpkg-query -W -f='\${Status}' tree | grep -q 'install ok installed'"

  # 原生 Termux 不出選單、不跑選裝腳本。這裡只驗樣板(把 .chezmoi.os 蓋成 android 來渲染);
  # 真的在 termux 容器跑 init 由 termux 目標負責。
  bold "▶ (渲染)Termux 不出選單、不跑選裝腳本"
  local android='{"chezmoi":{"os":"android"}}'
  check "android 的 config 樣板不問選單,tools 是空的" \
    "chezmoi execute-template --init --no-tty --override-data '$android' $(printf '%q ' "${INIT_FLAGS[@]}") < ~/.local/share/chezmoi/home/.chezmoi.toml.tmpl > /tmp/android.toml && grep -qx '    tools = \[\]' /tmp/android.toml"
  # dry-run 的輸出含所有檔案的 diff,只看腳本自己的 diff 標頭,避免檔案內容裡提到腳本名就誤判。
  # 先確認同一招在 linux 上看得到選裝腳本,不然下一項「看不到」可能只是指令本身看不到腳本
  check "(對照)linux 用同一招看得到選裝腳本" \
    "chezmoi --destination /tmp/linux-home --persistent-state /tmp/linux.boltdb apply --dry-run --verbose --no-tty 2>&1 | grep -q '^diff --git a/\.chezmoiscripts/install-fastfetch'"
  check "android 上沒有任何選裝工具的腳本會跑" \
    "out=\$(chezmoi --config /tmp/android.toml --override-data '$android' --destination /tmp/android-home --persistent-state /tmp/android.boltdb apply --dry-run --verbose --no-tty 2>&1); ! printf '%s' \"\$out\" | grep -E '^diff --git a/$TOOL_SCRIPT_RE'"

  # WSL 用 Windows 的 Chrome(remote-chrome),選單不列 headless Chrome。
  # 用 --override-data 蓋 kernel.osrelease 模擬 WSL;--config 指向不存在的檔,
  # promptMultichoiceOnce 才會真的問。用 --promptMultichoice 指定勾哪項:不在選單上的會報 invalid choice。
  bold "▶ (渲染)WSL 選單不列 headless Chrome、playwright-cli"
  local wsl='{"chezmoi":{"kernel":{"osrelease":"5.15.167.4-microsoft-standard-WSL2"}}}'
  # 加引號:~ 要留到容器裡才展開(容器的家目錄是 /home/ubuntu,不是跑 e2e 這台的)
  local tmpl='~/.local/share/chezmoi/home' scripts='~/.local/share/chezmoi/home/.chezmoiscripts'
  check "選單預設都不勾(沒給旗標 = tools 是空的)" \
    "chezmoi --config /tmp/fresh-linux.toml execute-template --init --no-tty $(printf '%q ' "${INIT_FLAGS[@]}") < $tmpl/.chezmoi.toml.tmpl | grep -qx '    tools = \\[\\]'"
  check "(對照)非 WSL 的選單有 headless-chrome、playwright-cli" \
    "chezmoi --config /tmp/fresh-linux.toml execute-template --init --no-tty $(printf '%q ' "${INIT_FLAGS[@]}") --promptMultichoice $(printf '%q' "$(menu_choice headless-chrome/playwright-cli)") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"playwright-cli\"'"
  check "WSL 的選單照常列 AI 工具" \
    "chezmoi --config /tmp/fresh-wsl.toml execute-template --init --no-tty --override-data '$wsl' $(printf '%q ' "${INIT_FLAGS[@]}") --promptMultichoice $(printf '%q' "$(menu_choice agent-config)") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"agent-config\"'"
  for t in headless-chrome playwright-cli; do
    check "WSL 的選單沒有 $t(勾了會報 invalid choice)" \
      "chezmoi --config /tmp/fresh-wsl.toml execute-template --init --no-tty --override-data '$wsl' $(printf '%q ' "${INIT_FLAGS[@]}") --promptMultichoice $(printf '%q' "$(menu_choice $t)") < $tmpl/.chezmoi.toml.tmpl 2>&1 | grep -q 'invalid choice'"
  done
  check "WSL 上就算 tools 裡有 headless-chrome,安裝腳本也渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"headless-chrome\"],\"chezmoi\":{\"kernel\":{\"osrelease\":\"5.15.167.4-microsoft-standard-WSL2\"}}}' < $scripts/run_onchange_after_install-headless-chrome.sh.tmpl | tr -d '[:space:]')\" ]"
  check "WSL 上就算 tools 裡有 playwright-cli,安裝腳本也渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"playwright-cli\"],\"chezmoi\":{\"kernel\":{\"osrelease\":\"5.15.167.4-microsoft-standard-WSL2\"}}}' < $scripts/run_onchange_after_npm-install-playwright-cli.sh.tmpl | tr -d '[:space:]')\" ]"

  # 非 Debian 系 Linux(例如 Fedora):要 apt 的東西安靜略過。用 --override-data 蓋 osRelease 模擬
  # (id 與 idLike 都要蓋,不然留著容器本身 Ubuntu 的 idLike=debian)。
  bold "▶ (渲染)非 Debian 系 Linux 不出選單、apt 腳本渲染成空的"
  local fedora='{"chezmoi":{"osRelease":{"id":"fedora","idLike":""}}}'
  check "非 Debian 系的 config 樣板不問選單,tools 是空的" \
    "chezmoi --config /tmp/fresh-fedora.toml execute-template --init --no-tty --override-data '$fedora' $(printf '%q ' "${INIT_FLAGS[@]}") < $tmpl/.chezmoi.toml.tmpl > /tmp/fedora.toml && grep -qx '    tools = \[\]' /tmp/fedora.toml"
  local fedora_tools='{"chezmoi":{"osRelease":{"id":"fedora","idLike":""}},"tools":["fastfetch","gh","headless-chrome","playwright-cli","btop"]}'
  for f in run_onchange_before_install-packages run_once_after_set-default-shell \
           run_onchange_after_install-fastfetch run_onchange_after_install-gh run_onchange_after_install-headless-chrome \
           run_onchange_after_npm-install-playwright-cli; do
    check "非 Debian 系上 $f 渲染成空的(就算 tools 有勾)" \
      "[ -z \"\$(chezmoi execute-template --override-data '$fedora_tools' < $scripts/$f.sh.tmpl | tr -d '[:space:]')\" ]"
  done
  check "(對照)Debian 系(ID_LIKE 有 debian,例如 Linux Mint)照常出選單" \
    "chezmoi --config /tmp/fresh-mint.toml execute-template --init --no-tty --override-data '{\"chezmoi\":{\"osRelease\":{\"id\":\"linuxmint\",\"idLike\":\"ubuntu debian\"}}}' $(printf '%q ' "${INIT_FLAGS[@]}") --promptMultichoice $(printf '%q' "$(menu_choice fastfetch)") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"fastfetch\"'"

  # ffmpeg、mupdf-tools、pandoc 不在 e2e 實裝(見 TOOLS_FIRST 上方);只驗勾哪個才裝哪個、而且語法對。
  bold "▶ (渲染)ffmpeg、mupdf-tools、pandoc"
  check "沒勾時套件腳本不含 ffmpeg" \
    "! chezmoi execute-template < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -q ffmpeg"
  check "只勾 pandoc 時套件腳本只多 pandoc" \
    "chezmoi execute-template --override-data '{\"tools\":[\"pandoc\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl > /tmp/dm.sh && grep -q pandoc /tmp/dm.sh && ! grep -qE 'ffmpeg|mupdf-tools' /tmp/dm.sh && sh -n /tmp/dm.sh"
  check "三個都勾時套件腳本裝 ffmpeg、mupdf-tools、pandoc" \
    "chezmoi execute-template --override-data '{\"tools\":[\"ffmpeg\",\"mupdf-tools\",\"pandoc\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl > /tmp/dm.sh && grep -q ffmpeg /tmp/dm.sh && grep -q mupdf-tools /tmp/dm.sh && grep -q pandoc /tmp/dm.sh && sh -n /tmp/dm.sh"

  # 只勾 wakatime、沒勾 agent:不碰 agent 的 plugin。實裝那半在上面(agent 先勾、之後補勾 wakatime)。
  bold "▶ (渲染)只勾 wakatime 不裝 agent 的 WakaTime plugin"
  check "只勾 wakatime 時腳本不含 plugin 安裝指令" \
    "chezmoi execute-template --override-data '{\"tools\":[\"wakatime\"]}' < $scripts/run_onchange_after_install-wakatime.sh.tmpl > /tmp/waka.sh && sh -n /tmp/waka.sh && ! grep -qE 'plugin (install|add)|--install-extension' /tmp/waka.sh"
  check "wakatime + claude 時腳本只多 Claude Code 那段" \
    "chezmoi execute-template --override-data '{\"tools\":[\"wakatime\",\"claude\"]}' < $scripts/run_onchange_after_install-wakatime.sh.tmpl > /tmp/waka.sh && sh -n /tmp/waka.sh && grep -q 'plugin install claude-code-wakatime@wakatime' /tmp/waka.sh && ! grep -qE 'codex plugin|--install-extension' /tmp/waka.sh"
  check "wakatime + codex 時腳本只多 Codex CLI 那段" \
    "chezmoi execute-template --override-data '{\"tools\":[\"wakatime\",\"codex\"]}' < $scripts/run_onchange_after_install-wakatime.sh.tmpl > /tmp/waka.sh && sh -n /tmp/waka.sh && grep -q 'plugin add codex-cli-wakatime@wakatime' /tmp/waka.sh && ! grep -qE 'claude-code-wakatime|--install-extension' /tmp/waka.sh"
  check "wakatime + code-server 時腳本只多 code-server 那段" \
    "chezmoi execute-template --override-data '{\"tools\":[\"wakatime\",\"code-server\"]}' < $scripts/run_onchange_after_install-wakatime.sh.tmpl > /tmp/waka.sh && sh -n /tmp/waka.sh && grep -q 'install-extension WakaTime.vscode-wakatime' /tmp/waka.sh && ! grep -qE 'claude-code-wakatime|codex-cli-wakatime' /tmp/waka.sh"

  # 容器的 config 已經勾了 playwright-cli,要蓋成空的才是「沒勾」
  bold "▶ (渲染)playwright-cli"
  check "沒勾時安裝腳本是空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[]}' < $scripts/run_onchange_after_npm-install-playwright-cli.sh.tmpl | tr -d '[:space:]')\" ]"
}

# ===============================================================
# 目標:termux(代表原生 Termux)
# ===============================================================
# 映像模擬一台剛裝好的 Termux:什麼都沒裝。chezmoi 照 README 用 pkg 裝,
# git、openssh、python、jq、zsh 等由 chezmoi 的套件腳本裝。
# 基底映像的 entrypoint 會以 root 起動再 su 成 system(uid 1000),第一次執行時跑完
# bootstrap second stage;build 時先跑一次,之後的容器就不用再等。
# 容器裡沒有 Android 系統 CA,go-git 走 https 會 x509 失敗,所以設 SSL_CERT_FILE(真機不需要)。
setup_termux() {
  CTR_USER=system
  CTR_HOME=/data/data/com.termux/files/home
  docker build -q -t "$IMAGE" - >/dev/null <<'DOCKERFILE' || { red "✗ 建映像失敗"; exit 1; }
FROM termux/termux-docker:x86_64
ENV SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
RUN /entrypoint.sh bash -lc true
DOCKERFILE
  docker rm -f "$CTR" >/dev/null 2>&1 || true
  docker run -d --name "$CTR" "$IMAGE" sleep infinity >/dev/null
  make_fixtures
}

# Termux 基底:spec 的 zsh git curl vim openssh fastfetch,
# 加上 modify_ 自己要用的 jq(改 JSON)與 python(改 TOML,套件名是 python,指令是 python3),
# 以及預設安裝的命令列工具(Linux 走下載腳本,Termux 走 pkg)。
TERMUX_BASE=(zsh git curl vim openssh fastfetch jq python eza fzf bat ripgrep)
APT_LOG='$PREFIX/var/log/apt/history.log'
# nerd-fonts v3.5.1 Hack.tar.xz 裡 HackNerdFont-Regular.ttf 的 sha256,在主機上下載後算的
# (fc-query 確認 family=Hack Nerd Font、style=Regular)。URL 釘 tag,這個值不會變。
HACK_SHA256=8cba545f0ab36d8f313a448676df9988d6c679a014ffed863e52305844e7b113

scenario_termux() {
  # pkg 沒選過 mirror 時每次隨機挑一個,挑到壞的(404、卡住)整輪就紅。先放好 termux-change-repo
  # 選完會留下的 symlink,固定用預設那組;真機上 pkg 自己挑,不受影響。
  step "固定用預設 mirror" "ln -sfn \$PREFIX/etc/termux/mirrors/default \$PREFIX/etc/termux/chosen_mirrors"
  # init 輸出留在 ~/e2e-init.log,給 reload 那項檢查看。
  step "全新 Termux 跑 README 的安裝指令(pkg upgrade、pkg install chezmoi、init --apply)" \
    "$(install_cmd '~/e2e-init.log' --no-tty "${INIT_FLAGS[@]}")"
  check "pkg upgrade 有跑:沒有可升級的套件" "[ -z \"\$(apt list --upgradable 2>/dev/null | grep -v '^Listing')\" ]"
  check "chezmoi 用 pkg 裝" "dpkg-query -W -f='\${Status}' chezmoi | grep -q 'install ok installed'"
  check_git_remotes

  bold "▶ 第一次 apply 之後"
  for p in "${TERMUX_BASE[@]}"; do
    check "基底套件 $p 已安裝" "dpkg-query -W -f='\${Status}' $p | grep -q 'install ok installed'"
  done
  check "modify_ 產物:~/.claude/settings.json 關掉 chrome-devtools plugin" \
    "jq -e '.enabledPlugins[\"chrome-devtools-mcp@claude-plugins-official\"] == false' ~/.claude/settings.json"
  check "modify_ 產物:~/.codex/config.toml 有 codex-lb provider" \
    "python3 -c 'import tomllib,sys; c=tomllib.load(open(sys.argv[1],\"rb\")); assert c[\"model_provider\"]==\"codex-lb-gcp\" and \"codex-lb-gcp\" in c[\"model_providers\"]' ~/.codex/config.toml"
  check_codex_permissions
  check "modify_ 產物:~/.codex/personal.config.toml 有 chatgpt 登入" \
    "python3 -c 'import tomllib,sys; c=tomllib.load(open(sys.argv[1],\"rb\")); assert c[\"forced_login_method\"]==\"chatgpt\"' ~/.codex/personal.config.toml"
  check "modify_ 產物:~/.config/opencode/opencode.json 有 repo 的 model" \
    "jq -e '.model == \"codex-lb-gcp/gpt-6.1-sol\" and .mcp == {}' ~/.config/opencode/opencode.json"
  check "移除 chezmoi MCP 的 python 腳本被排除" "! chezmoi managed --include scripts | grep -q remove-chezmoi-mcp"
  check "沒有 tools 指令(Termux 沒有選單)" "[ ! -e ~/.local/bin/tools ]"
  check "~/.termux/font.ttf 是 Hack Nerd Font Regular" \
    "echo '$HACK_SHA256  .termux/font.ttf' | sha256sum -c - && grep -aq 'Hack Nerd Font' ~/.termux/font.ttf"
  check "~/.local/share/fonts/HackNerdFont-Regular.ttf 是指向 ~/.termux/font.ttf 的 symlink" \
    "[ \"\$(readlink ~/.local/share/fonts/HackNerdFont-Regular.ttf)\" = \"\$HOME/.termux/font.ttf\" ] && [ -f ~/.local/share/fonts/HackNerdFont-Regular.ttf ]"
  # 容器裡有 termux-reload-settings(termux-tools),但它呼叫的 am 要 /system/bin/app_process,
  # 沒有 Android 就失敗。腳本設計成失敗只警告、不讓 apply 失敗;這裡確認它真的跑了、走的是警告那條路。
  check "reload 腳本有跑(scriptState 有記錄)" \
    "chezmoi state dump --format json | jq -e '[.scriptState[].name] | index(\".chezmoiscripts/termux-reload-settings.sh\")'"
  check "reload 失敗只印警告(容器沒有 Android 的 app_process)" \
    "grep -q 'termux-reload-settings 失敗' ~/e2e-init.log"
  # init 沒給 --promptMultichoice 也跑完了,本身就證明沒出選單;再確認存下來的是空清單、選裝腳本一支都沒跑
  check "沒有選裝工具選單(config 的 tools 是空的)" "grep -qx '    tools = \\[\\]' ~/.config/chezmoi/chezmoi.toml"
  check "選裝工具的腳本一支都沒跑" \
    "! chezmoi state dump --format json | jq -r '.scriptState[].name' | grep -E '^$TOOL_SCRIPT_RE'"
  # Termux 的 chsh 寫的是 ~/.termux/shell 這個 symlink,不是 passwd。
  check_zsh_env "readlink -f ~/.termux/shell"

  # key 不在 init 時放:之後放好、再 apply 一次,authorized_keys 才補上(docs/new-machine-setup.md 的步驟)
  bold "▶ 之後才放 SSH key,再 apply"
  # Termux 的 openssh 套件安裝時會建一個空的 authorized_keys,所以看「沒有這把 key」而不是「沒有檔案」
  check "還沒放 key:authorized_keys 腳本渲染成空的、沒加任何東西" \
    "! grep -qF \"\$(awk '{print \$2}' $FIX/key.pub)\" ~/.ssh/authorized_keys 2>/dev/null && ! chezmoi status | grep -q termux-authorized-keys"
  step "放假 key(~/.ssh/henry5720、henry5720.pub)" \
    "cp $FIX/key ~/.ssh/henry5720 && cp $FIX/key.pub ~/.ssh/henry5720.pub && chmod 600 ~/.ssh/henry5720"
  check "放了 key 之後 authorized_keys 腳本待跑" "chezmoi status | grep -E '^.?R.*termux-authorized-keys'"
  check "apply exit 0" "chezmoi apply --no-tty"
  check "authorized_keys 有這把 key 一次、權限 600" \
    "[ \"\$(grep -cF \"\$(awk '{print \$2}' $FIX/key.pub)\" ~/.ssh/authorized_keys)\" = 1 ] && [ \"\$(stat -c %a ~/.ssh/authorized_keys)\" = 600 ]"
  # run_onchange_ 內容沒變就不會再跑,所以直接把渲染出來的腳本再跑一次
  check "腳本重跑不重複加" \
    "chezmoi execute-template < ~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_after_termux-authorized-keys.sh.tmpl | sh | grep -q '已有 henry5720 這把 key' && [ \"\$(grep -cF \"\$(awk '{print \$2}' $FIX/key.pub)\" ~/.ssh/authorized_keys)\" = 1 ]"

  bold "▶ 第二次 apply"
  check "沒有腳本待跑(chezmoi status 無 R)" "! chezmoi status | grep -E '^.?R'"
  check "換 shell 腳本已記為跑過、第二次不會再跑" \
    "chezmoi state dump --format json | jq -e '[.scriptState[].name] | index(\".chezmoiscripts/set-default-shell.sh\")' && ! chezmoi status | grep -q set-default-shell"
  check "第二次 apply exit 0、pkg 沒被呼叫" \
    "before=\$(grep -c '^Commandline:' $APT_LOG); chezmoi apply --no-tty && [ \"\$(grep -c '^Commandline:' $APT_LOG)\" = \"\$before\" ]"
  check "chezmoi verify 通過" "chezmoi verify"
}

# ===============================================================
# 主流程
# ===============================================================
case "$TARGET" in
  ubuntu|termux) ;;
  *) red "用法:$0 [ubuntu|termux]"; exit 2 ;;
esac

trap cleanup EXIT
bold "== e2e:$TARGET(容器 $CTR)"
"setup_$TARGET"
"scenario_$TARGET"

echo
if [ ${#FAILED[@]} -eq 0 ]; then
  green "== 全部通過"
else
  red "== ${#FAILED[@]} 項失敗:"
  printf '  - %s\n' "${FAILED[@]}" | while IFS= read -r l; do red "$l"; done
  exit 1
fi
