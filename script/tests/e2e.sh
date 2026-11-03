#!/bin/bash
# 容器 e2e:在全新容器裡照 README「新機器」那兩行官方指令裝 chezmoi、從本機 repo
# `chezmoi init --apply`,檢查機器上看得到的結果。
#
# 用法:
#   bash script/tests/e2e.sh [ubuntu|termux|noroot]     # 預設 ubuntu;noroot = 沒有 root 的 Ubuntu
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

# 用途與選裝工具選單。--promptChoice、--promptMultichoice 的 key 也是「提示文字」,值用 / 分隔。
# 用途的提示文字也在 README 免回答安裝那一行,三處要一字不差。
USE_PROMPT='用途（完整：全部選裝工具／精簡：zsh、常用 CLI、tailscale、btop／自訂：自己勾）'
use_choice() { echo "$USE_PROMPT=$1"; }  # use_choice 精簡 → --promptChoice 的值
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
# ffmpeg 一般用不到、相依套件一大串,不在這裡實裝,只做下面的渲染檢查。
# nvm 不是選項:勾了 codegraph 或 playwright-cli 就自動裝,這裡刻意只勾它們、不勾 nvm(見 check_tool nvm)。
# zsh、eza、fzf、bat、ripgrep、vim 以前在基底,現在是選裝工具;第一次照樣全勾(下面的 zsh 檢查要它們)。
TOOLS_FIRST=zsh/eza/fzf/bat/ripgrep/vim/fastfetch/btop/gh/code-server/tailscale/herdr/claude/codex/codegraph/headless-chrome/playwright-cli/agent-config

# 各用途的預設組合(獨立的期望值,不從 config 樣板抄)。完整 = 選單上全部,從 tool-menu 讀。
LEAN_TOML='    tools = ["zsh", "eza", "fzf", "bat", "ripgrep", "vim", "tailscale", "btop"]'
FULL_TOOLS=$(grep -E '^[a-z]' "$REPO/home/.chezmoitemplates/tool-menu" | cut -d' ' -f1 | paste -sd/)
toml_list() {  # toml_list a/b/c → config 裡 tools 那一行
  local t out=()
  for t in ${1//\// }; do out+=("\"$t\""); done
  local IFS=,; echo "    tools = [${out[*]}]" | sed 's/,/, /g'
}
# render_cmd <config> [chezmoi 參數...]:印出「用這份 config 渲染 config 樣板」的容器內指令(秘密給假值)。
# config 不存在時兩個問題都會真的問,沒給旗標就是預設值(--no-tty)。
render_cmd() {
  local cfg=$1; shift
  echo "chezmoi --config $cfg execute-template --init --no-tty $(printf '%q ' "${INIT_FLAGS[@]}" "$@") < ~/.local/share/chezmoi/home/.chezmoi.toml.tmpl"
}

# agent-config 的預設 remote 是 GitHub 的 HTTPS(check_git_remotes 驗)。安裝測試用
# AGENT_CONFIG_REMOTE 換成 $FIX/agent-config.git(見 make_fixtures),內容可控、不受上游變動影響;
# skillshare 本身照樣從網路裝、照樣 init/install/sync。

# 每個工具「裝好了」從外面怎麼看。這裡是獨立的期望值,不從安裝腳本抄。
declare -A TOOL_CHECK=(
  # zsh 整組:套件 + 外掛 clone + .zshrc;預設 shell、p10k 等細項在 check_zsh_env
  [zsh]="command -v zsh && [ -f ~/.zshrc ] && git -C ~/.config/zsh/powerlevel10k rev-parse --is-inside-work-tree"
  # Linux 從 GitHub release 下載到 ~/.local/bin(install-cli-tools);Termux 走 pkg
  [eza]="command -v eza"
  [fzf]="command -v fzf"
  [bat]="command -v bat"
  [ripgrep]="command -v rg"
  [vim]="command -v vim"
  [fastfetch]="command -v fastfetch"
  [btop]="dpkg-query -W -f='\${Status}' btop | grep -q 'install ok installed'"
  # gh 要是官方 apt 源那版(有 pin),不是 Ubuntu 套件庫的舊版
  [gh]="command -v gh && [ -f /etc/apt/preferences.d/github-cli ] && apt-cache policy gh | grep -A1 '^ \*\*\*' | grep -q cli.github.com"
  # nvm 不在選單上,跟著 codegraph、playwright-cli 自動裝;留在這裡是為了驗它有裝、腳本名進 TOOL_SCRIPT_RE
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

# skillshare 的 targets 名稱(排序後的 JSON 陣列)等於後面接的值:check "..." "$SS_TARGETS_IS '[\"claude\"]'"
SS_TARGETS_IS="test \"\$(skillshare target list --json | jq -c '[.targets[].name] | sort')\" ="
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
UBUNTU_BASE=(git curl jq python3)

# 以前在基底、拆成選裝工具的六項。不出選單的機器(Termux、非 Debian 系)自動帶入;
# 舊 config(沒有 toolsSchema)升級時自動加進 tools。config 裡那一行應該長這樣:
BASE_SPLIT_TOML='    tools = ["zsh", "eza", "fzf", "bat", "ripgrep", "vim"]'

# 選裝工具 eza、fzf、bat、ripgrep:Linux 由 run_onchange_after_install-cli-tools 從 GitHub release 下載到 ~/.local/bin。
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
  step "全新機器跑 README 的官方安裝指令,init --apply(用途選自訂,選單只勾一部分)" \
    "$(install_cmd '~/e2e-init.log' --no-tty "${INIT_FLAGS[@]}" --promptChoice "$(use_choice 自訂)" --promptMultichoice "$(menu_choice "$TOOLS_FIRST")")"
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
  # 選單沒勾 nvm,勾了 codegraph、playwright-cli 就要自動帶入
  check_tool nvm
  check_no_tool ttyd
  check_no_tool wakatime
  check_no_tool opencode
  check_no_tool ffmpeg
  # agent 有裝、wakatime 沒勾:不裝 plugin
  for a in "${!WAKA_PLUGIN[@]}"; do check_no_waka_plugin "$a"; done
  check "tools 指令部署成可執行檔" "[ -x ~/.local/bin/tools ]"
  # skillshare 的設定(modify_config.yaml.tmpl)是 modify_ 檔案,所有 after_ 腳本都在檔案部署之後跑。
  # 腳本找不到 config.yaml 會失敗;apply 有跑完、上面 agent-config 的檢查過了,就代表順序對。
  check "agent-config 用的是 chezmoi 放的 skillshare 設定(targets 有 claude、codex)" \
    "grep -q 'path: ~/.claude/skills' ~/.config/skillshare/config.yaml && [ -e ~/.agents/skills/e2e-hello ]"
  # skillshare 照勾的 client 產生 targets、extras(#211):勾了 claude、codex,沒勾 opencode
  check "skillshare targets 只有 claude、codex" "$SS_TARGETS_IS '[\"claude\",\"codex\"]'"
  check "指令檔連到 Claude、Codex 與 agent-commit" \
    "[ -L ~/.claude/CLAUDE.md ] && [ -L ~/.codex/AGENTS.md ] && [ -L ~/.config/agent-commit/instructions.md ]"
  check "沒勾 opencode:沒有 ~/.config/opencode、extras 沒有 opencode 的路徑" \
    "[ ! -e ~/.config/opencode ] && ! grep -q opencode ~/.config/skillshare/config.yaml"
  check "tailscale 在沒有 systemd 時跳過啟用,而不是失敗" "grep -q 'PID 1 不是 systemd' ~/e2e-init.log"
  # ssh client 補裝與 userspace tailscale 的 ProxyCommand 只給沒有 root 的機器(#216)
  check "有 root:ssh config 沒有 ProxyCommand、沒有補裝家目錄的 ssh" \
    "grep -q '^Host company-ec2\$' ~/.ssh/config && ! grep -qi ProxyCommand ~/.ssh/config && [ ! -e ~/.local/bin/ssh ] && [ ! -e ~/.local/opt/openssh ]"
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
  check "有 root 走 chsh:~/.bashrc 沒加切 zsh 那段、~/.profile 不是 dotfiles 補的" \
    "! grep -q 'dotfiles:互動式 bash 切到 zsh' ~/.bashrc && ! grep -q 'dotfiles' ~/.profile"
  check_cli_tools

  bold "▶ 第二次 init／apply"
  check "再 init 一次不問選單(沒給任何 prompt 旗標也能跑完)" "chezmoi init --no-tty"
  check "用途存自訂" "grep -qx '    machineUse = \"自訂\"' ~/.config/chezmoi/chezmoi.toml"
  check "選擇沒變" "grep -qF 'tools = [\"zsh\", \"eza\", \"fzf\", \"bat\", \"ripgrep\", \"vim\", \"fastfetch\", \"btop\", \"gh\", \"code-server\", \"tailscale\", \"herdr\", \"claude\", \"codex\", \"codegraph\", \"headless-chrome\", \"playwright-cli\", \"agent-config\"]' ~/.config/chezmoi/chezmoi.toml"
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
  check "用途保留自訂" "grep -qx '    machineUse = \"自訂\"' ~/.config/chezmoi/chezmoi.toml"
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

  # skillshare 的 targets、extras 每次 apply 都照選單釘回去(#211)
  bold "▶ 手動 skillshare target add,再 apply"
  step "手動加一個 gemini target" "mkdir -p ~/.gemini/skills && skillshare target add gemini ~/.gemini/skills"
  check "(對照)加進去了" "grep -q gemini ~/.config/skillshare/config.yaml"
  check "apply exit 0" "chezmoi apply --no-tty"
  check "手動加的 target 被蓋掉" "$SS_TARGETS_IS '[\"claude\",\"codex\"]' && ! grep -q gemini ~/.config/skillshare/config.yaml"
  check "chezmoi verify 通過" "chezmoi verify"

  # 新機器只勾一部分時不部署哪些檔:不用另開容器,用 --override-data 換 tools 看 chezmoi 會管哪些檔
  bold "▶ 沒勾的 client 不部署設定目錄"
  check "(對照)現在的勾選會管 ~/.codex、skillshare 的 config.yaml" \
    "chezmoi managed | grep -qx .codex && chezmoi managed | grep -qx .config/skillshare/config.yaml"
  check "只勾 claude + agent-config:不管 ~/.codex、~/.config/opencode" \
    "out=\$(chezmoi managed --override-data '{\"tools\":[\"claude\",\"agent-config\"]}') && grep -qx .claude <<<\"\$out\" && grep -qx .config/skillshare/config.yaml <<<\"\$out\" && ! grep -qE '^(\\.codex|\\.config/opencode)(/|\$)' <<<\"\$out\""
  check "沒勾 agent-config:不放 skillshare 的 config.yaml" \
    "! chezmoi managed --override-data '{\"tools\":[\"claude\",\"codex\"]}' | grep -q '^\\.config/skillshare'"

  bold "▶ 取消勾選 codex"
  step "config 的 tools 拿掉 codex" \
    "sed -i 's/, \"codex\"//' ~/.config/chezmoi/chezmoi.toml && ! grep -q '\"codex\"' ~/.config/chezmoi/chezmoi.toml"
  check "apply exit 0" "chezmoi apply --no-tty"
  check "skillshare targets 只剩 claude" "$SS_TARGETS_IS '[\"claude\"]'"
  check "extras 不再連 ~/.codex" "! grep -q 'path: ~/.codex' ~/.config/skillshare/config.yaml"
  check "chezmoi 不再管 ~/.codex" "! chezmoi managed | grep -q '^\\.codex'"
  check "已經同步出去的檔案留著(~/.codex 的設定、AGENTS.md、~/.agents/skills)" \
    "[ -f ~/.codex/config.toml ] && [ -e ~/.codex/AGENTS.md ] && [ -e ~/.agents/skills/e2e-hello ]"
  check "chezmoi verify 通過" "chezmoi verify"

  bold "▶ 套件清單加一個套件"
  step "yaml 的 ubuntu 清單加上 tree" "sed -i '/^    - python3\$/a\\    - tree' ~/.local/share/chezmoi/home/.chezmoidata/packages.yaml"
  check "套件腳本待跑(chezmoi status 有 R)" "chezmoi status | grep -E '^.?R.*install-packages'"
  check "apply exit 0" "chezmoi apply --no-tty"
  check "只裝了 tree" "tail -n 20 /var/log/apt/history.log | grep '^Commandline:' | tail -n 1 | grep -qx 'Commandline: apt-get install -y tree'"
  check "tree 已安裝" "dpkg-query -W -f='\${Status}' tree | grep -q 'install ok installed'"

  # 舊機器:config 是拆基底之前存的(tools 沒有那六項、沒有 toolsSchema)。
  # init 不加 --prompt 也要把六項補進 tools,不然下一次 apply 就不再管 .zshrc。
  bold "▶ 舊 config(拆基底之前)跑 init"
  step "把 config 改回舊格式:tools 拿掉六項、刪 toolsSchema、machineUse" \
    "sed -i -e '/^    toolsSchema = /d' -e '/^    machineUse = /d' -e '/^    tools = /{s/\"zsh\", \"eza\", \"fzf\", \"bat\", \"ripgrep\", \"vim\", //}' ~/.config/chezmoi/chezmoi.toml && ! grep -qE 'toolsSchema|machineUse|\"zsh\"' ~/.config/chezmoi/chezmoi.toml"
  check "init(不帶 --prompt、不給任何 prompt 旗標)exit 0" "chezmoi init --no-tty </dev/null"
  for t in zsh eza fzf bat ripgrep vim; do
    check "升級後 tools 有 $t" "grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml | grep -qF '\"$t\"'"
  done
  check "升級後寫回 toolsSchema = 2" "grep -qx '    toolsSchema = 2' ~/.config/chezmoi/chezmoi.toml"
  check "只有 tools、沒有用途的舊 config 存成自訂" "grep -qx '    machineUse = \"自訂\"' ~/.config/chezmoi/chezmoi.toml"
  check "chezmoi diff 不刪也不改 zsh 設定" "[ -z \"\$(chezmoi diff ~/.zshrc ~/.p10k.zsh ~/.config/zsh)\" ] && chezmoi managed | grep -qx .zshrc"
  check "再 init 一次 tools 不變(不會重複加)" \
    "before=\$(grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml) && chezmoi init --no-tty </dev/null && [ \"\$(grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml)\" = \"\$before\" ]"

  # 用途(#212):選了用途、選單沒改存用途,改了存自訂;WSL／ARM 拿濾過的預設組合比。
  bold "▶ (渲染)用途:預設組合展開、沒改存用途、有改存自訂"
  local cfg='~/.config/chezmoi/chezmoi.toml'   # 加引號:~ 留到容器裡才展開
  local use_is="grep -qx '    machineUse = \"%s\"' %s"   # printf "$use_is" <用途> <config>
  check "選精簡、選單不改:存精簡,tools 是精簡那八項" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice 精簡)") > /tmp/lean.toml && $(printf "$use_is" 精簡 /tmp/lean.toml) && grep -qxF '$LEAN_TOML' /tmp/lean.toml"
  check "精簡的機器樣板看到的 .tools 就是那八項" \
    "[ \"\$(chezmoi --config /tmp/lean.toml execute-template '{{ .tools | join \" \" }}')\" = 'zsh eza fzf bat ripgrep vim tailscale btop' ]"
  check "精簡的機器裝的是那八項:套件腳本有 zsh、vim、btop,下載腳本是 eza、fzf、bat、ripgrep" \
    "chezmoi --config /tmp/lean.toml execute-template < ~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_before_install-packages.sh.tmpl | grep -E '^for pkg in' > /tmp/lean-pkg && grep -qw zsh /tmp/lean-pkg && grep -qw vim /tmp/lean-pkg && grep -qw btop /tmp/lean-pkg && [ \"\$(chezmoi --config /tmp/lean.toml execute-template < ~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_after_install-cli-tools.sh.tmpl | grep -E '^want ' | cut -d' ' -f2 | paste -sd' ')\" = 'eza fzf bat rg' ]"
  check "精簡的機器選裝腳本只跑 tailscale(其他選裝工具的腳本都不跑)" \
    "[ \"\$(chezmoi --config /tmp/lean.toml --destination /tmp/lean-home --persistent-state /tmp/lean.boltdb apply --dry-run --verbose --no-tty 2>&1 | grep -oE '^diff --git a/$TOOL_SCRIPT_RE' | sed 's|.*/||' | sort -u | paste -sd' ')\" = install-tailscale ]"
  check "選完整、選單不改:存完整,tools 是選單上全部" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice 完整)") > /tmp/full.toml && $(printf "$use_is" 完整 /tmp/full.toml) && grep -qxF '$(toml_list "$FULL_TOOLS")' /tmp/full.toml"
  local full_no_ttyd=${FULL_TOOLS/\/ttyd\///}
  check "選完整後取消 ttyd:存自訂加 tools 清單" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice 完整)" --promptMultichoice "$(menu_choice "$full_no_ttyd")") > /tmp/full-ttyd.toml && $(printf "$use_is" 自訂 /tmp/full-ttyd.toml) && grep -qxF '$(toml_list "$full_no_ttyd")' /tmp/full-ttyd.toml"
  check "選精簡後多勾 gh:存自訂" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice 精簡)" --promptMultichoice "$(menu_choice zsh/eza/fzf/bat/ripgrep/vim/tailscale/btop/gh)") > /tmp/lean-gh.toml && $(printf "$use_is" 自訂 /tmp/lean-gh.toml) && grep -q '\"gh\"' /tmp/lean-gh.toml"
  local full_filtered=${FULL_TOOLS/\/headless-chrome\/playwright-cli/}
  check "WSL 選完整、選單不改:判斷為沒改(存完整、沒有 headless-chrome、playwright-cli)" \
    "$(render_cmd /tmp/u-none.toml --override-data '{"chezmoi":{"kernel":{"osrelease":"5.15.167.4-microsoft-standard-WSL2"}}}' --promptChoice "$(use_choice 完整)") > /tmp/full-wsl.toml && $(printf "$use_is" 完整 /tmp/full-wsl.toml) && grep -qxF '$(toml_list "$full_filtered")' /tmp/full-wsl.toml"
  check "ARM 選完整、選單不改:判斷為沒改" \
    "$(render_cmd /tmp/u-none.toml --override-data '{"chezmoi":{"arch":"arm64"}}' --promptChoice "$(use_choice 完整)") > /tmp/full-arm.toml && $(printf "$use_is" 完整 /tmp/full-arm.toml) && grep -qxF '$(toml_list "$full_filtered")' /tmp/full-arm.toml"
  # README 免回答安裝那一行的 --promptChoice 要跟樣板一字不差,不然 init 會報錯或停下來問
  check "README 免回答安裝那一行的用途提示跟樣板一致" \
    "grep -qF -e $(printf '%q' "--promptChoice \"$(use_choice 精簡)\"") ~/.local/share/chezmoi/README.md"
  check "用途不是三個之一時報 invalid choice" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice server)") 2>&1 | grep -q 'invalid choice'"
  # 存用途的機器:預設組合改了(這裡用「config 裡的 tools 是舊的」模擬),init 就跟上
  check "存精簡的機器,init(不帶 --prompt)tools 照現在的預設組合重算" \
    "sed 's/^    tools = .*/    tools = [\"gh\"]/' /tmp/lean.toml > /tmp/lean-stale.toml && chezmoi --config /tmp/lean-stale.toml init --no-tty </dev/null && $(printf "$use_is" 精簡 /tmp/lean-stale.toml) && grep -qxF '$LEAN_TOML' /tmp/lean-stale.toml"
  check "存精簡的機器跑 tools 那條(init --prompt --promptDefaults):保留精簡與勾選" \
    "cp /tmp/lean.toml /tmp/lean-prompt.toml && chezmoi --config /tmp/lean-prompt.toml init --prompt --no-tty --promptDefaults </dev/null && $(printf "$use_is" 精簡 /tmp/lean-prompt.toml) && grep -qxF '$LEAN_TOML' /tmp/lean-prompt.toml"
  check "存精簡的機器在 tools 改選完整:選單預設帶完整的組合" \
    "cp /tmp/lean.toml /tmp/lean-full.toml && chezmoi --config /tmp/lean-full.toml init --prompt --no-tty --promptDefaults --promptChoice $(printf '%q' "$(use_choice 完整)") </dev/null && $(printf "$use_is" 完整 /tmp/lean-full.toml) && grep -qxF '$(toml_list "$FULL_TOOLS")' /tmp/lean-full.toml"
  check "只有 tools(有 toolsSchema)、沒有用途的舊 config:init 不問、存自訂、tools 不變" \
    "sed '/^    machineUse = /d' $cfg > /tmp/no-use.toml && ! grep -q machineUse /tmp/no-use.toml && chezmoi --config /tmp/no-use.toml init --no-tty </dev/null && $(printf "$use_is" 自訂 /tmp/no-use.toml) && [ \"\$(grep '^    tools = ' /tmp/no-use.toml)\" = \"\$(grep '^    tools = ' $cfg)\" ]"

  # 原生 Termux 不出選單、不跑選裝腳本。這裡只驗樣板(把 .chezmoi.os 蓋成 android 來渲染);
  # 真的在 termux 容器跑 init 由 termux 目標負責。
  bold "▶ (渲染)Termux 不出選單、不跑選裝腳本"
  local android='{"chezmoi":{"os":"android"}}'
  check "android 的 config 樣板不問用途與選單,套精簡、濾掉 tailscale、btop(剩以前基底的那六項)" \
    "chezmoi execute-template --init --no-tty --override-data '$android' $(printf '%q ' "${INIT_FLAGS[@]}") < ~/.local/share/chezmoi/home/.chezmoi.toml.tmpl > /tmp/android.toml && grep -qxF '$BASE_SPLIT_TOML' /tmp/android.toml && grep -qx '    machineUse = \"精簡\"' /tmp/android.toml"
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
  check "非 Debian 系的 config 樣板不問選單,tools 是以前基底的那六項" \
    "chezmoi --config /tmp/fresh-fedora.toml execute-template --init --no-tty --override-data '$fedora' $(printf '%q ' "${INIT_FLAGS[@]}") < $tmpl/.chezmoi.toml.tmpl > /tmp/fedora.toml && grep -qxF '$BASE_SPLIT_TOML' /tmp/fedora.toml"
  local fedora_tools='{"chezmoi":{"osRelease":{"id":"fedora","idLike":""}},"tools":["fastfetch","gh","headless-chrome","playwright-cli","btop"]}'
  for f in run_onchange_before_install-packages run_once_after_set-default-shell \
           run_onchange_after_install-fastfetch run_onchange_after_install-gh run_onchange_after_install-headless-chrome \
           run_onchange_after_npm-install-playwright-cli; do
    check "非 Debian 系上 $f 渲染成空的(就算 tools 有勾)" \
      "[ -z \"\$(chezmoi execute-template --override-data '$fedora_tools' < $scripts/$f.sh.tmpl | tr -d '[:space:]')\" ]"
  done
  check "(對照)Debian 系(ID_LIKE 有 debian,例如 Linux Mint)照常出選單" \
    "chezmoi --config /tmp/fresh-mint.toml execute-template --init --no-tty --override-data '{\"chezmoi\":{\"osRelease\":{\"id\":\"linuxmint\",\"idLike\":\"ubuntu debian\"}}}' $(printf '%q ' "${INIT_FLAGS[@]}") --promptMultichoice $(printf '%q' "$(menu_choice fastfetch)") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"fastfetch\"'"

  # ffmpeg 不在 e2e 實裝(見 TOOLS_FIRST 上方);只驗勾了才裝、而且語法對。
  bold "▶ (渲染)ffmpeg"
  check "沒勾時套件腳本不含 ffmpeg" \
    "! chezmoi execute-template < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -q ffmpeg"
  check "勾 ffmpeg 時套件腳本裝 ffmpeg" \
    "chezmoi execute-template --override-data '{\"tools\":[\"ffmpeg\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl > /tmp/dm.sh && grep -q ffmpeg /tmp/dm.sh && sh -n /tmp/dm.sh"

  # nvm、mupdf-tools、pandoc 拿掉了(#209):選單沒有、舊機器存著也不報 invalid choice。
  bold "▶ (渲染)選單沒有 nvm、mupdf-tools、pandoc,舊 config 存著會被濾掉"
  check "tool-menu 沒有 nvm、mupdf-tools、pandoc" \
    "! grep -qE '^(nvm|mupdf-tools|pandoc) ' $tmpl/.chezmoitemplates/tool-menu"
  check "套件清單沒有 mupdf-tools、pandoc" \
    "! grep -qE 'mupdf-tools|pandoc' $tmpl/.chezmoidata/packages.yaml"
  # 舊 config:tools 存著 nvm、mupdf-tools、pandoc(還有更舊的 document-media)
  step "放一份舊 config" \
    "sed 's/^    tools = .*/    tools = [\"nvm\", \"mupdf-tools\", \"pandoc\", \"document-media\", \"codegraph\"]/' ~/.config/chezmoi/chezmoi.toml > /tmp/old.toml && grep -q mupdf-tools /tmp/old.toml"
  check "舊 config 再 init(不帶 --prompt)濾掉拿掉的項目" \
    "cp /tmp/old.toml /tmp/old-init.toml && chezmoi --config /tmp/old-init.toml init --no-tty </dev/null && grep -qx '    tools = \\[\"codegraph\", \"ffmpeg\"\\]' /tmp/old-init.toml"
  check "舊 config 跑 tools 那條(init --prompt)不報 invalid choice、濾掉拿掉的項目" \
    "cp /tmp/old.toml /tmp/old-prompt.toml && chezmoi --config /tmp/old-prompt.toml init --prompt --no-tty --promptDefaults </dev/null && grep -qx '    tools = \\[\"codegraph\", \"ffmpeg\"\\]' /tmp/old-prompt.toml"

  # 只勾 codegraph(沒勾 playwright-cli 等其他 node 相關項)也要先裝 nvm 再裝 codegraph。
  # 第一次 apply 已經裝了 nvm,這裡換一個空的 HOME,照 chezmoi 的順序(install-nvm 排在 npm-install-codegraph 前)
  # 把兩支渲染出來的腳本真的跑一次。
  bold "▶ 只勾 codegraph 也會自動裝 nvm"
  local only_cg='{"tools":["codegraph"]}'
  check "只勾 codegraph:install-nvm 不是空的" \
    "[ -n \"\$(chezmoi execute-template --override-data '$only_cg' < $scripts/run_onchange_after_install-nvm.sh.tmpl | tr -d '[:space:]')\" ]"
  check "只勾 playwright-cli:install-nvm 不是空的" \
    "[ -n \"\$(chezmoi execute-template --override-data '{\"tools\":[\"playwright-cli\"]}' < $scripts/run_onchange_after_install-nvm.sh.tmpl | tr -d '[:space:]')\" ]"
  check "沒勾 codegraph、playwright-cli:install-nvm 是空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"claude\",\"opencode\"]}' < $scripts/run_onchange_after_install-nvm.sh.tmpl | tr -d '[:space:]')\" ]"
  check "腳本順序:install-nvm 排在 npm-install-codegraph 前" \
    "[ \"\$(ls $scripts | grep -E 'install-nvm|npm-install-codegraph' | sort | head -n1)\" = run_onchange_after_install-nvm.sh.tmpl ]"
  check "只勾 codegraph:在空的 HOME 照順序跑兩支腳本,exit 0、codegraph 能跑" \
    "chezmoi execute-template --override-data '$only_cg' < $scripts/run_onchange_after_install-nvm.sh.tmpl > /tmp/cg-1.sh && chezmoi execute-template --override-data '$only_cg' < $scripts/run_onchange_after_npm-install-codegraph.sh.tmpl > /tmp/cg-2.sh && rm -rf /tmp/only-cg && mkdir /tmp/only-cg && env -i HOME=/tmp/only-cg PATH=/usr/local/bin:/usr/bin:/bin sh -c 'sh /tmp/cg-1.sh && sh /tmp/cg-2.sh' && env -i HOME=/tmp/only-cg PATH=/usr/local/bin:/usr/bin:/bin bash -c '. ~/.nvm/nvm.sh && codegraph --version'"

  # 基底只剩 git、curl、jq、python3;zsh、vim 走 toolPackages,eza 等走下載腳本,都是勾了才有。
  bold "▶ (渲染)基底縮小、zsh 等變選裝工具"
  local none='{"tools":[]}'
  # 前面「套件清單加一個套件」在 yaml 的 ubuntu 清單加了 tree,所以這裡是四項 + tree
  check "沒勾任何工具時套件腳本只有基底四項" \
    "chezmoi execute-template --override-data '$none' < $scripts/run_onchange_before_install-packages.sh.tmpl > /tmp/base.sh && sh -n /tmp/base.sh && grep -qx 'for pkg in git curl jq python3 tree; do' /tmp/base.sh"
  check "只勾 vim 時套件腳本多 vim、沒有 zsh" \
    "chezmoi execute-template --override-data '{\"tools\":[\"vim\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -E '^for pkg in' | grep -qw vim && ! chezmoi execute-template --override-data '{\"tools\":[\"vim\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -E '^for pkg in' | grep -qw zsh"
  check "沒勾 zsh:不部署 .zshrc、.p10k.zsh、zsh 外掛" \
    "! chezmoi managed --include all --override-data '$none' | grep -xE '\.zshrc|\.p10k\.zsh|\.config/zsh/(powerlevel10k|zsh-autosuggestions|zsh-z|zsh-syntax-highlighting)'"
  check "(對照)勾 zsh:.zshrc、.p10k.zsh、四個外掛都在" \
    "[ \"\$(chezmoi managed --include all --override-data '{\"tools\":[\"zsh\"]}' | grep -cxE '\.zshrc|\.p10k\.zsh|\.config/zsh/(powerlevel10k|zsh-autosuggestions|zsh-z|zsh-syntax-highlighting)')\" = 6 ]"
  check "沒勾 zsh:改預設 shell 的腳本渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '$none' < $scripts/run_once_after_set-default-shell.sh.tmpl | tr -d '[:space:]')\" ]"
  check "eza、fzf、bat、ripgrep 都沒勾時下載腳本渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '$none' < $scripts/run_onchange_after_install-cli-tools.sh.tmpl | tr -d '[:space:]')\" ]"
  check "只勾 fzf 時下載腳本只下載 fzf" \
    "chezmoi execute-template --override-data '{\"tools\":[\"fzf\"]}' < $scripts/run_onchange_after_install-cli-tools.sh.tmpl > /tmp/cli.sh && sh -n /tmp/cli.sh && [ \"\$(grep -E '^want ' /tmp/cli.sh)\" = 'want fzf install_fzf' ]"
  check "wakatime 腳本不用 unzip(用 python3 -m zipfile)" \
    "chezmoi execute-template --override-data '{\"tools\":[\"wakatime\"]}' < $scripts/run_onchange_after_install-wakatime.sh.tmpl > /tmp/waka.sh && ! grep -v '^ *#' /tmp/waka.sh | grep -qw unzip && grep -q '^ *python3 -m zipfile' /tmp/waka.sh"

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

  # 放最後:這之後 config 是精簡,上面的渲染檢查有幾項看的是現在的 config
  bold "▶ tools 把用途改成精簡:已經裝的工具不移除"
  check "tools 選精簡、選單直接 Enter,exit 0" \
    "~/.local/bin/tools --no-tty --promptDefaults --promptChoice $(printf '%q' "$(use_choice 精簡)") </dev/null"
  check "用途存精簡、tools 是精簡那八項" \
    "$(printf "$use_is" 精簡 "$cfg") && grep -qxF '$LEAN_TOML' $cfg"
  for t in claude gh herdr codegraph; do check_tool "$t"; done
  check "之後沒有腳本待跑" "! chezmoi status | grep -E '^.?R'"
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

# Termux 基底:git curl openssh,加上 modify_ 自己要用的 jq(改 JSON)與 python(改 TOML,套件名是 python,
# 指令是 python3)。zsh、eza、fzf、bat、ripgrep、vim 是自動帶入的選裝工具,走 pkg(toolPackages.termux)。
TERMUX_BASE=(git curl openssh jq python)
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
  # Termux 沒有選單、沒勾任何 agent:client 的設定目錄都不部署(#211)。
  check "沒勾的 client 不部署設定目錄(~/.claude、~/.codex、~/.config/opencode、skillshare 的 config.yaml)" \
    "[ ! -e ~/.claude ] && [ ! -e ~/.codex ] && [ ! -e ~/.config/opencode ] && [ ! -e ~/.config/skillshare/config.yaml ]"
  # modify_ 腳本在 Termux 上照樣跑得動(shebang、jq、python3):用 chezmoi cat 假裝勾了三個 client,
  # 看它算出來的內容,不實際部署。
  # codexLbApiKey 一併給:沒勾 codex、opencode 的機器不會問這個秘密(#210)
  local agents='{"tools":["claude","codex","opencode"],"codexLbApiKey":"e2e"}'
  check "(勾 claude 時)modify_ 產物:~/.claude/settings.json 關掉 chrome-devtools plugin" \
    "chezmoi cat --override-data '$agents' ~/.claude/settings.json | jq -e '.enabledPlugins[\"chrome-devtools-mcp@claude-plugins-official\"] == false'"
  check "(勾 codex 時)modify_ 產物:~/.codex/config.toml 有 codex-lb provider" \
    "chezmoi cat --override-data '$agents' ~/.codex/config.toml | python3 -c 'import tomllib,sys; c=tomllib.loads(sys.stdin.read()); assert c[\"model_provider\"]==\"codex-lb-gcp\" and \"codex-lb-gcp\" in c[\"model_providers\"]'"
  check "(勾 codex 時)modify_ 產物:~/.codex/personal.config.toml 有 chatgpt 登入" \
    "chezmoi cat --override-data '$agents' ~/.codex/personal.config.toml | python3 -c 'import tomllib,sys; c=tomllib.loads(sys.stdin.read()); assert c[\"forced_login_method\"]==\"chatgpt\"'"
  check "(勾 opencode 時)modify_ 產物:~/.config/opencode/opencode.json 有 repo 的 model" \
    "chezmoi cat --override-data '$agents' ~/.config/opencode/opencode.json | jq -e '.model == \"codex-lb-gcp/gpt-6.1-sol\" and .mcp == {}'"
  check "移除 chezmoi MCP 的 python 腳本被排除" "! chezmoi managed --include scripts | grep -q remove-chezmoi-mcp"
  check "沒有 tools 指令(Termux 沒有選單)" "[ ! -e ~/.local/bin/tools ]"
  # openssh 是 Termux 的基底套件;ssh client 補裝、userspace tailscale 的 ProxyCommand 只看 Linux(#216)
  check "ssh config 已部署、沒有 ProxyCommand、沒有補裝家目錄的 ssh" \
    "grep -q '^Host company-ec2\$' ~/.ssh/config && ! grep -qi ProxyCommand ~/.ssh/config && [ ! -e ~/.local/opt/openssh ]"
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
  # init 沒給 --promptMultichoice 也跑完了,本身就證明沒出選單;再確認存下來的是自動帶入的六項、選裝腳本一支都沒跑
  check "沒有用途與選裝工具選單(config 存精簡、tools 是濾掉 tailscale、btop 的六項)" \
    "grep -qxF '$BASE_SPLIT_TOML' ~/.config/chezmoi/chezmoi.toml && grep -qx '    machineUse = \"精簡\"' ~/.config/chezmoi/chezmoi.toml"
  check "沒裝 tailscale、btop" "! command -v tailscale && ! command -v btop"
  for t in zsh eza fzf bat ripgrep vim; do check_tool "$t"; done
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
# 目標:noroot(沒有 root 的 Ubuntu,代表別人給的帳號、TeamSync 工作區)
# ===============================================================
# 映像模擬雲端映像本來就有的東西:curl、ca-certificates、git、python3;**不裝 sudo**。
# 每個情境一個新使用者(家目錄是全新的),不在 sudo／admin／wheel 群組;wheeluser 只給 root 判斷的樣板檢查用。
# 要加檢查:精簡、完整各一個 noroot_<情境>_checks,照順序加在裡面,其他地方不用動。
NOROOT_USERS=(slim full wheeluser)

setup_noroot() {
  docker build -q -t "$IMAGE" - >/dev/null <<'DOCKERFILE' || { red "✗ 建映像失敗"; exit 1; }
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git python3 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd wheel \
 && useradd -m -s /bin/bash slim \
 && useradd -m -s /bin/bash full \
 && useradd -m -s /bin/bash -G wheel wheeluser
DOCKERFILE
  docker rm -f "$CTR" >/dev/null 2>&1 || true
  docker run -d --name "$CTR" --hostname dotfiles "$IMAGE" sleep infinity >/dev/null
  local u
  for u in "${NOROOT_USERS[@]}"; do use_user "$u"; make_fixtures; done
}

# 之後的 step／check 以這個使用者、在他的家目錄跑(make_fixtures 的 $FIX 也跟著換)
use_user() {
  CTR_USER=$1
  CTR_HOME=/home/$1
  FIX=$CTR_HOME/e2e-fixtures
}

# 在容器裡以 root 寫一個檔(內容從 stdin),給 stub 與共用的 source 用
put_root_file() {  # put_root_file <路徑> <權限>
  docker exec -i -u 0 "$CTR" sh -c "mkdir -p \"\$(dirname '$1')\" && cat > '$1' && chmod $2 '$1'"
}

SKIP_HEADER='== 沒有 root,以下步驟已略過'

# 每個情境都一樣的部分:全新家目錄跑 README 的安裝指令,看 exit code、家目錄外的檔案、略過彙整。
# 情境就是用途(精簡、完整),跟 README 免回答安裝那一行一樣只答用途、選單直接 Enter(--promptDefaults),
# 所以 config 存的是用途。完整 = 選單上全部(這個容器是 amd64、不是 WSL,選單全列)。
noroot_init() {  # noroot_init <用途>
  bold "▶ $1:沒有 root 跑 README 的安裝指令"
  step "沒有 sudo(command -v sudo 失敗)" "! command -v sudo"
  step "放時間標記(之後找家目錄外的新檔)" "touch ~/.e2e-marker"
  step "$1:init --apply exit 0" \
    "$(install_cmd '~/e2e-init.log' --no-tty "${INIT_FLAGS[@]}" --promptDefaults --promptChoice "$(use_choice "$1")")"
  check "$1:config 存用途 $1" "grep -qx '    machineUse = \"$1\"' ~/.config/chezmoi/chezmoi.toml"
  # /tmp 不算:上游的東西會留在那裡(get.chezmoi.io 的下載暫存目錄、Claude Code 的 socket),
  # 要守的是 /etc、/usr、/opt 這些系統目錄
  check "家目錄與 /tmp 以外沒有屬於這個使用者的新檔" \
    "out=\$(find / -xdev -user \$(id -un) -newer ~/.e2e-marker -not -path \"\$HOME\" -not -path \"\$HOME/*\" -not -path '/tmp/*' -not -path /tmp 2>/dev/null); echo \"\$out\"; [ -z \"\$out\" ]"
  check "/etc/shells 沒被改" "[ ! /etc/shells -nt ~/.e2e-marker ]"
  # 彙整之後不能再有別的輸出:看標頭之後每一行都是彙整的格式(「- 項目:」、縮排的續行)
  check "輸出最後是略過彙整" \
    "grep -q '^$SKIP_HEADER' ~/e2e-init.log && ! sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | sed 1d | grep -vE '^(- |    |\$)'"
}

# pty_bash <bash 參數>:印出容器內指令 —— 在 pty 裡開 bash,等輸出停下來後印 ZSH_VERSION 再 exit,
# 整段輸出存進 $out。互動式 bash 會被 ~/.bashrc 切成 zsh,ZV=:...: 中間就是 zsh 版本。
# heredoc 的結尾 PY 要自己一行,所以連 out=$( ) 一起印(呼叫端的 $( ) 會吃掉結尾換行)。
pty_bash() {
  echo "out=\$(python3 - $* <<'PY'
import os, pty, select, signal, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.execvp('bash', ['bash'] + sys.argv[1:])
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
        os.write(fd, b'echo ZV=:\$ZSH_VERSION:; exit\\n')
        sent = True
for _ in range(30):
    if os.waitpid(pid, os.WNOHANG)[0]:
        break
    time.sleep(0.1)
else:
    os.kill(pid, signal.SIGKILL)
sys.stdout.write(out.decode(errors='replace'))
PY
)"
}

# check_skipped <項目>:彙整裡有「- <項目>:」這一行
check_skipped() {
  check "略過彙整列出 $1" "sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | grep -qF -- '- $1:'"
}

# 容器沒有 ssh(git 的 Recommends 沒裝):apply 要把 openssh-client 解到家目錄(#216)
check_ssh_client() {
  check "系統沒有 ssh、補裝的 ssh 在 ~/.local/bin" \
    "[ ! -e /usr/bin/ssh ] && [ \"\$(command -v ssh)\" = \"\$HOME/.local/bin/ssh\" ] && [ -d ~/.local/opt/openssh ]"
  check "ssh -V 能跑" "ssh -V 2>&1 | grep -q OpenSSH"
  check "ssh-keygen 能產 key、讀回公鑰" \
    "rm -f /tmp/k-\$(id -un)* && ssh-keygen -q -t ed25519 -N '' -f /tmp/k-\$(id -un) && ssh-keygen -y -f /tmp/k-\$(id -un) | grep -q '^ssh-ed25519 '"
  # scp 預設呼叫 /usr/bin/ssh;wrapper 要讓它改用補裝的 ssh。連 127.0.0.1:22 被拒 = 真的叫到了 ssh
  check "scp 叫得到補裝的 ssh(不是找 /usr/bin/ssh)" \
    "out=\$(scp -o BatchMode=yes -o ConnectTimeout=3 /etc/hostname 127.0.0.1:/tmp/x 2>&1); echo \"\$out\"; grep -qi 'connection refused' <<<\"\$out\""
}

noroot_slim_checks() {
  check_skipped "系統套件"
  check "套件的手動方式是 sudo apt-get install,含 vim btop、不含已經裝到家目錄的 jq、zsh" \
    "sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | grep -F -- '- 系統套件:' > /tmp/pkgs && grep -q 'sudo apt-get install -y' /tmp/pkgs && grep -qw vim /tmp/pkgs && grep -qw btop /tmp/pkgs && ! grep -qw jq /tmp/pkgs && ! grep -qw zsh /tmp/pkgs"
  check_skipped "tailscale"
  check "tailscale 的手動方式是 userspace 模式(啟動、登入、常駐、ssh ProxyCommand)" \
    "s=\$(sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log) && grep -q -- '--tun=userspace-networking' <<<\"\$s\" && grep -q ' up\$' <<<\"\$s\" && grep -q 'enable-linger' <<<\"\$s\" && grep -q 'nc %h %p' <<<\"\$s\""
  check "預設 shell 不算略過(改由 ~/.bashrc 切 zsh)" \
    "! sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | grep -q 預設\ shell"
  check "zsh 用 zsh-bin 裝到 ~/.local/bin,版本 5.8" "~/.local/bin/zsh --version | grep -q '^zsh 5\.8 '"
  check "zsh -i 下 p10k 有載入" "$(zsh_ok '(( ${+functions[p10k]} )) && [[ -n $POWERLEVEL9K_LEFT_PROMPT_ELEMENTS ]]')"
  check "TERM 沒設時 zsh 裡是 xterm-256color" "[ \"\$(env -u TERM ~/.local/bin/zsh -i -c 'print -r -- \$TERM' 2>/dev/null)\" = xterm-256color ]"
  check "pty 開互動 bash 會切成 zsh" "$(pty_bash -i); echo \"\$out\" | tail -n 5; grep -q 'ZV=:5\.8:' <<<\"\$out\""
  check "非互動 bash 留在 bash(bash -c、bash -lc)" \
    "[ \"\$(bash -c 'echo \${ZSH_VERSION:-none}')\" = none ] && [ \"\$(bash -lc 'echo \${ZSH_VERSION:-none}')\" = none ]"
  check "~/.bashrc 原本的內容還在、切 zsh 那段只有一份" \
    "grep -q 'HISTCONTROL' ~/.bashrc && [ \"\$(grep -c 'dotfiles:互動式 bash 切到 zsh >>>' ~/.bashrc)\" = 1 ]"
  # skel 本來就有 ~/.profile;拿掉它再 apply 一次,看會不會補、login bash 會不會切成 zsh,最後放回去
  # (補的 .profile 只 source .bashrc,不加 ~/.local/bin 到 PATH,後面的檢查要 skel 那份)
  check "沒有 ~/.profile 時補一個 source ~/.bashrc 的;login 互動 bash 會切成 zsh" \
    "mv ~/.profile ~/.profile.skel && ~/.local/bin/chezmoi apply --no-tty --force && grep -qF '. \"\$HOME/.bashrc\"' ~/.profile && $(pty_bash -il) && echo \"\$out\" | tail -n 5 && grep -q 'ZV=:5\.8:' <<<\"\$out\"; r=\$?; mv -f ~/.profile.skel ~/.profile; exit \$r"
  check "jq 不用 root 從 GitHub release 裝到 ~/.local/bin" "~/.local/bin/jq --version"
  check "沒裝到的套件不會被當成已裝(btop 不存在)" "! command -v btop"
  for t in eza fzf bat ripgrep; do check_tool "$t"; done
  check "zsh 外掛照常 clone(要的是 git,不用 root)" "git -C ~/.config/zsh/powerlevel10k rev-parse --is-inside-work-tree"
  check_ssh_client
  # 勾了 tailscale、沒有 root、系統 tailscaled 沒在跑 = userspace:只有 company-ec2 帶 ProxyCommand
  check "ssh config:company-ec2 經 userspace tailscale 的 ProxyCommand" \
    "ssh -G company-ec2 | grep -E \"^proxycommand \$HOME/.local/bin/tailscale --socket=\$HOME/.local/state/tailscale/tailscaled.sock nc \""
  check "ssh config:其他 Host 沒有 ProxyCommand(company-ec2-public、github.com)" \
    "! ssh -G company-ec2-public | grep -qi '^proxycommand' && ! ssh -G github.com | grep -qi '^proxycommand'"

  bold "▶ 精簡:第二次 apply"
  step "放時間標記(之後看 zsh-bin 有沒有重裝)" "touch ~/.e2e-marker2"
  # 略過的步驟記在 run_onchange_ 的狀態裡,沒有 root 的狀況沒變就不重跑、不重印,也不重新下載
  check "第二次 apply exit 0、沒有任何略過或下載" \
    "out=\$(chezmoi apply --no-tty 2>&1); r=\$?; echo \"\$out\"; [ \$r = 0 ] && ! grep -qE '略過|安裝|下載' <<<\"\$out\""
  check "第二次 apply 沒有重裝 zsh-bin" \
    "[ ! ~/.local/bin/zsh -nt ~/.e2e-marker2 ] && [ ! ~/.local/share/zsh -nt ~/.e2e-marker2 ]"
  check "待跑的腳本只有略過彙整那支" \
    "[ \"\$(chezmoi status | grep -E '^.?R')\" = \"\$(chezmoi status | grep -E '^.?R.*zz-root-skipped-summary')\" ]"
}

noroot_full_checks() {
  for s in tailscale headless-chrome gh fastfetch code-server "nvm 與 Node" codegraph playwright-cli 系統套件; do
    check_skipped "$s"
  done
  check "已經有 ~/.bash_profile 時不補 ~/.profile" "[ -e ~/.bash_profile ] && [ ! -e ~/.profile ]"
  check "headless-chrome 的說明寫了缺系統函式庫" \
    "sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | grep -F -- '- headless-chrome:' | grep -q '系統函式庫'"
  # 不用 root 的照常裝好
  for t in eza fzf bat ripgrep herdr ttyd wakatime claude codex opencode agent-config; do check_tool "$t"; done
  check_ssh_client
  check "modify_ 用家目錄的 jq 照常產出 ~/.claude/settings.json" \
    "~/.local/bin/jq -e '.enabledPlugins[\"chrome-devtools-mcp@claude-plugins-official\"] == false' ~/.claude/settings.json"
  check "第二次 apply exit 0" "chezmoi apply --no-tty"
}

# 用 stub 模擬「系統層 tailscaled 已經在跑」:渲染 tailscale 腳本、在 PATH 前面放 stub 跑它。
# sudo 也放一支會記錄呼叫的 stub,證明整段跳過、沒有叫 sudo。
noroot_tailscale_running_checks() {
  bold "▶ 系統層 tailscaled 已經在跑:整段跳過、不叫 sudo"
  put_root_file /opt/e2e-stub/running/tailscale 755 <<'SH'
#!/bin/sh
[ "$1" = status ] && { echo '{"BackendState": "Running"}'; exit 0; }
exit 1
SH
  put_root_file /opt/e2e-stub/active/systemctl 755 <<'SH'
#!/bin/sh
[ "$*" = "is-active --quiet tailscaled" ]
SH
  for d in running active; do
    put_root_file "/opt/e2e-stub/$d/sudo" 755 <<'SH'
#!/bin/sh
echo "sudo $*" >> /tmp/e2e-sudo.log
exit 1
SH
  done
  # 沒有 root 時渲染出來的那版,與有 root 時那版(PATH 放一支會成功的 sudo,讓 has-root 判斷成有)都要跳過
  put_root_file /opt/e2e-stub/sudo-ok/sudo 755 <<'SH'
#!/bin/sh
exit 0
SH
  local tmpl='~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_after_install-tailscale.sh.tmpl'
  local ssh_tmpl='~/.local/share/chezmoi/home/private_dot_ssh/private_config.tmpl'
  local d how
  for d in running active; do
    for how in noroot root; do
      local pre=""; [ $how = root ] && pre="PATH=/opt/e2e-stub/sudo-ok:\$PATH "
      check "($d,$how 的渲染)tailscale 腳本整段跳過、exit 0、沒有叫 sudo" \
        "rm -f /tmp/e2e-sudo.log; ${pre}chezmoi execute-template --override-data '{\"tools\":[\"tailscale\"]}' < $tmpl > /tmp/ts.sh && out=\$(PATH=/opt/e2e-stub/$d:\$PATH sh /tmp/ts.sh 2>&1) && echo \"\$out\" && grep -q '已經在跑' <<<\"\$out\" && ! grep -q 略過 <<<\"\$out\" && [ ! -e /tmp/e2e-sudo.log ]"
    done
    # 系統 tailscaled 在跑就不是 userspace,ssh config 不加 ProxyCommand(#216)
    check "($d)ssh config 渲染出來沒有 ProxyCommand" \
      "! PATH=/opt/e2e-stub/$d:\$PATH chezmoi execute-template --override-data '{\"tools\":[\"tailscale\"]}' < $ssh_tmpl | grep -i ProxyCommand"
  done
  check "(對照,沒有 stub)ssh config 渲染出來有 ProxyCommand" \
    "chezmoi execute-template --override-data '{\"tools\":[\"tailscale\"]}' < $ssh_tmpl | grep -q ProxyCommand"
  check "沒勾 tailscale:ssh config 渲染出來沒有 ProxyCommand" \
    "! chezmoi execute-template --override-data '{\"tools\":[]}' < $ssh_tmpl | grep -i ProxyCommand"
  check "有 root(sudo 免密碼):ssh config 渲染出來沒有 ProxyCommand" \
    "! PATH=/opt/e2e-stub/sudo-ok:\$PATH chezmoi execute-template --override-data '{\"tools\":[\"tailscale\"]}' < $ssh_tmpl | grep -i ProxyCommand"
}

# root 判斷(.chezmoitemplates/has-root)只看樣板輸出。chezmoi 與 source 放到大家讀得到的地方,
# sudo 用 stub:exit 1 = 要密碼(或不在 sudoers),exit 0 = 免密碼。
noroot_has_root_checks() {
  bold "▶ (樣板)有沒有 root 的判斷"
  docker exec -u 0 "$CTR" sh -c "install -m 755 /home/slim/.local/bin/chezmoi /usr/local/bin/chezmoi && rm -rf /opt/e2e-src && cp -a /home/slim/e2e-fixtures/dotfiles /opt/e2e-src && chmod -R a+rX /opt/e2e-src"
  put_root_file /opt/e2e-stub/sudo-pw/sudo 755 <<'SH'
#!/bin/sh
exit 1
SH
  local has_root="chezmoi --source /opt/e2e-src --config /tmp/none.toml execute-template '{{ includeTemplate \"has-root\" . }}'"
  use_user wheeluser
  check "wheel 群組 + sudo 要密碼:判為有 root" "[ \"\$(PATH=/opt/e2e-stub/sudo-pw:\$PATH $has_root)\" = true ]"
  check "wheel 群組但沒有 sudo:判為沒有 root" "[ -z \"\$($has_root)\" ]"
  use_user slim
  check "不在群組 + sudo 要密碼:判為沒有 root" "[ -z \"\$(PATH=/opt/e2e-stub/sudo-pw:\$PATH $has_root)\" ]"
  check "不在群組 + sudo 免密碼(sudo -n true 成功):判為有 root" "[ \"\$(PATH=/opt/e2e-stub/sudo-ok:\$PATH $has_root)\" = true ]"
  check "沒有 sudo:判為沒有 root" "[ -z \"\$($has_root)\" ]"
}

# 已經有 ssh 的機器(stub 放在 PATH 前面)不補裝:用沒跑過 apply 的 wheeluser(沒有 root、家目錄乾淨),
# 渲染 install-ssh-client 直接跑。chezmoi 與 source 用 noroot_has_root_checks 放好的那份。
noroot_ssh_present_checks() {
  bold "▶ 已經有 ssh:不補裝"
  put_root_file /opt/e2e-stub/ssh/ssh 755 <<'SH'
#!/bin/sh
echo "OpenSSH_stub"
SH
  use_user wheeluser
  check "install-ssh-client 跳過、exit 0、家目錄沒有多出 ssh" \
    "chezmoi --source /opt/e2e-src --config /tmp/none.toml execute-template < /opt/e2e-src/home/.chezmoiscripts/run_onchange_after_install-ssh-client.sh.tmpl > /tmp/ssh-client.sh && [ -s /tmp/ssh-client.sh ] && out=\$(PATH=/opt/e2e-stub/ssh:\$PATH sh /tmp/ssh-client.sh 2>&1) && echo \"\$out\" && grep -q '已經有 ssh' <<<\"\$out\" && [ ! -e ~/.local/bin/ssh ] && [ ! -e ~/.local/opt/openssh ]"
  use_user slim
}

# root 帶著一般使用者的 HOME 跑(sudo -E chezmoi apply 這類誤用):一開頭就停、exit 非 0、家目錄沒有 root 的檔
noroot_root_foreign_home_checks() {
  bold "▶ 以 root 執行、\$HOME 是 slim 的家目錄"
  local cz="/home/slim/.local/bin/chezmoi"
  CTR_USER=root
  check "chezmoi apply 一開頭就停、exit 非 0、說明原因" \
    "export HOME=/home/slim; out=\$($cz apply --no-tty 2>&1); r=\$?; echo \"\$out\"; [ \$r != 0 ] && grep -q '以 root 執行' <<<\"\$out\""
  check "chezmoi init 也一開頭就停、exit 非 0" \
    "export HOME=/home/slim; out=\$($cz init --no-tty </dev/null 2>&1); r=\$?; echo \"\$out\"; [ \$r != 0 ] && grep -q '以 root 執行' <<<\"\$out\""
  check "家目錄沒有 root 擁有的檔" "out=\$(find /home/slim -user root); echo \"\$out\"; [ -z \"\$out\" ]"
  check "(對照)root 自己的家目錄照常渲染(不會被擋)" \
    "export HOME=/root; [ -z \"\$($cz --source /opt/e2e-src --config /tmp/none.toml execute-template '{{ template \"home-owner-guard\" . }}' 2>&1)\" ]"
  use_user slim
}

scenario_noroot() {
  use_user slim
  noroot_init 精簡
  noroot_slim_checks
  noroot_tailscale_running_checks

  use_user full
  # 「已經有 .bash_profile 就不補 .profile」:把 skel 的 .profile 改名成 .bash_profile(內容照用,PATH 一樣)
  step "完整:只有 ~/.bash_profile、沒有 ~/.profile" "mv ~/.profile ~/.bash_profile"
  noroot_init 完整
  noroot_full_checks

  noroot_has_root_checks
  noroot_ssh_present_checks
  noroot_root_foreign_home_checks
}

# ===============================================================
# 主流程
# ===============================================================
case "$TARGET" in
  ubuntu|termux|noroot) ;;
  *) red "用法:$0 [ubuntu|termux|noroot]"; exit 2 ;;
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
