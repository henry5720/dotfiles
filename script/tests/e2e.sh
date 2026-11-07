#!/bin/bash
# 容器 e2e:在全新容器裡照 README「新機器」那兩行官方指令裝 chezmoi、從本機 repo
# `chezmoi init --apply`,檢查機器上看得到的結果。
#
# 用法:
#   bash script/tests/e2e.sh [ubuntu|termux|noroot]     # 預設 ubuntu;noroot = 沒有 root 的 Ubuntu
# 主機要有 docker、chezmoi、python3(選單文字在主機上渲染,見 menu_labels)。
#
# 環境變數:
#   E2E_TAG=<字串>   容器名與映像 tag 的後綴,平行跑時避免撞名(預設 local)
#   E2E_KEEP=1       跑完不刪容器,方便 `docker exec -it <容器> bash` 進去看
#   AGENT_CONFIG_DIR=<路徑>  agent-config 的 checkout(預設 ~/.config/skillshare),找不到就直接失敗。
#                    改 agent-config 的 personal-chrome-attach 時指到自己的 worktree
#
# 測的是 repo 的工作目錄(含未 commit 的修改)加上 AGENT_CONFIG_DIR 指定的 agent-config checkout,不經過 GitHub。
# agent-config 在容器裡是假 remote(container.sh 的 make_fixtures):personal-chrome-attach 是從那份 checkout
# 複製的真腳本(工作目錄的現況,含未 commit),其他 skill 都是 fixture 自己寫的假檔。
# dotfiles 這邊:
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
# 主機有 GITHUB_TOKEN 就帶進去(只給變數名,值不出現在指令列):mise、chezmoi 的 gitHub* 函式打 GitHub API,
# 未登入每小時 60 次,noroot 完整那段一次就用掉不少。本機跑:GITHUB_TOKEN=$(gh auth token) bash script/tests/e2e.sh noroot
in_ctr() {
  OUT=$(docker exec ${GITHUB_TOKEN:+-e GITHUB_TOKEN} -u "$CTR_USER" -w "$CTR_HOME" "$CTR" bash -lc "$1" 2>&1)
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
  # e2e 用 AGENT_CONFIG_REMOTE 換成假 remote,這裡另外看沒換時的預設值,並確認不帶 key 真的 clone 得到。
  # Termux 裝不了 agent-config(#274),腳本渲染成空的,只在 Linux 驗
  [ "$TARGET" = termux ] && return 0
  check "agent-config 腳本預設 remote 是 HTTPS,而且不用 key 就讀得到" \
    "url=\$(chezmoi execute-template --override-data '{\"tools\":[\"agent-config\"]}' < ~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_after_install-agent-config.sh.tmpl | sed -n 's/^remote=\\\${AGENT_CONFIG_REMOTE:-\\(.*\\)}\$/\\1/p') && echo \"\$url\" && [ \"\$url\" = $GH_HTTPS/agent-config.git ] && GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false git ls-remote \"\$url\" HEAD | grep -q HEAD"
}

# 瀏覽器與轉發(#261、#278):一兩行指令的包裝都拿掉了,指令寫在 docs/remote-access/。
# ssh config 只有不帶轉發的 company-ec2,沒有 company-ec2-attach／-socks／-chrome 這些轉發別名;
# ~/.local/bin 沒有 remote-chrome、remote-chrome-headless。
check_no_browser_wrappers() {
  check "ssh config 沒有轉發別名,company-ec2 不帶任何轉發" \
    "[ -f ~/.ssh/config ] && ! grep -Eqi '^[[:space:]]*Host .*company-ec2-(attach|socks|chrome)' ~/.ssh/config && ! ssh -G company-ec2 | grep -Ei '^(localforward|remoteforward|dynamicforward) '"
  check "沒有 ~/.local/bin/remote-chrome、remote-chrome-headless" \
    "[ ! -e ~/.local/bin/remote-chrome ] && [ ! -L ~/.local/bin/remote-chrome ] && [ ! -e ~/.local/bin/remote-chrome-headless ] && [ ! -L ~/.local/bin/remote-chrome-headless ]"
}

# 接個人電腦日常的 Chrome(#264):~/.local/bin/personal-chrome-attach 指向 agent-config 的 browser-access skill,
# 勾了 playwright-cli 和 agent-config 才部署(.chezmoiignore);fixture 放的是 agent-config 的真腳本,見 container.sh。
ATTACH_TARGET='$HOME/.config/skillshare/skills/browser-access/scripts/personal-chrome-attach'
check_personal_chrome_attach() {  # check_personal_chrome_attach <有沒有勾 playwright-cli 和 agent-config:yes|no>
  if [ "$1" = yes ]; then
    check "personal-chrome-attach 指向 agent-config 的腳本" \
      "[ \"\$(readlink ~/.local/bin/personal-chrome-attach)\" = \"$ATTACH_TARGET\" ]"
    check "personal-chrome-attach 指得到檔案、可執行" "[ -f ~/.local/bin/personal-chrome-attach ] && [ -x ~/.local/bin/personal-chrome-attach ]"
  else
    check "沒有 ~/.local/bin/personal-chrome-attach(沒勾 playwright-cli、agent-config 不部署)" \
      "[ ! -e ~/.local/bin/personal-chrome-attach ] && [ ! -L ~/.local/bin/personal-chrome-attach ]"
  fi
}

# 秘密類 prompt 的假值。--promptString 的 key 是「提示文字」不是資料名稱,
# 所以要跟 home/.chezmoi.toml.tmpl 的提示文字一字不差;漏了會在 init 時看到 EOF 和那句提示。
# 憑證只在勾了用得到的工具時才問(#213),多給的旗標沒問到就不用。
SECRET_FLAGS=(
  --promptString 'code-server 密碼=e2e'
  --promptString 'codex-lb API key=e2e'
  --promptString 'Context7 API key（可留空）='
  --promptString 'WakaTime API key（可留空）='
)
GIT_FLAGS=(
  --promptString 'git user.name=e2e'
  --promptString 'git user.email=e2e@example.com'
)
INIT_FLAGS=("${SECRET_FLAGS[@]}" "${GIT_FLAGS[@]}")

# ===============================================================
# 共用檢查
# ===============================================================
# zsh 環境:兩個目標共用。預設 shell 怎麼查各平台不同,由呼叫端給指令。
ZSH_EXTERNALS=(zsh-autosuggestions zsh-z zsh-syntax-highlighting)

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
  check "~/.config/starship.toml 已部署" "grep -q '^format = ' ~/.config/starship.toml"
  # starship 有 init(PROMPT 交給 starship 畫)、插件有載入、stderr 是空的。
  # 這項沒有終端機,也守住「沒終端機時 fzf 整合不載入、不印 can't change option: zle」。
  check "zsh -i -c exit 不出錯、starship 與插件有載入" \
    "$(zsh_ok '[[ $STARSHIP_SHELL == zsh && $PROMPT == *starship* ]] && (( ${+functions[_zsh_autosuggest_start]} && ${+functions[zshz]} && ${+ZSH_HIGHLIGHT_VERSION} ))')"
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
  # `zsh -i -c` 不畫 prompt,所以要真的開互動 shell 看 starship 畫不畫得出來:
  # 用 python 的 pty 模擬終端機(兩邊都有 python3),等輸出停下來再送 exit。
  # exit 沒被吃掉、30 秒內結束,輸出裡有提示列的 ❯(starship.toml 的 character)才算過。
  check "互動 zsh(有 tty)畫出 starship 提示列、正常 exit" \
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
); echo \"\$out\" | tail -n 15; grep -qF '❯' <<<\"\$out\" && ! grep -qF 'ZSH-DID-NOT-EXIT' <<<\"\$out\""
}

# 用途與選裝工具選單。--promptChoice、--promptMultichoice 的 key 也是「提示文字」,值用 / 分隔。
# 用途的提示文字也在免回答安裝那一行(docs/new-machine-setup.md、docs/install/no-root-machine.md),要一字不差。
# 選項是英文代號(#222):full 完整、minimal 精簡、custom 自訂;config 的 machineUse 也存代號。
USE_PROMPT='用途：按一個字母（full 完整／minimal 精簡：只要 shell 體驗／custom 自訂）'
# 用途那題的選項是字母(chezmoi 的灰字顯示要按的字),config 存代號。呼叫端照樣給代號,這裡換成字母。
use_choice() {  # use_choice minimal → --promptChoice 的值(…=m)
  local l=$1
  case $1 in full) l=f ;; minimal) l=m ;; custom) l=c ;; esac
  echo "$USE_PROMPT=$l"
}
TOOLS_PROMPT='選裝工具（空白鍵勾選、Enter 確定；用途選錯按 Ctrl+C 重來）'
# 選單上的選項是「工具名 + 說明」,這台不建議／裝不了的後面再標原因,--promptMultichoice 要給這串。
# 排版與標註只寫在 home/.chezmoitemplates/tool-menu-labels:在主機上用主機的 chezmoi 渲染它
# (第一次 init 時容器裡還沒有 chezmoi)。環境先釘成容器的(amd64、非 WSL 的 Ubuntu),
# 主機自己是 WSL 或 ARM 也不影響;要模擬別的環境就給第二個參數,跟 --override-data 一樣的 JSON。
CTR_ENV='{"chezmoi":{"os":"linux","arch":"amd64","kernel":{"osrelease":"6.8.0-e2e"},"osRelease":{"id":"ubuntu","idLike":"debian"}}}'
menu_labels() {  # menu_labels [override-json] → 選單上每一行
  local env
  env=$(python3 -c '
import json, sys
def merge(a, b):
    for k, v in b.items():
        a[k] = merge(a[k], v) if isinstance(v, dict) and isinstance(a.get(k), dict) else v
    return a
print(json.dumps(merge(json.loads(sys.argv[1]), json.loads(sys.argv[2] or "{}"))))' "$CTR_ENV" "${1:-}") || return 1
  # --config 指向不存在的檔:不讀主機自己的 chezmoi 設定
  chezmoi --source "$REPO" --config "${TMPDIR:-/tmp}/dotfiles-e2e-no-config.toml" --no-tty execute-template \
    --override-data "$env" '{{ includeTemplate "tool-menu-labels" . }}'
}
# menu_choice a/b [override-json] → 「$TOOLS_PROMPT=a 的選單文字/b 的選單文字」
menu_choice() {
  local t out=() line labels
  labels=$(menu_labels "${2:-}") || { echo "渲染選單失敗" >&2; return 1; }
  for t in ${1//\// }; do
    line=$(grep -m1 "^$t " <<<"$labels") || { echo "選單沒有 $t" >&2; return 1; }
    out+=("$line")
  done
  (IFS=/; echo "$TOOLS_PROMPT=${out[*]}")
}
# 第一次 init 只勾這些;ttyd、wakatime、opencode 故意不勾,之後模擬 edit-config 補勾 wakatime。
# ffmpeg 不單獨勾(相依套件一大串);勾 snapserver(#290)會一併裝,check_snapserver 驗。
# node 刻意不勾:勾了 codegraph 或 playwright-cli 就自動裝 nvm 與 Node(見 check_tool node)。
# zsh、eza、fzf、bat、ripgrep、vim 以前在基底,現在是選裝工具;第一次照樣全勾(下面的 zsh 檢查要它們,還有 starship)。
TOOLS_FIRST=zsh/starship/eza/fzf/bat/ripgrep/vim/fastfetch/btop/gh/code-server/tailscale/cloudflared/herdr/claude/codex/snapserver/snapclient/codegraph/headless-chrome/playwright-cli/agent-config

# 各用途的預設組合(獨立的期望值,不從 config 樣板抄)。完整 = 選單上全部,從 tool-menu 讀。
LEAN_TOML='    tools = ["zsh", "starship", "eza", "fzf", "bat", "ripgrep", "vim", "fastfetch"]'
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
  # zsh 整組:套件 + 外掛 clone + .zshrc;預設 shell、提示列等細項在 check_zsh_env
  [zsh]="command -v zsh && [ -f ~/.zshrc ] && git -C ~/.config/zsh/zsh-autosuggestions rev-parse --is-inside-work-tree"
  # Linux 由 mise 裝(miseTools 的 always;這裡的 bash -l 沒有 shims,直接找 shim);Termux 走 pkg。設定檔跟著勾選部署
  [starship]="{ ~/.local/share/mise/shims/starship --version || starship --version; } && [ -f ~/.config/starship.toml ]"
  # 同上:Linux 由 mise 裝,Termux 走 pkg
  [eza]="[ -x ~/.local/share/mise/shims/eza ] || command -v eza"
  [fzf]="[ -x ~/.local/share/mise/shims/fzf ] || command -v fzf"
  [bat]="[ -x ~/.local/share/mise/shims/bat ] || command -v bat"
  [ripgrep]="[ -x ~/.local/share/mise/shims/rg ] || command -v rg"
  [vim]="command -v vim"
  [fastfetch]="[ -x ~/.local/share/mise/shims/fastfetch ] || command -v fastfetch"
  [btop]="[ -x ~/.local/share/mise/shims/btop ] || command -v btop"
  # gh 要是官方 apt 源那版(有 pin),不是 Ubuntu 套件庫的舊版
  [gh]="command -v gh && [ -f /etc/apt/preferences.d/github-cli ] && apt-cache policy gh | grep -A1 '^ \*\*\*' | grep -q cli.github.com"
  # nvm＋Node LTS;沒勾 node 時也會跟著 codegraph、playwright-cli 自動裝
  [node]=". ~/.nvm/nvm.sh && node --version"
  [code-server]="command -v code-server"
  [tailscale]="command -v tailscale"
  # Linux 由 mise 裝(miseTools 的 always)
  [cloudflared]="{ [ -x ~/.local/share/mise/shims/cloudflared ] && ~/.local/share/mise/shims/cloudflared --version; } || cloudflared --version"
  [herdr]="command -v herdr"
  [ttyd]="[ -x ~/.local/share/mise/shims/ttyd ] || command -v ttyd"
  # 官方位置:~/.wakatime/wakatime-cli 是指到 wakatime-cli-linux-<arch> 的 symlink
  [wakatime]="[ -L ~/.wakatime/wakatime-cli ] && ~/.wakatime/wakatime-cli --version"
  [claude]="command -v claude && claude --version"
  [codex]="command -v codex && codex --version"
  [opencode]="command -v opencode || [ -x ~/.opencode/bin/opencode ]"
  [ffmpeg]="dpkg-query -W -f='\${Status}' ffmpeg 2>/dev/null | grep -q 'install ok installed'"
  # apt 的 snapserver,連同它要的 ffmpeg(朗讀指令解 mp3)、開關指令 voice-out、朗讀指令 voice-out-speak
  # 與它跑 edge-tts 用的 uv(mise 裝,miseTools 的 snapserver;edge-tts 不另裝);服務與朗讀的檢查在 check_snapserver
  [snapserver]="command -v snapserver && command -v ffmpeg && [ -x ~/.local/bin/voice-out ] && [ -x ~/.local/bin/voice-out-speak ] && ~/.local/share/mise/shims/uv --version && [ ! -e ~/.local/bin/edge-tts ]"
  # Linux 是 apt 的 snapclient(收到串流由 check_snapclient 驗),Termux 是 pkg 的 snapcast-client
  [snapclient]="snapclient --version"
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

# 原生 Termux(#274):跟 Linux 同一套用途與選單,環境用 --override-data 模擬時給 ANDROID_ENV。
# Termux 的精簡跟 Ubuntu 的一樣:精簡只放 shell 體驗(#273),每一項 Termux 都能用 pkg 裝。
# TERMUX_LEAN 是同一份清單換成 / 分隔,給逐項檢查用。
ANDROID_ENV='{"chezmoi":{"os":"android"}}'
TERMUX_LEAN=$(grep -oE '"[a-z-]+"' <<<"$LEAN_TOML" | tr -d '"' | paste -sd/)
TERMUX_TOML=$LEAN_TOML

# 有 root 的 Ubuntu 也由 mise 裝的選裝工具(miseTools 的 always,#233),這裡列第一次 init 有勾的那幾個的指令名。
CLI_TOOLS=(eza fzf bat rg starship btop fastfetch)
SHIMS='~/.local/share/mise/shims'

check_cli_tools() {
  for t in "${CLI_TOOLS[@]}"; do
    check "$t 經 mise 的 shim 跑得起來、是 mise 管的那份" "$SHIMS/$t --version && ~/.local/bin/mise which $t"
    # zsh -i 開頭會跑 fastfetch,只看最後一行
    check "zsh 裡的 $t 是 mise 的 shim" "[ \"\$(zsh -i -c 'whence -p $t' 2>/dev/null | tail -n1)\" = \"\$HOME/.local/share/mise/shims/$t\" ]"
  done
  # apt 可能有同名的舊版(24.04 的 fzf 0.44 沒有 --zsh):shims 要排在系統目錄前面
  check "zsh 的 PATH 裡 mise shims 排在 /usr/bin 前面" \
    "p=\$(zsh -i -c 'print -l \$path' 2>/dev/null) && s=\$(grep -nx \"\$HOME/.local/share/mise/shims\" <<<\"\$p\" | cut -d: -f1) && u=\$(grep -nx /usr/bin <<<\"\$p\" | cut -d: -f1) && [ -n \"\$s\" ] && [ \"\$s\" -lt \"\$u\" ]"
  # 沒裝到要安靜略過(mise 下載失敗、架構不支援):把 shim 藏起來模擬,檢查完放回去
  local hide="" unhide=""
  for t in "${CLI_TOOLS[@]}"; do
    hide+="mv $SHIMS/$t $SHIMS/$t.e2e-hidden && "
    unhide+="mv $SHIMS/$t.e2e-hidden $SHIMS/$t && "
  done
  step "藏起 mise shims 的 ${CLI_TOOLS[*]}" "${hide}true"
  check "藏起後 zsh -i -c exit 不出錯" "$(zsh_ok 'true')"
  check "藏起後(有 tty)zsh -i -c exit 不出錯" "$(zsh_ok '[[ -n $TTY ]]' tty)"
  check_alias "藏起後 ll 退回 ls -alF" ll '$a == "ls -alF"'
  check_alias "藏起後 la 退回 ls -A" la '$a == "ls -A"'
  check_alias "藏起後 l 退回 ls -CF" l '$a == "ls -CF"'
  check_alias "藏起後 lt 沒定義" lt '$a == 未定義'
  step "放回 mise shims 的 ${CLI_TOOLS[*]}" "${unhide}true"
}

# ===============================================================
# playwright-cli:版本、錄影、show(#262)
# ===============================================================
# 0.1.23 起 show 的畫面才能點擊、打字;錄影要 playwright 自己的 ffmpeg(0.1.23 是 ffmpeg-1013)。
# 版本下限是獨立的期望值,不從安裝腳本讀。
PWCLI_MIN=0.1.23
PWCLI="cd \$(mktemp -d) && . ~/.nvm/nvm.sh && export PLAYWRIGHT_MCP_SANDBOX=false &&"
PWCLI_VERSION_OK="v=\$(playwright-cli --version) && echo \"版本 \$v\" && [ \"\$(printf '%s\\n' $PWCLI_MIN \"\$v\" | sort -V | head -n1)\" = $PWCLI_MIN ]"
PWCLI_SHOW_PORT=9377

check_playwright_cli() {
  bold "▶ playwright-cli:版本、錄影、show"
  check "playwright-cli --version ≥ $PWCLI_MIN" "$PWCLI $PWCLI_VERSION_OK"
  # 錄影要 ffmpeg:沒有的話 video-start 或 video-stop 會報錯、不會產出檔案
  check "video-start／video-stop 產出影片檔" \
    "$PWCLI playwright-cli -s=e2e-video open 'data:text/html,<p>a</p>' && playwright-cli -s=e2e-video video-start \$PWD/e2e.webm && playwright-cli -s=e2e-video goto 'data:text/html,<p>b</p>' && playwright-cli -s=e2e-video video-stop; playwright-cli -s=e2e-video close >/dev/null 2>&1; ls -l \$PWD; [ -s \$PWD/e2e.webm ]"
  # show --port 是阻塞的 http server:背景起、等它回應,再看 /proc/net/tcp{,6} 裡這個 port 的 LISTEN(狀態 0A)
  # 全部都是 127.0.0.1(0100007F),不能有 0.0.0.0 或 ::。指令照 verify-in-browser 的 hitl.md 帶 --host=127.0.0.1:
  # 不帶時聽 localhost,這個容器解析成 ::1,ssh -L 127.0.0.1:<port> 就連不到(第一次跑 e2e 實測)。
  local hex; hex=$(printf '%04X' $PWCLI_SHOW_PORT)
  check "show --port 起得來、只聽 127.0.0.1" \
    "$PWCLI true; playwright-cli show --port $PWCLI_SHOW_PORT --host=127.0.0.1 > show.log 2>&1 & p=\$!; ok=; for i in \$(seq 30); do curl -sf -o /dev/null http://127.0.0.1:$PWCLI_SHOW_PORT/ && ok=1 && break; sleep 1; done; cat show.log; l=\$(awk 'NR>1 && \$4==\"0A\" {print \$2}' /proc/net/tcp /proc/net/tcp6 | grep -i ':$hex\$'); echo \"LISTEN:\$l\"; kill \$p; playwright-cli show --kill >/dev/null 2>&1; [ -n \"\$ok\" ] && [ -n \"\$l\" ] && [ -z \"\$(grep -v '^0100007F:' <<<\"\$l\")\" ]"
  # 已經裝 0.1.22 的機器:安裝腳本內容一變 run_onchange_ 就重跑,要升上來(不是「已裝就跳過」)。
  # run_onchange_ 內容沒變不會再跑,所以裝回舊版後直接跑渲染出來的腳本。
  step "playwright-cli 裝回 0.1.22" ". ~/.nvm/nvm.sh && npm install -g @playwright/cli@0.1.22 && [ \"\$(playwright-cli --version)\" = 0.1.22 ]"
  check "0.1.22 的機器跑安裝腳本後 ≥ $PWCLI_MIN、exit 0" \
    "chezmoi execute-template < ~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_after_npm-install-playwright-cli.sh.tmpl | sh && $PWCLI $PWCLI_VERSION_OK"
}

# ===============================================================
# personal-chrome-attach:dry run(#264)
# ===============================================================
# 容器裡沒有人的 Chrome,只驗 ec2 單邊:網址拿得到、9555 轉得到 relay、沒人連進來會自己收乾淨、9555 被佔就失敗。
# 有 token 時網址不進腳本的輸出(agent 看得到、背景跑會存檔),只在 9555 的 /connect 頁給人複製。
# 不帶 -s:順便驗預設 session 名是 personal-chrome。
# 9555 有在聽 = /proc/net/tcp{,6} 有 :2553(9555)的 LISTEN(狀態 0A)。殘留 = 指令列還有這支、它的轉發或 session 的 daemon。
ATTACH_LISTEN="awk 'NR>1 && \$4==\"0A\" {print \$2}' /proc/net/tcp /proc/net/tcp6 | grep -i ':2553\$'"
ATTACH_LEFT="for f in /proc/[0-9]*/cmdline; do tr '\\0' ' ' < \$f 2>/dev/null; echo; done | grep -E 'personal-chrome-attach|cliDaemon.js personal-chrome' | grep -v grep"
ATTACH_TOKEN=e2e-attach-token-$$
# connect 網址:chrome-extension://<id>/connect.html?…,mcpRelayUrl 是 ws://127.0.0.1:9555/extension/…
ATTACH_URL_RE='^chrome-extension://[a-z]+/connect\.html\?.*mcpRelayUrl=ws%3A%2F%2F127\.0\.0\.1%3A9555%2Fextension%2F'

check_personal_chrome_attach_dry_run() {
  bold "▶ personal-chrome-attach:dry run"
  # 要放背景的指令前面先 `$PWCLI true;`:整串接在 $PWCLI 後面再加 & 的話,連 cd、nvm 都在背景的 subshell 跑,
  # $! 是那個 subshell,kill 不到腳本本身。/connect 頁的網址在 value="…" 裡,&amp; 換回 &。
  check "有 token:輸出不印網址、指到 /connect;/connect 回帶 token 的網址;/ 是 relay 的 404;session 是 personal-chrome" \
    "$PWCLI true; PLAYWRIGHT_MCP_EXTENSION_TOKEN=$ATTACH_TOKEN personal-chrome-attach --timeout=60 > ~/attach.log 2>&1 & p=\$!; for i in \$(seq 30); do grep -q '127.0.0.1:9555/connect' ~/attach.log && break; sleep 1; done; url=\$(curl -s http://127.0.0.1:9555/connect | grep -o 'value=\"[^\"]*\"' | sed 's/^value=\"//; s/\"\$//; s/&amp;/\\&/g'); code=\$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9555/); daemon=\$(for f in /proc/[0-9]*/cmdline; do tr '\\0' ' ' < \$f 2>/dev/null; echo; done | grep 'cliDaemon.js personal-chrome ' | grep -vc grep); kill \$p; wait \$p; cat ~/attach.log; echo \"curl /:\$code daemon:\$daemon\"; grep -E '$ATTACH_URL_RE' <<<\"\$url\" >/dev/null && grep -q '&token=$ATTACH_TOKEN' <<<\"\$url\" && echo '/connect 的網址 OK' && grep -q 'http://127.0.0.1:9555/connect' ~/attach.log && ! grep -q 'chrome-extension://' ~/attach.log && [ \"\$code\" = 404 ] && [ \"\$daemon\" -ge 1 ]"
  check "被中斷後 9555 放掉、沒有殘留 process" "sleep 2; ! $ATTACH_LISTEN && ! $ATTACH_LEFT"
  # 連腳本自己的輸出(~/attach.log)一起找:輸出也是 agent 看得到、會存檔的地方
  check "token 沒寫進任何檔案(含腳本的輸出)" "[ -s ~/attach.log ] && ! grep -rlI $ATTACH_TOKEN ~ /tmp 2>/dev/null"
  check "沒 token:印出 connect 網址(不帶 token);沒人連進來就在逾時(10 秒)內非 0 結束、9555 放掉、沒有殘留 process" \
    "$PWCLI s=\$SECONDS; out=\$(env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN personal-chrome-attach --timeout=10 2>&1); rc=\$?; e=\$((SECONDS - s)); sleep 1; echo \"\$out\"; echo \"rc=\$rc 秒數=\$e\"; url=\$(grep -o 'chrome-extension://[^ ]*' <<<\"\$out\"); grep -E '$ATTACH_URL_RE' <<<\"\$url\" >/dev/null && ! grep -q 'token=' <<<\"\$url\" && [ \$rc -ne 0 ] && [ \$e -le 20 ] && ! $ATTACH_LISTEN && ! $ATTACH_LEFT"
  check "9555 先被佔時失敗,說出是誰佔著" \
    "$PWCLI true; python3 -m http.server 9555 --bind 127.0.0.1 >/dev/null 2>&1 & h=\$!; sleep 1; out=\$(personal-chrome-attach --timeout=10 2>&1); rc=\$?; kill \$h; echo \"\$out\"; echo rc=\$rc; [ \$rc -ne 0 ] && grep -q 'http.server 9555' <<<\"\$out\""
}

# 朗讀串流服務(#290)。容器的 PID 1 不是 systemd、也沒有 systemctl:user service 起不來,
# 改成直接用部署的設定跑 snapserver,看三個 port 綁哪裡(容器裡 tailscale 沒登入,設定綁 127.0.0.1;
# 綁 tailnet IP 由 test_tool_env 用假的 tailscale 驗)。/proc/net/tcp 的位址是十六進位:
# 0100007F = 127.0.0.1;port 06A8 = 1704(串流)、06A9 = 1705(控制)、06F4 = 1780(網頁);狀態 0A = LISTEN。
check_snapserver() {
  check "snapserver 套件自帶的系統服務已停用(multi-user.target.wants 沒有它)" \
    "[ -f /lib/systemd/system/snapserver.service ] && [ ! -e /etc/systemd/system/multi-user.target.wants/snapserver.service ]"
  check "user service voice-out 已部署、預設 disabled(default.target.wants 沒有它)" \
    "[ -f ~/.config/systemd/user/voice-out.service ] && [ ! -e ~/.config/systemd/user/default.target.wants/voice-out.service ]"
  check "voice-out status:停止、exit 3" \
    "out=\$(voice-out status 2>&1); rc=\$?; echo \"\$out\"; [ \$rc = 3 ] && grep -q 停止 <<<\"\$out\""
  check "照部署的設定跑 snapserver:三個 port 只綁 127.0.0.1,沒有 0.0.0.0;pipe 建在 ~/.local/state/voice-out" \
    "mkdir -p ~/.local/state/voice-out && { snapserver --config=\$HOME/.config/snapserver/snapserver.conf > /tmp/snapserver.log 2>&1 & p=\$!; sleep 3; l=\$(awk '\$4 == \"0A\" {print \$2}' /proc/net/tcp /proc/net/tcp6); kill \$p; echo \"\$l\"; ok=1; for port in 06A8 06A9 06F4; do [ \"\$(grep -c \":\$port\$\" <<<\"\$l\")\" = 1 ] && grep -qx \"0100007F:\$port\" <<<\"\$l\" || ok=0; done; [ \$ok = 1 ] && [ -p ~/.local/state/voice-out/snapfifo ]; }"
  # 朗讀指令(#291)。pipe 是上一項 snapserver 建的;服務沒開 = 沒有人讀 pipe
  check "voice-out-speak:服務沒開時 1 秒內結束、exit 0" \
    "s=\$(date +%s%N); echo '{\"last_assistant_message\":\"沒人在聽\"}' | voice-out-speak; rc=\$?; ms=\$(( (\$(date +%s%N) - s) / 1000000 )); echo \"rc=\$rc \${ms}ms\"; [ \$rc = 0 ] && [ \$ms -lt 1000 ]"
  check "voice-out-speak:有人讀 pipe 時,真的用 uv 跑 edge-tts 唸成 PCM 寫進去(連網;bash -l 沒有 mise shims,要自己找到 uv)" \
    "cat ~/.local/state/voice-out/snapfifo > /tmp/speak.pcm & c=\$!; echo '{\"last_assistant_message\":\"**測試**朗讀。\"}' | timeout 60 voice-out-speak; rc=\$?; sleep 1; kill \$c 2>/dev/null; n=\$(stat -c %s /tmp/speak.pcm); echo \"rc=\$rc bytes=\$n\"; [ \$rc = 0 ] && [ \$n -gt 48000 ]"
}

# 收聽朗讀串流(#292)。容器沒有音效裝置:snapclient 用 file player 把收到的 PCM 寫進檔案。
# 跑 check_snapserver 同一份設定的 snapserver,往 pipe 寫一秒亂數,收到的檔案裡有非 0 的 byte 就是串流到了
# (沒有資料時 file player 寫的是靜音,全是 0)。
check_snapclient() {
  check "snapclient 套件自帶的系統服務已停用(multi-user.target.wants 沒有它)" \
    "[ -f /usr/lib/systemd/system/snapclient.service ] && [ ! -e /etc/systemd/system/multi-user.target.wants/snapclient.service ]"
  check "snapclient 連上照部署設定跑的 snapserver(127.0.0.1),收得到寫進 pipe 的音訊" \
    "mkdir -p ~/.local/state/voice-out && rm -f /tmp/snapclient.pcm && { snapserver --config=\$HOME/.config/snapserver/snapserver.conf > /tmp/snapserver.log 2>&1 & s=\$!; sleep 2; snapclient --host 127.0.0.1 --player file:filename=/tmp/snapclient.pcm > /tmp/snapclient.log 2>&1 & c=\$!; sleep 2; head -c 192000 /dev/urandom > ~/.local/state/voice-out/snapfifo; sleep 2; kill \$c \$s; tail -n 3 /tmp/snapclient.log; [ \"\$(tr -d '\\000' < /tmp/snapclient.pcm | head -c 1 | wc -c)\" = 1 ]; }"
}

# 容器裡做不到、刻意不驗的事:
# - tailscale:容器 PID 1 不是 systemd,`systemctl enable --now tailscaled` 一定會跳過。
#   只驗 tailscale 有裝、而且安裝腳本有印出「跳過 systemd」的訊息(證明走到了那個分支、沒有失敗)。
#   真的啟用 tailscaled 要在有 systemd 的機器上人工確認。
# - nvm／code-server／herdr／fastfetch／wakatime 都會連網抓上游 installer 或 release;
#   上游掛掉測試就會紅,這是預期的(它就是要驗真的裝得起來)。
scenario_ubuntu() {
  step "全新機器跑 README 的官方安裝指令,init --apply(用途選自訂,選單只勾一部分)" \
    "$(install_cmd '~/e2e-init.log' --no-tty "${INIT_FLAGS[@]}" --promptChoice "$(use_choice custom)" --promptMultichoice "$(menu_choice "$TOOLS_FIRST")")"
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
  # 選單沒勾 node,勾了 codegraph、playwright-cli 就要自動帶入
  check_tool node
  # 有 root 也用 mise,但只裝單一執行檔的(#233);vim 這類 conda 的照 apt(上面 check_tool vim 是 apt 那支)。
  # uv 是 snapserver 帶的(照 miseTools 的工具名排序,在 starship 前面)
  check "有 root:mise 清單是勾了的單一執行檔工具,沒有 vim" \
    "[ -x ~/.local/bin/mise ] && [ \"\$(grep -oE '^\"[^\"]+\"' ~/.config/mise/conf.d/dotfiles.toml | tr -d '\"' | paste -sd' ')\" = 'bat btop cloudflared eza fastfetch fzf ripgrep uv starship' ]"
  check "有 root:vim、btop 的來源(vim 是 apt、btop 不是 apt)" \
    "dpkg-query -W -f='\${Status}' vim | grep -q 'install ok installed' && ! dpkg-query -W -f='\${Status}' btop 2>/dev/null | grep -q 'install ok installed'"
  check_no_tool ttyd
  check_no_tool wakatime
  check_no_tool opencode
  check_snapserver
  check_snapclient
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
    "grep -Eq '^Host company-ec2( |\$)' ~/.ssh/config && ! grep -qi ProxyCommand ~/.ssh/config && [ ! -e ~/.local/bin/ssh ] && [ ! -e ~/.local/opt/openssh ]"
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
  check_no_browser_wrappers
  check_personal_chrome_attach yes
  check_codex_permissions
  check_zsh_env "getent passwd \$(id -un) | cut -d: -f7"
  check "有 root 走 chsh:~/.bashrc 沒加切 zsh 那段、~/.profile 不是 dotfiles 補的" \
    "! grep -q 'dotfiles:互動式 bash 切到 zsh' ~/.bashrc && ! grep -q 'dotfiles' ~/.profile"
  # 勾了 starship:bash 也用同一份設定(#194)。原本的 .bashrc 內容留著
  check "~/.bashrc 加了 starship 那段一份、原本的內容還在" \
    "grep -q 'HISTCONTROL' ~/.bashrc && [ \"\$(grep -c 'dotfiles:starship 提示列 >>>' ~/.bashrc)\" = 1 ]"
  check "互動 bash 載入 starship" "[ \"\$(bash -ic 'echo \$STARSHIP_SHELL' 2>/dev/null)\" = bash ]"
  check_cli_tools
  check_playwright_cli
  check_personal_chrome_attach_dry_run

  bold "▶ 第二次 init／apply"
  check "再 init 一次不問選單(沒給任何 prompt 旗標也能跑完)" "chezmoi init --no-tty"
  check "用途存自訂" "grep -qx '    machineUse = \"custom\"' ~/.config/chezmoi/chezmoi.toml"
  check "選擇沒變" "grep -qF 'tools = [\"zsh\", \"starship\", \"eza\", \"fzf\", \"bat\", \"ripgrep\", \"vim\", \"fastfetch\", \"btop\", \"gh\", \"code-server\", \"tailscale\", \"cloudflared\", \"herdr\", \"claude\", \"codex\", \"snapserver\", \"snapclient\", \"codegraph\", \"headless-chrome\", \"playwright-cli\", \"agent-config\"]' ~/.config/chezmoi/chezmoi.toml"
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
  check "用途保留自訂" "grep -qx '    machineUse = \"custom\"' ~/.config/chezmoi/chezmoi.toml"
  check "之後沒有腳本待跑" "! chezmoi status | grep -E '^.?R'"

  # 不經選單、直接用 chezmoi edit-config 改 [data] tools 那一行再 apply,也要能裝。
  # edit-config 只是開編輯器,這裡直接 sed config 模擬。
  bold "▶ edit-config 在 tools 多加 wakatime"
  # 模擬以前裝過 zsh 外掛的機器:clone 還在,apply 之後要被 .chezmoiremove 清掉、zsh 不再載入
  step "放一份舊的 zsh 外掛 clone" \
    "mkdir -p ~/.config/zsh/wakatime-zsh-plugin && echo '_wakatime_heartbeat() { :; }' > ~/.config/zsh/wakatime-zsh-plugin/wakatime.plugin.zsh"
  # 模擬用過 p10k 的機器(#194):設定、主題 clone、gitstatusd 與 instant prompt 的快取,apply 之後都要清掉
  step "放一份舊的 p10k 檔案" \
    "mkdir -p ~/.config/zsh/powerlevel10k ~/.cache/gitstatus && touch ~/.p10k.zsh ~/.config/zsh/powerlevel10k/powerlevel10k.zsh-theme ~/.cache/gitstatus/gitstatusd ~/.cache/p10k-instant-prompt-\$(id -un).zsh"
  # 模擬 #233 以前的機器:install-cli-tools 下載到 ~/.local/bin 的舊版,apply 之後要被 .chezmoiremove 清掉,
  # 不然排在 mise shims 前面
  step "放一份舊的 ~/.local/bin/fzf、rg" \
    "printf '#!/bin/sh\\necho old\\n' > ~/.local/bin/fzf && cp ~/.local/bin/fzf ~/.local/bin/rg && chmod +x ~/.local/bin/fzf ~/.local/bin/rg"
  # 模擬 #261 以前的機器:部署過 remote-chrome(WSL 開 Windows Chrome 那支)的 symlink,apply 之後要被 .chezmoiremove 清掉
  step "放一份舊的 ~/.local/bin/remote-chrome、remote-chrome-headless(#278 以前部署過)" \
    "ln -sfn ~/.config/skillshare/skills/remote-chrome/scripts/remote-chrome ~/.local/bin/remote-chrome && ln -sfn ~/.config/skillshare/skills/remote-chrome/scripts/remote-chrome-headless ~/.local/bin/remote-chrome-headless"
  step "config 的 tools 加上 wakatime" \
    "sed -i 's/^    tools = \\[\\(.*\\)\\]\$/    tools = [\\1, \"wakatime\"]/' ~/.config/chezmoi/chezmoi.toml && grep -q '\"wakatime\"\\]\$' ~/.config/chezmoi/chezmoi.toml"
  check "只有 wakatime 的安裝腳本待跑" \
    "[ \"\$(chezmoi status | grep -E '^.?R')\" = \"\$(chezmoi status | grep -E '^.?R.*install-wakatime')\" ] && chezmoi status | grep -qE '^.?R.*install-wakatime'"
  check "apply exit 0" "chezmoi apply --no-tty"
  check_tool wakatime
  # zsh 外掛不再裝(#176):不 clone、zshrc 也不載入
  check "沒有 clone zsh 的 WakaTime 外掛" "[ ! -e ~/.config/zsh/wakatime-zsh-plugin ]"
  check "舊的 p10k 檔案都清掉了、zsh 外掛還在" \
    "[ ! -e ~/.p10k.zsh ] && [ ! -e ~/.config/zsh/powerlevel10k ] && [ ! -e ~/.cache/gitstatus ] && ! ls ~/.cache/p10k-* 2>/dev/null && [ -d ~/.config/zsh/zsh-z ]"
  check "舊的 ~/.local/bin/fzf、rg 清掉了,zsh 用的是 mise 那份" \
    "[ ! -e ~/.local/bin/fzf ] && [ ! -e ~/.local/bin/rg ] && [ \"\$(zsh -i -c 'whence -p fzf' 2>/dev/null | tail -n1)\" = \"\$HOME/.local/share/mise/shims/fzf\" ]"
  check "舊的 ~/.local/bin/remote-chrome、remote-chrome-headless 清掉了" "[ ! -L ~/.local/bin/remote-chrome ] && [ ! -L ~/.local/bin/remote-chrome-headless ]"
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
  # 第一次沒勾 wakatime,所以 WakaTime key 沒問過、config 裡沒有(#213);勾了之後 init 才問
  check "(對照)第一次沒勾 wakatime:config 裡沒有 wakatimeApiKey" "! grep -q wakatimeApiKey ~/.config/chezmoi/chezmoi.toml"
  check "之後 init 不給 WakaTime key:會問(--no-tty 讀到 EOF 失敗)" \
    "! out=\$(chezmoi init --no-tty </dev/null 2>&1) && echo \"\$out\" && grep -q 'WakaTime API key' <<<\"\$out\""
  check "之後 init(不帶 --prompt)只給 WakaTime key:存下來、tools 不變" \
    "chezmoi init --no-tty --promptString 'WakaTime API key（可留空）=e2e-waka' </dev/null && grep -qx '    wakatimeApiKey = \"e2e-waka\"' ~/.config/chezmoi/chezmoi.toml && grep -q '^    tools = .*\"wakatime\"\\]\$' ~/.config/chezmoi/chezmoi.toml && grep -qF '\"agent-config\", \"wakatime\"]' ~/.config/chezmoi/chezmoi.toml"
  check "WakaTime key 寫進 ~/.wakatime.cfg" "chezmoi cat ~/.wakatime.cfg | grep -qx 'api_key = e2e-waka'"

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
  # 那時還沒有 starship(提示列是 zsh 附帶的 p10k),一起拿掉;升級要補回六項加 starship
  step "把 config 改回舊格式:tools 拿掉六項與 starship、刪 toolsSchema、machineUse" \
    "sed -i -e '/^    toolsSchema = /d' -e '/^    machineUse = /d' -e '/^    tools = /{s/\"zsh\", //;s/\"starship\", //;s/\"eza\", //;s/\"fzf\", //;s/\"bat\", //;s/\"ripgrep\", //;s/\"vim\", //}' ~/.config/chezmoi/chezmoi.toml && ! grep -qE 'toolsSchema|machineUse|\"zsh\"|\"starship\"' ~/.config/chezmoi/chezmoi.toml"
  check "init(不帶 --prompt、不給任何 prompt 旗標)exit 0" "chezmoi init --no-tty </dev/null"
  for t in zsh eza fzf bat ripgrep vim; do
    check "升級後 tools 有 $t" "grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml | grep -qF '\"$t\"'"
  done
  check "升級後 tools 有 starship、只有一個" "[ \"\$(grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml | grep -o '\"starship\"' | wc -l)\" = 1 ]"
  check "升級後寫回 toolsSchema = 3" "grep -qx '    toolsSchema = 3' ~/.config/chezmoi/chezmoi.toml"
  check "只有 tools、沒有用途的舊 config 存成自訂" "grep -qx '    machineUse = \"custom\"' ~/.config/chezmoi/chezmoi.toml"
  check "chezmoi diff 不刪也不改 zsh 設定" "[ -z \"\$(chezmoi diff ~/.zshrc ~/.config/starship.toml ~/.config/zsh)\" ] && chezmoi managed | grep -qx .zshrc"
  check "再 init 一次 tools 不變(不會重複加)" \
    "before=\$(grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml) && chezmoi init --no-tty </dev/null && [ \"\$(grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml)\" = \"\$before\" ]"

  # 第 2 版(#194 以前)勾了 zsh 的自訂 config:當時 zsh 附帶 p10k,init 自動補勾 starship;第 3 版之後照存的勾選
  bold "▶ (渲染)toolsSchema 2 → 3:勾了 zsh 的補勾 starship"
  local no_ss="sed -e 's/\"starship\", //' -e 's/, \"starship\"//' -e 's/^    toolsSchema = .*/    toolsSchema = %s/' ~/.config/chezmoi/chezmoi.toml"
  check "第 2 版、有 zsh 沒 starship:init 後補上 starship、寫回 3" \
    "$(printf "$no_ss" 2) > /tmp/schema2.toml && ! grep -q '\"starship\"' /tmp/schema2.toml && chezmoi --config /tmp/schema2.toml init --no-tty </dev/null && grep '^    tools = ' /tmp/schema2.toml | grep -qF '\"starship\"' && grep -qx '    toolsSchema = 3' /tmp/schema2.toml"
  check "第 3 版、有 zsh 沒 starship:init 後還是沒有 starship(使用者自己取消的)" \
    "$(printf "$no_ss" 3) > /tmp/schema3.toml && chezmoi --config /tmp/schema3.toml init --no-tty </dev/null && ! grep -q '\"starship\"' /tmp/schema3.toml"
  check "第 2 版、沒有 zsh:不補 starship" \
    "$(printf "$no_ss" 2) | sed 's/\"zsh\", //' > /tmp/schema2-nozsh.toml && ! grep -q '\"zsh\"' /tmp/schema2-nozsh.toml && chezmoi --config /tmp/schema2-nozsh.toml init --no-tty </dev/null && ! grep -q '\"starship\"' /tmp/schema2-nozsh.toml"

  # 用途(#212):選了用途、選單沒改存用途,改了存自訂;WSL／ARM 拿濾過的預設組合比。
  bold "▶ (渲染)用途:預設組合展開、沒改存用途、有改存自訂"
  local cfg='~/.config/chezmoi/chezmoi.toml'   # 加引號:~ 留到容器裡才展開
  local use_is="grep -qx '    machineUse = \"%s\"' %s"   # printf "$use_is" <用途> <config>
  check "選精簡、選單不改:存精簡,tools 是精簡那八項" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice minimal)") > /tmp/lean.toml && $(printf "$use_is" minimal /tmp/lean.toml) && grep -qxF '$LEAN_TOML' /tmp/lean.toml"
  check "精簡的機器樣板看到的 .tools 就是那八項" \
    "[ \"\$(chezmoi --config /tmp/lean.toml execute-template '{{ .tools | join \" \" }}')\" = 'zsh starship eza fzf bat ripgrep vim fastfetch' ]"
  check "精簡的機器裝的是那八項:套件腳本有 zsh、vim(沒有 fastfetch),mise 清單是 bat、eza、fastfetch、fzf、ripgrep、starship" \
    "chezmoi --config /tmp/lean.toml execute-template < ~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_before_install-packages.sh.tmpl | grep -E '^for pkg in' > /tmp/lean-pkg && grep -qw zsh /tmp/lean-pkg && grep -qw vim /tmp/lean-pkg && ! grep -qw fastfetch /tmp/lean-pkg && [ \"\$(chezmoi --config /tmp/lean.toml execute-template < ~/.local/share/chezmoi/home/dot_config/mise/conf.d/dotfiles.toml.tmpl | grep -oE '^\"[^\"]+\"' | tr -d '\"' | paste -sd' ')\" = 'bat eza fastfetch fzf ripgrep starship' ]"
  # 精簡只放 shell 體驗(#273):tailscale、btop 拿掉了,選裝工具的安裝腳本一支都不跑
  check "精簡的機器選裝腳本一支都不跑(tailscale 不在精簡裡)" \
    "chezmoi --config /tmp/lean.toml --destination /tmp/lean-home --persistent-state /tmp/lean.boltdb apply --dry-run --verbose --no-tty > /tmp/lean-dry 2>&1 && ! grep -E '^diff --git a/$TOOL_SCRIPT_RE' /tmp/lean-dry"
  check "選完整、選單不改:存完整,tools 是選單上全部" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice full)") > /tmp/full.toml && $(printf "$use_is" full /tmp/full.toml) && grep -qxF '$(toml_list "$FULL_TOOLS")' /tmp/full.toml"
  check "完整的預設組合有 node,精簡沒有" "grep -q '\"node\"' /tmp/full.toml && ! grep -q '\"node\"' /tmp/lean.toml"
  check "完整的預設組合有 cloudflared、tailscale、btop,精簡沒有" \
    "for t in cloudflared tailscale btop; do grep -q \"\\\"\$t\\\"\" /tmp/full.toml && ! grep -q \"\\\"\$t\\\"\" /tmp/lean.toml || exit 1; done"
  local full_no_ttyd=${FULL_TOOLS/\/ttyd\///}
  check "選完整後取消 ttyd:存自訂加 tools 清單" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice full)" --promptMultichoice "$(menu_choice "$full_no_ttyd")") > /tmp/full-ttyd.toml && $(printf "$use_is" custom /tmp/full-ttyd.toml) && grep -qxF '$(toml_list "$full_no_ttyd")' /tmp/full-ttyd.toml"
  check "選精簡後多勾 gh:存自訂" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice minimal)" --promptMultichoice "$(menu_choice zsh/starship/eza/fzf/bat/ripgrep/vim/fastfetch/gh)") > /tmp/lean-gh.toml && $(printf "$use_is" custom /tmp/lean-gh.toml) && grep -q '\"gh\"' /tmp/lean-gh.toml"
  local full_filtered=${FULL_TOOLS/\/headless-chrome\/playwright-cli/}
  # WSL 的網路借 Windows 那份 Tailscale(#273):tailscale 不建議,完整也不勾;snapserver 抓不到 tailnet IP(#290),同樣不建議
  local full_wsl=${full_filtered/\/tailscale\///}
  full_wsl=${full_wsl/\/snapserver\///}
  check "WSL 選完整、選單不改:判斷為沒改(存完整、沒有 tailscale、snapserver、headless-chrome、playwright-cli)" \
    "$(render_cmd /tmp/u-none.toml --override-data '{"chezmoi":{"kernel":{"osrelease":"5.15.167.4-microsoft-standard-WSL2"}}}' --promptChoice "$(use_choice full)") > /tmp/full-wsl.toml && $(printf "$use_is" full /tmp/full-wsl.toml) && grep -qxF '$(toml_list "$full_wsl")' /tmp/full-wsl.toml"
  check "ARM 選完整、選單不改:判斷為沒改" \
    "$(render_cmd /tmp/u-none.toml --override-data '{"chezmoi":{"arch":"arm64"}}' --promptChoice "$(use_choice full)") > /tmp/full-arm.toml && $(printf "$use_is" full /tmp/full-arm.toml) && grep -qxF '$(toml_list "$full_filtered")' /tmp/full-arm.toml"
  check "第一次 init 用途預設精簡(--promptDefaults、不給用途)" \
    "chezmoi --config /tmp/s-default.toml init --no-tty --promptDefaults --promptString 'git user.email=e2e@example.com' </dev/null && $(printf "$use_is" minimal /tmp/s-default.toml)"
  # 免回答安裝那一行(#253 起在 Runbook 與沒有 root 的那份,不在 README)的 --promptChoice
  # 要跟樣板一字不差,不然 init 會報錯或停下來問。兩份都要有、都要一致。
  check "免回答安裝那一行的用途提示跟樣板一致(new-machine-setup、no-root-machine)" \
    "for f in docs/new-machine-setup.md docs/install/no-root-machine.md; do grep -qF -e $(printf '%q' "--promptChoice \"$(use_choice minimal)\"") ~/.local/share/chezmoi/\$f || { echo \"\$f 沒有\"; exit 1; }; done"
  # 用途那題的選項是字母 f/m/c,直接 Enter 用預設(#222)。--no-tty 時答案從 stdin 一行一題讀:
  # 用途、選單(Enter = 預設勾選)、git user.name(Enter = henry)
  check "用途那題打 m 得到 minimal" \
    "printf 'm\\n\\n\\n' | chezmoi --config /tmp/use-m.toml init --no-tty --promptString 'git user.email=e2e@example.com' && $(printf "$use_is" minimal /tmp/use-m.toml) && grep -qxF '$LEAN_TOML' /tmp/use-m.toml"
  check "用途那題直接 Enter 得到 minimal" \
    "printf '\\n\\n\\n' | chezmoi --config /tmp/use-enter.toml init --no-tty --promptString 'git user.email=e2e@example.com' && $(printf "$use_is" minimal /tmp/use-enter.toml)"
  check "用途不是三個之一時報 invalid choice" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice server)") 2>&1 | grep -q 'invalid choice'"
  # 存用途的機器:預設組合改了(這裡用「config 裡的 tools 是舊的」模擬),init 就跟上
  check "存精簡的機器,init(不帶 --prompt)tools 照現在的預設組合重算" \
    "sed 's/^    tools = .*/    tools = [\"gh\"]/' /tmp/lean.toml > /tmp/lean-stale.toml && chezmoi --config /tmp/lean-stale.toml init --no-tty </dev/null && $(printf "$use_is" minimal /tmp/lean-stale.toml) && grep -qxF '$LEAN_TOML' /tmp/lean-stale.toml"
  check "存精簡的機器跑 tools 那條(init --prompt --promptDefaults):保留精簡與勾選" \
    "cp /tmp/lean.toml /tmp/lean-prompt.toml && chezmoi --config /tmp/lean-prompt.toml init --prompt --no-tty --promptDefaults </dev/null && $(printf "$use_is" minimal /tmp/lean-prompt.toml) && grep -qxF '$LEAN_TOML' /tmp/lean-prompt.toml"
  # 精簡沒問過憑證,改成完整就要問(給 SECRET_FLAGS)
  check "存精簡的機器在 tools 改選完整:選單預設帶完整的組合" \
    "cp /tmp/lean.toml /tmp/lean-full.toml && chezmoi --config /tmp/lean-full.toml init --prompt --no-tty --promptDefaults $(printf '%q ' "${SECRET_FLAGS[@]}")--promptChoice $(printf '%q' "$(use_choice full)") </dev/null && $(printf "$use_is" full /tmp/lean-full.toml) && grep -qxF '$(toml_list "$FULL_TOOLS")' /tmp/lean-full.toml"
  check "只有 tools(有 toolsSchema)、沒有用途的舊 config:init 不問、存自訂、tools 不變" \
    "sed '/^    machineUse = /d' $cfg > /tmp/no-use.toml && ! grep -q machineUse /tmp/no-use.toml && chezmoi --config /tmp/no-use.toml init --no-tty </dev/null && $(printf "$use_is" custom /tmp/no-use.toml) && [ \"\$(grep '^    tools = ' /tmp/no-use.toml)\" = \"\$(grep '^    tools = ' $cfg)\" ]"
  # #222 以前 machineUse 存中文:init(不帶 --prompt)換成代號,勾選不變
  check "存「精簡」的舊 config:init 後存 minimal、tools 是精簡那九項" \
    "sed 's/^    machineUse = .*/    machineUse = \"精簡\"/' /tmp/lean.toml > /tmp/legacy-lean.toml && chezmoi --config /tmp/legacy-lean.toml init --no-tty </dev/null && $(printf "$use_is" minimal /tmp/legacy-lean.toml) && grep -qxF '$LEAN_TOML' /tmp/legacy-lean.toml"
  check "存「完整」的舊 config:init 後存 full、tools 是選單上全部" \
    "sed 's/^    machineUse = .*/    machineUse = \"完整\"/' /tmp/full.toml > /tmp/legacy-full.toml && chezmoi --config /tmp/legacy-full.toml init --no-tty </dev/null && $(printf "$use_is" full /tmp/legacy-full.toml) && grep -qxF '$(toml_list "$FULL_TOOLS")' /tmp/legacy-full.toml"
  check "存「自訂」的舊 config:init 後存 custom、tools 不變" \
    "sed 's/^    machineUse = .*/    machineUse = \"自訂\"/' $cfg > /tmp/legacy-custom.toml && chezmoi --config /tmp/legacy-custom.toml init --no-tty </dev/null && $(printf "$use_is" custom /tmp/legacy-custom.toml) && [ \"\$(grep '^    tools = ' /tmp/legacy-custom.toml)\" = \"\$(grep '^    tools = ' $cfg)\" ]"

  # 憑證只問用得到的(#213)。execute-template 沒給旗標時不會停下來問,而是把提示文字當答案,
  # 所以「有問」=「config 裡有那個 key」(全新 config、只給 git 身分)。
  bold "▶ (渲染)憑證只問用得到的"
  local secret_keys='codeServerPassword|codexLbApiKey|context7ApiKey|wakatimeApiKey'
  # secrets_asked <用途> [勾選] → 印出渲染指令,輸出問到的憑證 key(照樣板順序,空白分隔)
  secrets_asked() {
    local flags=(--promptChoice "$(use_choice "$1")")
    [ -n "${2:-}" ] && flags+=(--promptMultichoice "$(menu_choice "$2")")
    echo "chezmoi --config /tmp/s-none.toml execute-template --init --no-tty $(printf '%q ' "${GIT_FLAGS[@]}" "${flags[@]}") < ~/.local/share/chezmoi/home/.chezmoi.toml.tmpl | grep -oE '^    ($secret_keys) = ' | awk '{print \$1}' | paste -sd' '"
  }
  check "選精簡:只問 git 身分,一個憑證都不問" "[ -z \"\$($(secrets_asked minimal))\" ]"
  check "免回答安裝那一行(--promptDefaults、只給用途與 git email)跑得完、不問憑證" \
    "chezmoi --config /tmp/s-readme.toml init --no-tty --promptDefaults --promptChoice $(printf '%q' "$(use_choice minimal)") --promptString 'git user.email=e2e@example.com' </dev/null && cat /tmp/s-readme.toml && ! grep -qE '$secret_keys' /tmp/s-readme.toml && grep -qx '    gitUserName = \"henry\"' /tmp/s-readme.toml"
  check "勾 code-server:只問 code-server 密碼" "[ \"\$($(secrets_asked custom code-server))\" = codeServerPassword ]"
  check "勾 opencode(沒勾 codex):只問 codex-lb key" "[ \"\$($(secrets_asked custom opencode))\" = codexLbApiKey ]"
  check "勾 codex:只問 codex-lb key" "[ \"\$($(secrets_asked custom codex))\" = codexLbApiKey ]"
  check "勾 agent-config、wakatime:問 Context7、WakaTime key" \
    "[ \"\$($(secrets_asked custom wakatime/agent-config))\" = 'context7ApiKey wakatimeApiKey' ]"
  check "選完整:四個憑證都問" \
    "[ \"\$($(secrets_asked full))\" = 'codeServerPassword codexLbApiKey context7ApiKey wakatimeApiKey' ]"
  # 存過的值不管現在勾不勾都留著(第一次 init 存的四項;改成精簡也不刪)
  check "已存的憑證在改成精簡後保留(init --prompt 改用途)" \
    "cp $cfg /tmp/s-keep.toml && chezmoi --config /tmp/s-keep.toml init --prompt --no-tty --promptDefaults --promptChoice $(printf '%q' "$(use_choice minimal)") </dev/null && $(printf "$use_is" minimal /tmp/s-keep.toml) && grep -qx '    codeServerPassword = \"e2e\"' /tmp/s-keep.toml && grep -qx '    codexLbApiKey = \"e2e\"' /tmp/s-keep.toml && grep -qx '    wakatimeApiKey = \"e2e-waka\"' /tmp/s-keep.toml && grep -qx '    context7ApiKey = \"\"' /tmp/s-keep.toml"
  check "沒勾 code-server:不部署 ~/.config/code-server(它要的密碼沒問)" \
    "! chezmoi --config /tmp/lean.toml managed | grep -q '^\\.config/code-server'"
  check "精簡(沒有任何憑證)的 config 渲染得了所有檔案" \
    "chezmoi --config /tmp/lean.toml --destination /tmp/lean-home --persistent-state /tmp/lean.boltdb apply --dry-run --no-tty --exclude externals,scripts"

  # 原生 Termux 跟 Linux 同一套用途與選單(#274)。這裡只驗樣板(把 .chezmoi.os 蓋成 android 來渲染);
  # 真的在 termux 容器跑 init、apply 由 termux 目標負責。
  bold "▶ (渲染)Termux 出用途與選單、裝不了的不跑腳本"
  local android=$ANDROID_ENV
  check "android 選精簡:存精簡,tools 跟 Ubuntu 的精簡一樣" \
    "$(render_cmd /tmp/u-android.toml --override-data "$android" --promptChoice "$(use_choice minimal)") > /tmp/android.toml && $(printf "$use_is" minimal /tmp/android.toml) && grep -qxF '$TERMUX_TOML' /tmp/android.toml"
  check "android 選單全部勾(含裝不了的):照存,存自訂" \
    "$(render_cmd /tmp/u-android.toml --override-data "$android" --promptChoice "$(use_choice custom)" --promptMultichoice "$(menu_choice "$FULL_TOOLS" "$android")") > /tmp/android-all.toml && $(printf "$use_is" custom /tmp/android-all.toml) && grep -qxF '$(toml_list "$FULL_TOOLS")' /tmp/android-all.toml"
  # dry-run 的輸出含所有檔案的 diff,只看腳本自己的 diff 標頭,避免檔案內容裡提到腳本名就誤判。
  # 先確認同一招在 linux 上看得到選裝腳本,不然下一項「看不到」可能只是指令本身看不到腳本
  check "(對照)linux 用同一招看得到選裝腳本" \
    "chezmoi --destination /tmp/linux-home --persistent-state /tmp/linux.boltdb apply --dry-run --verbose --no-tty 2>&1 | grep -q '^diff --git a/\.chezmoiscripts/install-gh'"
  # 全部勾了,Termux 會跑的選裝腳本只剩 wakatime(其他走 pkg,或裝不了);Node 走 pkg、不跑 install-node
  check "android 全部勾:選裝工具的腳本只跑 install-wakatime" \
    "[ \"\$(chezmoi --config /tmp/android-all.toml --override-data '$android' --destination /tmp/android-home --persistent-state /tmp/android.boltdb apply --dry-run --verbose --no-tty 2>&1 | grep -oE '^diff --git a/($TOOL_SCRIPT_RE|\\.chezmoiscripts/install-node)' | sed 's|.*/||' | sort -u | paste -sd' ')\" = install-wakatime ]"

  # 選單每台列全部工具(#272)。WSL 不在 WSL 裝 Linux Chrome(查原因到遠端主機做,#260)、Google 只出 amd64 的 .deb:
  # headless Chrome、playwright-cli 照列,後面標「裝不了」與原因(.chezmoitemplates/tool-env),預設組合不勾,勾了照存、apply 時略過。
  # 用 --override-data 蓋 kernel.osrelease 模擬 WSL、arch 模擬 ARM;--config 指向不存在的檔,
  # promptMultichoiceOnce 才會真的問。用 --promptMultichoice 指定勾哪項:選單文字對不上會報 invalid choice。
  bold "▶ (渲染)WSL、ARM 選單照列 headless Chrome、playwright-cli,標裝不了"
  local wsl='{"chezmoi":{"kernel":{"osrelease":"5.15.167.4-microsoft-standard-WSL2"}}}' arm='{"chezmoi":{"arch":"arm64"}}'
  # 加引號:~ 要留到容器裡才展開(容器的家目錄是 /home/ubuntu,不是跑 e2e 這台的)
  local tmpl='~/.local/share/chezmoi/home' scripts='~/.local/share/chezmoi/home/.chezmoiscripts'
  check "沒給旗標 = 用途預設精簡、選單勾精簡那九項" \
    "chezmoi --config /tmp/fresh-linux.toml execute-template --init --no-tty $(printf '%q ' "${INIT_FLAGS[@]}") < $tmpl/.chezmoi.toml.tmpl | grep -qxF '$LEAN_TOML'"
  check "(對照)非 WSL 的選單有 headless-chrome、playwright-cli" \
    "chezmoi --config /tmp/fresh-linux.toml execute-template --init --no-tty $(printf '%q ' "${INIT_FLAGS[@]}") --promptMultichoice $(printf '%q' "$(menu_choice headless-chrome/playwright-cli)") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"playwright-cli\"'"
  check "WSL 的選單照常列 AI 工具" \
    "chezmoi --config /tmp/fresh-wsl.toml execute-template --init --no-tty --override-data '$wsl' $(printf '%q ' "${INIT_FLAGS[@]}") --promptMultichoice $(printf '%q' "$(menu_choice agent-config)") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"agent-config\"'"
  local ov label
  for ov in "$wsl" "$arm"; do
    for t in headless-chrome playwright-cli; do
      label=$(menu_choice "$t" "$ov")
      check "$ov 的選單列 $t、標裝不了與原因,勾了照存" \
        "grep -q '（裝不了：' <<<$(printf '%q' "$label") && chezmoi --config /tmp/fresh-env.toml execute-template --init --no-tty --override-data '$ov' $(printf '%q ' "${INIT_FLAGS[@]}") --promptMultichoice $(printf '%q' "$label") < $tmpl/.chezmoi.toml.tmpl | grep -qxF '$(toml_list "$t")'"
    done
  done
  check "(對照)非 WSL 的 amd64 選單沒有任何標註" "! grep -qE '（(裝不了|不建議)：' <<<$(printf '%q' "$(menu_labels)")"
  label=$(menu_choice tailscale "$wsl")
  check "WSL 的選單 tailscale 標不建議,勾了照存" \
    "grep -q '（不建議：網路借 Windows' <<<$(printf '%q' "$label") && chezmoi --config /tmp/fresh-env.toml execute-template --init --no-tty --override-data '$wsl' $(printf '%q ' "${INIT_FLAGS[@]}") --promptMultichoice $(printf '%q' "$label") < $tmpl/.chezmoi.toml.tmpl | grep -qxF '$(toml_list tailscale)'"
  check "WSL 勾了 tailscale:照裝(安裝腳本渲染出官方 installer)、不記略過" \
    "chezmoi execute-template --override-data '{\"tools\":[\"tailscale\"],\"chezmoi\":{\"kernel\":{\"osrelease\":\"5.15.167.4-microsoft-standard-WSL2\"}}}' < $scripts/run_onchange_after_install-tailscale.sh.tmpl | grep -q tailscale.com/install.sh && [ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"tailscale\"],\"chezmoi\":{\"kernel\":{\"osrelease\":\"5.15.167.4-microsoft-standard-WSL2\"}}}' < $scripts/run_onchange_after_record-env-skipped.sh.tmpl | tr -d '[:space:]')\" ]"
  # proot Ubuntu(#273):kernel 是 Android 的(.chezmoitemplates/is-proot),tailscale 也不建議
  local proot='{"chezmoi":{"arch":"arm64","kernel":{"osrelease":"5.15.123-android14-11-ge2e"}}}'
  check "proot Ubuntu 的選單 tailscale 標不建議" \
    "grep -q '（不建議：網路借 Android' <<<$(printf '%q' "$(menu_choice tailscale "$proot")")"
  check "WSL 上就算 tools 裡有 headless-chrome,安裝腳本也渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"headless-chrome\"],\"chezmoi\":{\"kernel\":{\"osrelease\":\"5.15.167.4-microsoft-standard-WSL2\"}}}' < $scripts/run_onchange_after_install-headless-chrome.sh.tmpl | tr -d '[:space:]')\" ]"
  check "WSL 上就算 tools 裡有 playwright-cli,安裝腳本也渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"playwright-cli\"],\"chezmoi\":{\"kernel\":{\"osrelease\":\"5.15.167.4-microsoft-standard-WSL2\"}}}' < $scripts/run_onchange_after_npm-install-playwright-cli.sh.tmpl | tr -d '[:space:]')\" ]"
  local wsl_hc='{"tools":["headless-chrome","fzf"],"chezmoi":{"kernel":{"osrelease":"5.15.167.4-microsoft-standard-WSL2"}}}'
  check "WSL 勾了 headless-chrome:略過腳本只記它與原因、彙整腳本(有 root 也)渲染出來,語法對" \
    "chezmoi execute-template --override-data '$wsl_hc' < $scripts/run_onchange_after_record-env-skipped.sh.tmpl > /tmp/rec.sh && sh -n /tmp/rec.sh && [ \"\$(grep -c '^skip_env ' /tmp/rec.sh)\" = 1 ] && grep -q \"^skip_env 'headless-chrome' '.*WSL\" /tmp/rec.sh && chezmoi execute-template --override-data '$wsl_hc' < $scripts/run_after_zz-root-skipped-summary.sh.tmpl > /tmp/sum.sh && sh -n /tmp/sum.sh && grep -q 這台裝不了 /tmp/sum.sh"
  check "(對照)沒有裝不了的勾選:略過腳本、有 root 時的彙整腳本都渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"headless-chrome\"]}' < $scripts/run_onchange_after_record-env-skipped.sh.tmpl | tr -d '[:space:]')\" ] && [ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"headless-chrome\"]}' < $scripts/run_after_zz-root-skipped-summary.sh.tmpl | tr -d '[:space:]')\" ]"
  # 真的 apply 一次(#272):WSL 勾一個裝不了的 headless-chrome,apply 照樣 exit 0,最後列出略過與原因。
  # 用另一份 config、目的地、狀態檔,不動這台主要的那份;腳本照樣在這台跑(彙整檔在真的 $HOME)。
  # 只勾 headless-chrome:其他選裝腳本都不跑,套件腳本的基底前面已經裝好、不用連網。
  check "WSL 勾 headless-chrome 跑 init --apply:exit 0,彙整列出它和原因,有 root 那段不出現" \
    "mkdir -p /tmp/wsl-home && chezmoi init --apply --config /tmp/wsl-apply.toml --destination /tmp/wsl-home --persistent-state /tmp/wsl-apply.boltdb --no-tty --override-data '$wsl' $(printf '%q ' "${INIT_FLAGS[@]}") --promptChoice $(printf '%q' "$(use_choice custom)") --promptMultichoice $(printf '%q' "$(menu_choice headless-chrome "$wsl")") > /tmp/wsl-apply.log 2>&1; rc=\$?; tail -n 8 /tmp/wsl-apply.log; [ \$rc = 0 ] && grep -qxF '$(toml_list headless-chrome)' /tmp/wsl-apply.toml && sed -n '/^== 這台裝不了,以下選裝工具已略過/,\$p' /tmp/wsl-apply.log | grep -q -- '^- headless-chrome:WSL' && ! grep -q '^== 沒有 root' /tmp/wsl-apply.log && [ ! -e ~/.local/state/dotfiles/env-skipped ]"

  # 非 Debian 系 Linux(例如 Fedora):要 apt 的東西安靜略過。用 --override-data 蓋 osRelease 模擬
  # (id 與 idLike 都要蓋,不然留著容器本身 Ubuntu 的 idLike=debian)。
  bold "▶ (渲染)非 Debian 系 Linux 照樣出用途選單、apt 腳本渲染成空的、選裝工具改走 mise"
  local fedora='{"chezmoi":{"osRelease":{"id":"fedora","idLike":""}}}'
  # snapserver 走 apt(#290),非 Debian 系同樣裝不了
  local fedora_full=${FULL_TOOLS/\/headless-chrome\/playwright-cli/}
  fedora_full=${fedora_full/\/snapserver\///}
  # snapclient 也走 apt(#292)
  fedora_full=${fedora_full/\/snapclient\///}
  check "非 Debian 系出用途選單:選完整存完整,tools 是選單上全部扣掉裝不了的 headless-chrome、playwright-cli、snapserver、snapclient" \
    "$(render_cmd /tmp/fresh-fedora.toml --override-data "$fedora" --promptChoice "$(use_choice full)") > /tmp/fedora.toml && grep -qx '    machineUse = \"full\"' /tmp/fedora.toml && grep -qxF '$(toml_list "$fedora_full")' /tmp/fedora.toml"
  label=$(menu_choice headless-chrome "$fedora")
  check "非 Debian 系的選單列 headless-chrome、標裝不了,勾了照存" \
    "grep -q '（裝不了：' <<<$(printf '%q' "$label") && $(render_cmd /tmp/fresh-fedora.toml --override-data "$fedora" --promptMultichoice "$label") | grep -qxF '$(toml_list headless-chrome)'"
  check "非 Debian 系有 tools 指令可以重出選單" \
    "chezmoi execute-template --override-data '$fedora' < $tmpl/dot_local/bin/executable_tools.tmpl | grep -q 'chezmoi init --prompt'"
  # 這台(有 root 的 Ubuntu)前面已經 apt 裝了 vim,也跟著 snapserver 裝了 ffmpeg(#290)。
  # 樣板用 lookPath 看系統有沒有:PATH 換成只放 vim(和渲染要的 chezmoi、id、sh、sudo)的目錄,當成系統沒有 ffmpeg。
  # btop 是單一執行檔(always),不看系統
  local fedora_mise='{"chezmoi":{"osRelease":{"id":"fedora","idLike":""}},"tools":["ffmpeg","btop","vim"]}'
  check "非 Debian 系(就算有 root)選裝工具走 mise:清單有系統沒有的 ffmpeg、always 的 btop,沒有系統已有的 vim" \
    "rm -rf /tmp/nopath && mkdir /tmp/nopath && for c in chezmoi id sh sudo vim; do ln -s \"\$(command -v \$c)\" /tmp/nopath/\$c; done && PATH=/tmp/nopath chezmoi execute-template --override-data '$fedora_mise' < $tmpl/dot_config/mise/conf.d/dotfiles.toml.tmpl > /tmp/fedora-mise.toml && cat /tmp/fedora-mise.toml && grep -qx '\"ffmpeg\" = \"latest\"' /tmp/fedora-mise.toml && grep -qx '\"btop\" = \"latest\"' /tmp/fedora-mise.toml && ! grep -q vim /tmp/fedora-mise.toml && chezmoi execute-template --override-data '$fedora_mise' < $scripts/run_onchange_after_install-mise.sh.tmpl | grep -q 'mise\" install'"
  check "有 root 的 Ubuntu:只勾 conda 的(ffmpeg)忽略 ~/.config/mise,勾了 always 的(fzf)不忽略;非 Debian 系不忽略" \
    "! chezmoi execute-template --override-data '$fedora_mise' < $tmpl/.chezmoiignore | grep -qx .config/mise && chezmoi execute-template --override-data '{\"tools\":[\"ffmpeg\"]}' < $tmpl/.chezmoiignore | grep -qx .config/mise && ! chezmoi execute-template --override-data '{\"tools\":[\"fzf\"]}' < $tmpl/.chezmoiignore | grep -qx .config/mise"
  check "有 root 的 Ubuntu:系統已經有 vim,always 的工具照樣列(mise 清單不看 lookPath)" \
    "chezmoi execute-template --override-data '{\"tools\":[\"vim\",\"fzf\"],\"miseTools\":{\"vim\":{\"tool\":\"vim\",\"cmd\":\"vim\",\"always\":true},\"fzf\":{\"tool\":\"fzf\",\"cmd\":\"fzf\",\"always\":true}}}' < $tmpl/dot_config/mise/conf.d/dotfiles.toml.tmpl | grep -qx '\"vim\" = \"latest\"'"
  local fedora_tools='{"chezmoi":{"osRelease":{"id":"fedora","idLike":""}},"tools":["gh","headless-chrome","playwright-cli","btop"]}'
  for f in run_onchange_before_install-packages run_once_after_set-default-shell \
           run_onchange_after_install-gh run_onchange_after_install-headless-chrome \
           run_onchange_after_npm-install-playwright-cli; do
    check "非 Debian 系上 $f 渲染成空的(就算 tools 有勾)" \
      "[ -z \"\$(chezmoi execute-template --override-data '$fedora_tools' < $scripts/$f.sh.tmpl | tr -d '[:space:]')\" ]"
  done
  # jq、zsh 不走 mise:jq 要在 modify_ 之前就有,zsh 用 zsh-bin(spec US42)
  local fedora_zsh='{"chezmoi":{"osRelease":{"id":"fedora","idLike":""}},"tools":["zsh"]}'
  check "非 Debian 系勾 zsh:install-home-jq-zsh 裝 jq 與 zsh-bin,語法對" \
    "chezmoi execute-template --override-data '$fedora_zsh' < $scripts/run_onchange_before_install-home-jq-zsh.sh.tmpl > /tmp/fedora-hjz.sh && sh -n /tmp/fedora-hjz.sh && grep -q 'jq-linux-' /tmp/fedora-hjz.sh && grep -q 'romkatv/zsh-bin' /tmp/fedora-hjz.sh"
  check "非 Debian 系沒勾 zsh:install-home-jq-zsh 只裝 jq" \
    "chezmoi execute-template --override-data '$fedora_mise' < $scripts/run_onchange_before_install-home-jq-zsh.sh.tmpl > /tmp/fedora-hj.sh && sh -n /tmp/fedora-hj.sh && grep -q 'jq-linux-' /tmp/fedora-hj.sh && ! grep -q 'romkatv/zsh-bin' /tmp/fedora-hj.sh"
  check "非 Debian 系勾 zsh:部署 .bashrc(互動式 bash 切 zsh)" \
    "chezmoi managed --override-data '$fedora_zsh' | grep -qx .bashrc"
  check "(對照)有 root 的 Ubuntu:install-home-jq-zsh 渲染成空的、不部署 .bashrc" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"zsh\"]}' < $scripts/run_onchange_before_install-home-jq-zsh.sh.tmpl | tr -d '[:space:]')\" ] && ! chezmoi managed --override-data '{\"tools\":[\"zsh\"]}' | grep -qx .bashrc"
  check "(對照)Debian 系(ID_LIKE 有 debian,例如 Linux Mint)照常出選單" \
    "chezmoi --config /tmp/fresh-mint.toml execute-template --init --no-tty --override-data '{\"chezmoi\":{\"osRelease\":{\"id\":\"linuxmint\",\"idLike\":\"ubuntu debian\"}}}' $(printf '%q ' "${INIT_FLAGS[@]}") --promptMultichoice $(printf '%q' "$(menu_choice fastfetch)") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"fastfetch\"'"

  # macOS(#218):沒有 mac 可跑,把 .chezmoi.os 蓋成 darwin 渲染。真機驗收另一張 ticket。
  bold "▶ (渲染)macOS 出用途選單,套件走 brew bundle(tailscale 是 cask)"
  local mac='{"chezmoi":{"os":"darwin"}}'
  # snapserver 靠 systemd user service(#290),macOS 裝不了
  local mac_full=${FULL_TOOLS/\/headless-chrome\/playwright-cli/}
  mac_full=${mac_full/\/snapserver\///}
  check "macOS 選完整、選單不改:存完整,tools 是選單上全部(有 tailscale,沒有 headless-chrome、playwright-cli、snapserver)" \
    "$(render_cmd /tmp/u-mac.toml --override-data "$mac" --promptChoice "$(use_choice full)") > /tmp/mac.toml && $(printf "$use_is" full /tmp/mac.toml) && grep -qxF '$(toml_list "$mac_full")' /tmp/mac.toml"
  check "macOS 選精簡:跟 Linux 同一組" \
    "$(render_cmd /tmp/u-mac.toml --override-data "$mac" --promptChoice "$(use_choice minimal)") > /tmp/mac-lean.toml && $(printf "$use_is" minimal /tmp/mac-lean.toml) && grep -qxF '$LEAN_TOML' /tmp/mac-lean.toml"
  check "macOS 的選單 tailscale 沒有標註" "grep -qx 'tailscale *私人 VPN,連自己的機器' <<<$(printf '%q' "$(menu_labels "$mac")")"
  for t in headless-chrome playwright-cli; do
    label=$(menu_choice "$t" "$mac")
    check "macOS 的選單列 $t、標裝不了,勾了照存" \
      "grep -q '（裝不了：' <<<$(printf '%q' "$label") && $(render_cmd /tmp/u-mac.toml --override-data "$mac" --promptMultichoice "$label") | grep -qxF '$(toml_list "$t")'"
  done
  local mac_tools='{"chezmoi":{"os":"darwin"},"tools":["zsh","starship","eza","claude","ttyd","code-server","herdr","cloudflared","tailscale"]}'
  check "macOS 的 brew bundle 腳本:基底 jq 加有勾的 formula,沒勾的、走 installer 的不列,app 另外 brew install --cask、失敗不中斷,語法對" \
    "chezmoi execute-template --override-data '$mac_tools' < $scripts/run_onchange_before_install-packages-darwin.sh.tmpl > /tmp/brew.sh && sh -n /tmp/brew.sh && grep -q '^brew bundle --file=/dev/stdin' /tmp/brew.sh && [ \"\$(grep -E '^brew \"' /tmp/brew.sh | sort | paste -sd' ')\" = 'brew \"cloudflared\" brew \"code-server\" brew \"eza\" brew \"jq\" brew \"poppler\" brew \"starship\" brew \"ttyd\"' ] && ! grep -q '^cask ' /tmp/brew.sh && [ \"\$(grep -E '^brew install --cask ' /tmp/brew.sh)\" = 'brew install --cask \"tailscale-app\" ||' ]"
  check "brew bundle 腳本在 Linux 渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"eza\"]}' < $scripts/run_onchange_before_install-packages-darwin.sh.tmpl | tr -d '[:space:]')\" ]"
  check "brew bundle 腳本在 Termux 渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"chezmoi\":{\"os\":\"android\"},\"tools\":[\"eza\"]}' < $scripts/run_onchange_before_install-packages-darwin.sh.tmpl | tr -d '[:space:]')\" ]"
  local mac_all='{"chezmoi":{"os":"darwin"},"tools":["zsh","eza","fastfetch","gh","ttyd","code-server","tailscale","headless-chrome","playwright-cli","btop"]}'
  for f in run_onchange_before_install-packages run_once_after_set-default-shell \
           run_onchange_after_install-gh run_onchange_after_install-mise \
           run_onchange_after_install-code-server run_onchange_after_install-headless-chrome \
           run_onchange_after_npm-install-playwright-cli run_onchange_after_install-tailscale; do
    check "macOS 上 $f 渲染成空的(Linux 的裝法、不改預設 shell、裝不了的不跑)" \
      "[ -z \"\$(chezmoi execute-template --override-data '$mac_all' < $scripts/$f.sh.tmpl | tr -d '[:space:]')\" ]"
  done
  check "macOS 勾了裝不了的(headless-chrome、playwright-cli):略過腳本只列這兩項(tailscale 走 cask),彙整腳本渲染出來" \
    "chezmoi execute-template --override-data '$mac_all' < $scripts/run_onchange_after_record-env-skipped.sh.tmpl > /tmp/mac-rec.sh && sh -n /tmp/mac-rec.sh && [ \"\$(grep '^skip_env ' /tmp/mac-rec.sh | cut -d\\' -f2 | sort | paste -sd' ')\" = 'headless-chrome playwright-cli' ] && chezmoi execute-template --override-data '$mac_all' < $scripts/run_after_zz-root-skipped-summary.sh.tmpl | grep -q 這台裝不了"
  check "macOS 的 wakatime 抓 darwin 版" \
    "chezmoi execute-template --override-data '{\"chezmoi\":{\"os\":\"darwin\"},\"tools\":[\"wakatime\"]}' < $scripts/run_onchange_after_install-wakatime.sh.tmpl > /tmp/waka-mac.sh && sh -n /tmp/waka-mac.sh && grep -qx 'asset=darwin-\$asset' /tmp/waka-mac.sh"
  check "macOS 部署 tools 指令" \
    "chezmoi --config /tmp/mac.toml managed --override-data '$mac' | grep -qx .local/bin/tools"
  # 憑證照勾選問(#213):用全新 config、只給 git 身分,看 config 寫了哪些 key
  local mac_secrets="chezmoi --config /tmp/s-mac-none.toml execute-template --init --no-tty --override-data '$mac' $(printf '%q ' "${GIT_FLAGS[@]}")"
  local mac_secret_keys='^    (codeServerPassword|codexLbApiKey|context7ApiKey|wakatimeApiKey) = '
  check "macOS 選精簡:一個憑證都不問" \
    "$mac_secrets --promptChoice $(printf '%q' "$(use_choice minimal)") < $tmpl/.chezmoi.toml.tmpl > /tmp/mac-s-lean.toml && $(printf "$use_is" minimal /tmp/mac-s-lean.toml) && ! grep -qE '$mac_secret_keys' /tmp/mac-s-lean.toml"
  check "macOS 選完整:四個憑證都問" \
    "[ \"\$($mac_secrets --promptChoice $(printf '%q' "$(use_choice full)") < $tmpl/.chezmoi.toml.tmpl | grep -oE '$mac_secret_keys' | awk '{print \$1}' | paste -sd' ')\" = 'codeServerPassword codexLbApiKey context7ApiKey wakatimeApiKey' ]"
  # .bashrc 切 zsh、補 .profile(#215)只給沒有 root 的 Linux;mac 勾了 zsh 也不部署。
  # .bashrc 的 starship 那段不分 OS,勾了 starship 就部署
  check "macOS 勾 zsh(沒勾 starship)不部署 .bashrc、.profile" \
    "! chezmoi --config /tmp/mac.toml managed --override-data '{\"chezmoi\":{\"os\":\"darwin\"},\"tools\":[\"zsh\"]}' | grep -qxE '\\.bashrc|\\.profile'"
  check "macOS 勾 starship:部署 .bashrc(只有 starship 那段)、不部署 .profile" \
    "chezmoi --config /tmp/mac.toml managed --override-data '{\"chezmoi\":{\"os\":\"darwin\"},\"tools\":[\"zsh\",\"starship\"]}' > /tmp/mac-managed && grep -qx .bashrc /tmp/mac-managed && ! grep -qx .profile /tmp/mac-managed && chezmoi --config /tmp/mac.toml execute-template --override-data '{\"chezmoi\":{\"os\":\"darwin\"},\"tools\":[\"zsh\",\"starship\"]}' < $tmpl/modify_dot_bashrc.tmpl > /tmp/mac-bashrc.sh && echo HIST | sh /tmp/mac-bashrc.sh | grep -q 'starship 提示列 >>>' && ! echo HIST | sh /tmp/mac-bashrc.sh | grep -q '切到 zsh'"

  # ffmpeg 不單獨勾(見 TOOLS_FIRST 上方);這裡只驗單獨勾了才裝、而且語法對。
  bold "▶ (渲染)ffmpeg"
  check "沒勾時套件腳本不含 ffmpeg" \
    "! chezmoi execute-template --override-data '{\"tools\":[\"vim\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -q ffmpeg"
  check "勾 ffmpeg 時套件腳本裝 ffmpeg" \
    "chezmoi execute-template --override-data '{\"tools\":[\"ffmpeg\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl > /tmp/dm.sh && grep -q ffmpeg /tmp/dm.sh && sh -n /tmp/dm.sh"

  # mupdf-tools、pandoc 拿掉了(#209):選單沒有、舊機器存著也不報 invalid choice。
  # nvm 在 #209 拿掉、#222 以 node 放回選單:舊機器存著 nvm 的換成 node。
  bold "▶ (渲染)選單沒有 mupdf-tools、pandoc,舊 config 存著會被濾掉;存著 nvm 的換成 node"
  check "tool-menu 沒有 nvm、mupdf-tools、pandoc,有 node" \
    "! grep -qE '^(nvm|mupdf-tools|pandoc) ' $tmpl/.chezmoitemplates/tool-menu && grep -q '^node ' $tmpl/.chezmoitemplates/tool-menu"
  check "套件清單沒有 mupdf-tools、pandoc" \
    "! grep -qE 'mupdf-tools|pandoc' $tmpl/.chezmoidata/packages.yaml"
  # 舊 config:tools 存著 nvm、mupdf-tools、pandoc(還有更舊的 document-media)
  step "放一份舊 config" \
    "sed 's/^    tools = .*/    tools = [\"nvm\", \"mupdf-tools\", \"pandoc\", \"document-media\", \"codegraph\"]/' ~/.config/chezmoi/chezmoi.toml > /tmp/old.toml && grep -q mupdf-tools /tmp/old.toml"
  check "舊 config 再 init(不帶 --prompt)濾掉拿掉的項目、nvm 換成 node" \
    "cp /tmp/old.toml /tmp/old-init.toml && chezmoi --config /tmp/old-init.toml init --no-tty </dev/null && grep -qx '    tools = \\[\"node\", \"codegraph\", \"ffmpeg\"\\]' /tmp/old-init.toml"
  check "舊 config 跑 tools 那條(init --prompt)不報 invalid choice、濾掉拿掉的項目、nvm 換成 node" \
    "cp /tmp/old.toml /tmp/old-prompt.toml && chezmoi --config /tmp/old-prompt.toml init --prompt --no-tty --promptDefaults </dev/null && grep -qx '    tools = \\[\"node\", \"codegraph\", \"ffmpeg\"\\]' /tmp/old-prompt.toml"

  # 只勾 codegraph(沒勾 node、playwright-cli 等其他 node 相關項)也要先裝 nvm 再裝 codegraph。
  # 第一次 apply 已經裝了 nvm,這裡換一個空的 HOME,照 chezmoi 的順序(install-node 排在 npm-install-codegraph 前)
  # 把兩支渲染出來的腳本真的跑一次。
  bold "▶ 勾了 node 或要 Node 的工具(codegraph、playwright-cli、opencode、wakatime)會裝 nvm 與 Node"
  local only_cg='{"tools":["codegraph"]}'
  check "只勾 codegraph:install-node 不是空的" \
    "[ -n \"\$(chezmoi execute-template --override-data '$only_cg' < $scripts/run_onchange_after_install-node.sh.tmpl | tr -d '[:space:]')\" ]"
  check "只勾 playwright-cli:install-node 不是空的" \
    "[ -n \"\$(chezmoi execute-template --override-data '{\"tools\":[\"playwright-cli\"]}' < $scripts/run_onchange_after_install-node.sh.tmpl | tr -d '[:space:]')\" ]"
  for t in opencode wakatime; do
    check "只勾 $t:install-node 不是空的、套件腳本加 libatomic1" \
      "[ -n \"\$(chezmoi execute-template --override-data '{\"tools\":[\"$t\"]}' < $scripts/run_onchange_after_install-node.sh.tmpl | tr -d '[:space:]')\" ] && chezmoi execute-template --override-data '{\"tools\":[\"$t\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -E '^for pkg in' | grep -qw libatomic1"
  done
  check "沒勾要 Node 的工具:install-node 是空的、套件腳本沒有 libatomic1" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"claude\",\"codex\"]}' < $scripts/run_onchange_after_install-node.sh.tmpl | tr -d '[:space:]')\" ] && ! chezmoi execute-template --override-data '{\"tools\":[\"claude\",\"codex\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -qw libatomic1"
  check "腳本順序:install-node 排在 npm-install-codegraph 前" \
    "[ \"\$(ls $scripts | grep -E 'install-node|npm-install-codegraph' | sort | head -n1)\" = run_onchange_after_install-node.sh.tmpl ]"
  # 只勾 node:整個 apply 在空的 HOME 真的跑一次(config 用選單勾 node 渲染出來的)
  check "只勾 node:install-node 不是空的、套件腳本加 libatomic1" \
    "[ -n \"\$(chezmoi execute-template --override-data '{\"tools\":[\"node\"]}' < $scripts/run_onchange_after_install-node.sh.tmpl | tr -d '[:space:]')\" ] && chezmoi execute-template --override-data '{\"tools\":[\"node\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -E '^for pkg in' | grep -qw libatomic1"
  check "只勾 node:選單勾 node 存 custom、tools 只有 node" \
    "$(render_cmd /tmp/u-none.toml --promptChoice "$(use_choice custom)" --promptMultichoice "$(menu_choice node)") > /tmp/only-node.toml && $(printf "$use_is" custom /tmp/only-node.toml) && grep -qxF '$(toml_list node)' /tmp/only-node.toml"
  check "只勾 node:在空的 HOME apply exit 0、nvm 與 node 能跑" \
    "rm -rf /tmp/only-node /tmp/only-node.boltdb && mkdir /tmp/only-node && HOME=/tmp/only-node chezmoi --source ~/.local/share/chezmoi --config /tmp/only-node.toml --persistent-state /tmp/only-node.boltdb apply --no-tty && HOME=/tmp/only-node bash -c '. ~/.nvm/nvm.sh && nvm --version && node --version'"
  check "只勾 codegraph:在空的 HOME 照順序跑兩支腳本,exit 0、codegraph 能跑" \
    "chezmoi execute-template --override-data '$only_cg' < $scripts/run_onchange_after_install-node.sh.tmpl > /tmp/cg-1.sh && chezmoi execute-template --override-data '$only_cg' < $scripts/run_onchange_after_npm-install-codegraph.sh.tmpl > /tmp/cg-2.sh && rm -rf /tmp/only-cg && mkdir /tmp/only-cg && env -i HOME=/tmp/only-cg PATH=/usr/local/bin:/usr/bin:/bin sh -c 'sh /tmp/cg-1.sh && sh /tmp/cg-2.sh' && env -i HOME=/tmp/only-cg PATH=/usr/local/bin:/usr/bin:/bin bash -c '. ~/.nvm/nvm.sh && codegraph --version'"

  # 基底只剩 git、curl、jq、python3;zsh、vim 走 toolPackages,eza 等走下載腳本,都是勾了才有。
  bold "▶ (渲染)基底縮小、zsh 等變選裝工具"
  local none='{"tools":[]}'
  # 前面「套件清單加一個套件」在 yaml 的 ubuntu 清單加了 tree,所以這裡是四項 + tree
  check "沒勾任何工具時套件腳本只有基底四項" \
    "chezmoi execute-template --override-data '$none' < $scripts/run_onchange_before_install-packages.sh.tmpl > /tmp/base.sh && sh -n /tmp/base.sh && grep -qx 'for pkg in git curl jq python3 tree; do' /tmp/base.sh"
  check "只勾 vim 時套件腳本多 vim、沒有 zsh" \
    "chezmoi execute-template --override-data '{\"tools\":[\"vim\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -E '^for pkg in' | grep -qw vim && ! chezmoi execute-template --override-data '{\"tools\":[\"vim\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -E '^for pkg in' | grep -qw zsh"
  check "沒勾 zsh:不部署 .zshrc、zsh 外掛" \
    "! chezmoi managed --include all --override-data '$none' | grep -xE '\.zshrc|\.config/zsh/(zsh-autosuggestions|zsh-z|zsh-syntax-highlighting)'"
  check "(對照)勾 zsh:.zshrc、三個外掛都在" \
    "[ \"\$(chezmoi managed --include all --override-data '{\"tools\":[\"zsh\"]}' | grep -cxE '\.zshrc|\.config/zsh/(zsh-autosuggestions|zsh-z|zsh-syntax-highlighting)')\" = 4 ]"
  check "不再部署、下載 p10k(.p10k.zsh、powerlevel10k)" \
    "! chezmoi managed --include all --override-data '{\"tools\":[\"zsh\",\"starship\"]}' | grep -E 'p10k|powerlevel10k'"
  # starship 跟 zsh 分開勾(#194):沒勾不部署設定、有 root 的 Ubuntu 也不碰 .bashrc;勾了兩個都部署
  check "沒勾 starship:不部署 starship.toml、.bashrc" \
    "! chezmoi managed --override-data '{\"tools\":[\"zsh\"]}' | grep -qxE '\.config/starship\.toml|\.bashrc'"
  check "只勾 starship(沒勾 zsh):部署 starship.toml、.bashrc,不部署 .zshrc、.profile" \
    "chezmoi managed --override-data '{\"tools\":[\"starship\"]}' > /tmp/ss-managed && grep -qx .config/starship.toml /tmp/ss-managed && grep -qx .bashrc /tmp/ss-managed && ! grep -qxE '\.zshrc|\.profile' /tmp/ss-managed"
  # 從沒有 root 變成有 root:切 zsh 那段不再重加但留著,starship 那段要排在它前面(exec 之後的跑不到)
  check "只勾 starship、.bashrc 留著舊的切 zsh 那段:那段原樣搬到最後" \
    "chezmoi execute-template --override-data '{\"tools\":[\"starship\"]}' < $tmpl/modify_dot_bashrc.tmpl > /tmp/ss-bashrc.sh && printf 'A\\n# >>> dotfiles:互動式 bash 切到 zsh >>>\\nOLDZSH\\n# <<< dotfiles:互動式 bash 切到 zsh <<<\\nB\\n' | sh /tmp/ss-bashrc.sh > /tmp/ss-bashrc.out && tail -n1 /tmp/ss-bashrc.out | grep -q '切到 zsh <<<' && grep -q OLDZSH /tmp/ss-bashrc.out && grep -qx B /tmp/ss-bashrc.out && [ \"\$(grep -n 'starship 提示列 >>>' /tmp/ss-bashrc.out | cut -d: -f1)\" -lt \"\$(grep -n '切到 zsh >>>' /tmp/ss-bashrc.out | cut -d: -f1)\" ]"
  check "只勾 starship 時 mise 清單只有 starship" \
    "[ \"\$(chezmoi execute-template --override-data '{\"tools\":[\"starship\"]}' < $tmpl/dot_config/mise/conf.d/dotfiles.toml.tmpl | grep '= \"latest\"')\" = '\"starship\" = \"latest\"' ]"
  check "沒勾 zsh:改預設 shell 的腳本渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '$none' < $scripts/run_once_after_set-default-shell.sh.tmpl | tr -d '[:space:]')\" ]"
  check "什麼都沒勾時 mise 清單與安裝腳本都渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '$none' < $tmpl/dot_config/mise/conf.d/dotfiles.toml.tmpl | tr -d '[:space:]')\" ] && [ -z \"\$(chezmoi execute-template --override-data '$none' < $scripts/run_onchange_after_install-mise.sh.tmpl | tr -d '[:space:]')\" ]"
  check "只勾 fzf 時 mise 安裝腳本語法對、清單只有 fzf" \
    "chezmoi execute-template --override-data '{\"tools\":[\"fzf\"]}' < $scripts/run_onchange_after_install-mise.sh.tmpl > /tmp/mise-fzf.sh && sh -n /tmp/mise-fzf.sh && [ \"\$(grep -E '^#   \"' /tmp/mise-fzf.sh)\" = '#   \"fzf\" = \"latest\"' ]"
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
    "~/.local/bin/tools --no-tty --promptDefaults --promptChoice $(printf '%q' "$(use_choice minimal)") </dev/null"
  check "用途存精簡、tools 是精簡那八項" \
    "$(printf "$use_is" minimal "$cfg") && grep -qxF '$LEAN_TOML' $cfg"
  check_tool fastfetch
  check "選精簡後 fastfetch 跑得起來" "~/.local/share/mise/shims/fastfetch --version"
  for t in claude gh herdr codegraph tailscale btop; do check_tool "$t"; done
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
# 指令是 python3)。zsh、eza、fzf、bat、ripgrep、vim 這些是精簡勾的選裝工具,走 pkg(toolPackages.termux)。
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
  # 跟 Runbook 免回答那行一樣:用途選精簡、選單直接 Enter(--promptDefaults)
  step "全新 Termux 跑 README 的安裝指令(pkg upgrade、pkg install chezmoi、init --apply,用途選精簡)" \
    "$(install_cmd '~/e2e-init.log' --no-tty "${INIT_FLAGS[@]}" --promptDefaults --promptChoice "$(use_choice minimal)")"
  check "pkg upgrade 有跑:沒有可升級的套件" "[ -z \"\$(apt list --upgradable 2>/dev/null | grep -v '^Listing')\" ]"
  check "chezmoi 用 pkg 裝" "dpkg-query -W -f='\${Status}' chezmoi | grep -q 'install ok installed'"
  check_git_remotes

  bold "▶ 第一次 apply 之後"
  for p in "${TERMUX_BASE[@]}"; do
    check "基底套件 $p 已安裝" "dpkg-query -W -f='\${Status}' $p | grep -q 'install ok installed'"
  done
  # 精簡沒勾任何 agent:client 的設定目錄都不部署(#211)。
  check "沒勾的 client 不部署設定目錄(~/.claude、~/.codex、~/.config/opencode、skillshare 的 config.yaml)" \
    "[ ! -e ~/.claude ] && [ ! -e ~/.codex ] && [ ! -e ~/.config/opencode ] && [ ! -e ~/.config/skillshare/config.yaml ]"
  # claude、codex、opencode、agent-config 在 Termux 裝不了(#274):勾了也不部署它們的設定目錄,
  # 所以不再在 Termux 驗它們的 modify_ 產物(Ubuntu 目標驗)。勾了不部署由下面 tools 那段驗。
  check "移除 chezmoi MCP 的 python 腳本被排除" "! chezmoi managed --include scripts | grep -q remove-chezmoi-mcp"
  check "tools 指令部署成可執行檔、shebang 指得到(Termux 沒有 /bin/sh)" \
    "[ -x ~/.local/bin/tools ] && sh_path=\$(head -n1 ~/.local/bin/tools | sed 's/^#!//') && [ -x \"\$sh_path\" ]"
  # openssh 是 Termux 的基底套件;ssh client 補裝、userspace tailscale 的 ProxyCommand 只看 Linux(#216)
  check "ssh config 已部署、沒有 ProxyCommand、沒有補裝家目錄的 ssh" \
    "grep -Eq '^Host company-ec2( |\$)' ~/.ssh/config && ! grep -qi ProxyCommand ~/.ssh/config && [ ! -e ~/.local/opt/openssh ]"
  # personal-chrome-attach 要勾 playwright-cli 和 agent-config 才部署,Termux 沒有
  check_no_browser_wrappers
  check_personal_chrome_attach no
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
  # 用途與選單跟 Linux 一樣會問(#274):--no-tty 時答案從 stdin 一行一題讀(用途、選單、git user.name),
  # 提示文字會印出來。另一份 config,不動上面裝好的那份。
  check "init 出用途與選裝工具選單(打 m、選單 Enter 得到精簡)" \
    "out=\$(printf 'm\\n\\n\\n' | chezmoi --config ~/q-use.toml init --no-tty --promptString 'git user.email=e2e@example.com' 2>&1); grep -qF $(printf '%q' "$USE_PROMPT") <<<\"\$out\" && grep -qF $(printf '%q' "$TOOLS_PROMPT") <<<\"\$out\" && grep -qx '    machineUse = \"minimal\"' ~/q-use.toml && grep -qxF '$TERMUX_TOML' ~/q-use.toml"
  check "選單列全部工具,Termux 裝不了的標原因(tailscale 提示裝 Android app)" \
    "out=\$(printf 'c\\n\\n\\n' | chezmoi --config ~/q-menu.toml init --no-tty --promptString 'git user.email=e2e@example.com' 2>&1); grep -q 'claude .*（裝不了：' <<<\"\$out\" && grep -q 'tailscale .*（裝不了：.*Android app' <<<\"\$out\" && grep -q 'agent-config .*（裝不了：' <<<\"\$out\""
  check "config 存精簡、tools 跟 Ubuntu 的精簡一樣" \
    "grep -qxF '$TERMUX_TOML' ~/.config/chezmoi/chezmoi.toml && grep -qx '    machineUse = \"minimal\"' ~/.config/chezmoi/chezmoi.toml"
  check "沒裝 tailscale、btop" "! command -v tailscale && ! command -v btop"
  for t in ${TERMUX_LEAN//\// }; do check_tool "$t"; done
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

  # 跟 Linux 一樣用 tools 加減工具(#274)。勾 pkg 裝得起來的(gh、node、wakatime、cloudflared、snapclient),
  # 再勾兩個 Termux 裝不了的(claude、headless-chrome):apply 照樣 exit 0,最後列出略過與原因。
  bold "▶ tools 勾 gh、node、wakatime、cloudflared、snapclient 與裝不了的 claude、headless-chrome"
  local picks=gh/node/wakatime/claude/headless-chrome/cloudflared/snapclient
  check "tools 選自訂、勾 $picks:exit 0" \
    "~/.local/bin/tools --no-tty $(printf '%q ' "${SECRET_FLAGS[@]}")--promptChoice $(printf '%q' "$(use_choice custom)") --promptMultichoice $(printf '%q' "$(menu_choice "$picks" "$ANDROID_ENV")") </dev/null > ~/e2e-tools.log 2>&1; rc=\$?; tail -n 15 ~/e2e-tools.log; [ \$rc = 0 ]"
  check "config 存自訂、tools 照勾的存(含裝不了的)" \
    "grep -qx '    machineUse = \"custom\"' ~/.config/chezmoi/chezmoi.toml && grep -qxF '$(toml_list "$picks")' ~/.config/chezmoi/chezmoi.toml"
  check "gh 用 pkg 裝好" "dpkg-query -W -f='\${Status}' gh | grep -q 'install ok installed' && gh --version"
  # snapclient(#292):pkg 的 snapcast-client,出聲靠它依賴的 pulseaudio(容器沒有音效裝置,只驗能執行)
  check "snapclient 用 pkg 的 snapcast-client 裝好,pulseaudio 跟著裝" \
    "dpkg-query -W -f='\${Status}' snapcast-client | grep -q 'install ok installed' && command -v pulseaudio && snapclient --version"
  check "cloudflared 用 pkg 裝好" "dpkg-query -W -f='\${Status}' cloudflared | grep -q 'install ok installed' && cloudflared --version"
  # Node 走 pkg 的 nodejs-lts,不走 nvm(nvm 的官方 binary 在 Android 跑不起來)
  check "node 是 pkg 的 nodejs-lts、沒有 ~/.nvm" \
    "dpkg-query -W -f='\${Status}' nodejs-lts | grep -q 'install ok installed' && node --version && [ ! -e ~/.nvm ]"
  # wakatime 在 Termux 實測裝得起來:linux 版 wakatime-cli 能跑(連得到 API 由 #274 手動驗過,這裡不連)
  check_tool wakatime
  check "claude 沒裝、~/.claude 沒部署" "! command -v claude && [ ! -e ~/.local/bin/claude ] && [ ! -e ~/.claude ]"
  check "headless-chrome 沒裝" "! command -v google-chrome"
  check "略過彙整列出 claude、headless-chrome 與原因,沒有「沒有 root」那段" \
    "s=\$(sed -n '/^== 這台裝不了,以下選裝工具已略過/,\$p' ~/e2e-tools.log) && grep -q -- '^- claude:.*proot Ubuntu' <<<\"\$s\" && grep -q -- '^- headless-chrome:.*Termux' <<<\"\$s\" && ! grep -q '^== 沒有 root' ~/e2e-tools.log"

  # 以前 android 每次 init 都把 tools 重算回固定那幾項,手動加的會不見(#274)
  bold "▶ 手動在 config 的 tools 加 ttyd,再 init、apply"
  step "config 的 tools 加 ttyd" \
    "sed -i 's/^    tools = \\[\\(.*\\)\\]\$/    tools = [\\1, \"ttyd\"]/' ~/.config/chezmoi/chezmoi.toml && grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml | grep -qF '\"ttyd\"'"
  check "chezmoi init 之後 ttyd 還在" \
    "chezmoi init --no-tty </dev/null && grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml | grep -qF '\"ttyd\"'"
  check "apply 用 pkg 裝好 ttyd" "chezmoi apply --no-tty && dpkg-query -W -f='\${Status}' ttyd | grep -q 'install ok installed'"
}

# ===============================================================
# 目標:noroot(沒有 root 的 Ubuntu,代表別人給的帳號、TeamSync 工作區)
# ===============================================================
# 映像模擬雲端映像本來就有的東西:curl、ca-certificates、git、python3;**不裝 sudo**。
# 另放一支假的 vim 在 /usr/local/bin:代表「系統已經有的指令」,mise 不該再裝一份。
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
 && useradd -m -s /bin/bash -G wheel wheeluser \
 && printf '#!/bin/sh\necho "VIM - e2e system stub"\n' > /usr/local/bin/vim && chmod 755 /usr/local/bin/vim
DOCKERFILE
  docker rm -f "$CTR" >/dev/null 2>&1 || true
  # --init:PID 1 換成會回收子程序的 tini。apply 裝的 userspace tailscaled 會被 zsh 背景起來,
  # 測試停掉它之後,sleep 當 PID 1 不回收,留下的 zombie 讓 pgrep 以為還在跑
  docker run -d --init --name "$CTR" --hostname dotfiles "$IMAGE" sleep infinity >/dev/null
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
# 情境就是用途(精簡、完整),跟免回答安裝那一行一樣只答用途、選單直接 Enter(--promptDefaults),
# 所以 config 存的是用途。完整 = 選單上全部(這個容器是 amd64、不是 WSL,沒有不建議或裝不了的)。
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
  # 彙整之後不能再有別的輸出:看標頭之後每一行都是彙整的格式(「- 項目:」、縮排的續行)。
  # 有沒有彙整看用途:精簡沒有要 root 的步驟(#273 拿掉 tailscale 後),完整有;各自在 noroot_slim_checks、check_skipped 驗
  check "有略過彙整時,它在輸出最後" \
    "! grep -q '^$SKIP_HEADER' ~/e2e-init.log || ! sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | sed 1d | grep -vE '^(- |    |\$)'"
}

# 沒有 root 時走 apt 的選裝工具改由 mise 裝(#217)。check_mise <指令> [--version 以外的參數]:
# 經 shims(不靠 PATH 設定)跑得起來,而且真的是 mise 管的那份。
MISE_SHIMS='~/.local/share/mise/shims'
check_mise() {  # check_mise <指令> [參數,預設 --version]
  check "$1 經 mise 的 shim 跑得起來" "$MISE_SHIMS/$1 ${2:---version} && ~/.local/bin/mise which $1"
}
# 系統已經有 vim(映像放的假 vim):mise 清單沒有它、shim 也沒有
check_mise_skips_system_vim() {
  check "系統已有的 vim 不在 mise 清單(conf.d 與 mise ls 都沒有)、vim 還是系統那支" \
    "! grep -qw vim ~/.config/mise/conf.d/dotfiles.toml && ! ~/.local/bin/mise ls --json | jq -e 'has(\"vim\")' && [ ! -e $MISE_SHIMS/vim ] && vim | grep -q 'e2e system stub'"
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
  # 精簡要 apt 的只剩 jq、zsh、vim:jq、zsh 從 release 裝到家目錄,vim 系統已有;tailscale 不在精簡裡(#273)
  check "精簡沒有任何要略過的步驟:沒有略過彙整(jq、zsh 裝到家目錄,vim 系統已有)" \
    "! grep -q '^$SKIP_HEADER' ~/e2e-init.log && ! grep -q '以下選裝工具已略過' ~/e2e-init.log"
  check "預設 shell 不算略過(改由 ~/.bashrc 切 zsh)" \
    "! sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | grep -q 預設\ shell"
  check "zsh 用 zsh-bin 裝到 ~/.local/bin,版本 5.8" "~/.local/bin/zsh --version | grep -q '^zsh 5\.8 '"
  check "zsh -i 下 starship 有載入" "$(zsh_ok '[[ $STARSHIP_SHELL == zsh && $PROMPT == *starship* ]]')"
  # zsh -i 開頭會跑 fastfetch(精簡有勾),只看最後一行
  check "TERM 沒設時 zsh 裡是 xterm-256color" "[ \"\$(env -u TERM ~/.local/bin/zsh -i -c 'print -r -- \$TERM' 2>/dev/null | tail -n1)\" = xterm-256color ]"
  check "pty 開互動 bash 會切成 zsh" "$(pty_bash -i); echo \"\$out\" | tail -n 5; grep -q 'ZV=:5\.8:' <<<\"\$out\""
  check "非互動 bash 留在 bash(bash -c、bash -lc)" \
    "[ \"\$(bash -c 'echo \${ZSH_VERSION:-none}')\" = none ] && [ \"\$(bash -lc 'echo \${ZSH_VERSION:-none}')\" = none ]"
  check "~/.bashrc 原本的內容還在、切 zsh 那段只有一份" \
    "grep -q 'HISTCONTROL' ~/.bashrc && [ \"\$(grep -c 'dotfiles:互動式 bash 切到 zsh >>>' ~/.bashrc)\" = 1 ]"
  check "~/.bashrc 的 starship 那段只有一份、排在切 zsh 那段前面" \
    "[ \"\$(grep -c 'dotfiles:starship 提示列 >>>' ~/.bashrc)\" = 1 ] && [ \"\$(grep -n 'dotfiles:starship 提示列 >>>' ~/.bashrc | cut -d: -f1)\" -lt \"\$(grep -n 'dotfiles:互動式 bash 切到 zsh >>>' ~/.bashrc | cut -d: -f1)\" ]"
  # skel 本來就有 ~/.profile;拿掉它再 apply 一次,看會不會補、login bash 會不會切成 zsh,最後放回去
  # 非互動 login bash 用 env -i 起:不帶外面這層 login shell 已經設好的 PATH
  check "沒有 ~/.profile 時補一個:login bash 找得到 ~/.local/bin 的 chezmoi、login 互動 bash 會切成 zsh" \
    "mv ~/.profile ~/.profile.skel && ~/.local/bin/chezmoi apply --no-tty --force && grep -qF '. \"\$HOME/.bashrc\"' ~/.profile && [ \"\$(env -i HOME=\$HOME PATH=/usr/bin:/bin bash -lc 'command -v chezmoi')\" = \"\$HOME/.local/bin/chezmoi\" ] && $(pty_bash -il) && echo \"\$out\" | tail -n 5 && grep -q 'ZV=:5\.8:' <<<\"\$out\"; r=\$?; mv -f ~/.profile.skel ~/.profile; exit \$r"
  check "jq 不用 root 從 GitHub release 裝到 ~/.local/bin" "~/.local/bin/jq --version"
  # 單一執行檔的選裝工具跟有 root 時一樣由 mise 裝(#233)
  # fastfetch 也在精簡裡(#273):每台開 shell 都跑它
  for t in eza fzf bat rg starship fastfetch; do check_mise "$t"; done
  check_mise_skips_system_vim
  check "zsh 外掛照常 clone(要的是 git,不用 root)" "git -C ~/.config/zsh/zsh-autosuggestions rev-parse --is-inside-work-tree"
  check_ssh_client
  # 精簡只放 shell 體驗(#273):沒有 tailscale,也就沒有 userspace 的 ProxyCommand
  check "精簡沒裝 tailscale、略過彙整沒有它、ssh config 沒有 ProxyCommand" \
    "[ ! -e ~/.local/bin/tailscale ] && ! sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | grep -qF -- '- tailscale:' && ! ssh -G company-ec2 | grep -qi '^proxycommand'"

  bold "▶ 精簡:第二次 apply"
  step "放時間標記(之後看 zsh-bin 有沒有重裝)" "touch ~/.e2e-marker2"
  # 略過的步驟記在 run_onchange_ 的狀態裡,沒有 root 的狀況沒變就不重跑、不重印,也不重新下載
  check "第二次 apply exit 0、沒有任何略過或下載" \
    "out=\$(chezmoi apply --no-tty 2>&1); r=\$?; echo \"\$out\"; [ \$r = 0 ] && ! grep -qE '略過|安裝|下載' <<<\"\$out\""
  check "第二次 apply 沒有重裝 zsh-bin" \
    "[ ! ~/.local/bin/zsh -nt ~/.e2e-marker2 ] && [ ! ~/.local/share/zsh -nt ~/.e2e-marker2 ]"
  # 後面 noroot_tailscale_checks 等用的 stub:會記錄呼叫、一定失敗的 curl;會成功的 sudo(渲染出有 root 那版)
  put_root_file /opt/e2e-stub/curl-log/curl 755 <<'SH'
#!/bin/sh
echo "curl $*" >> /tmp/e2e-curl.log
exit 1
SH
  put_root_file /opt/e2e-stub/sudo-ok/sudo 755 <<'SH'
#!/bin/sh
exit 0
SH
  check "待跑的腳本只有略過彙整那支" \
    "[ \"\$(chezmoi status | grep -E '^.?R')\" = \"\$(chezmoi status | grep -E '^.?R.*zz-root-skipped-summary')\" ]"
  check "zsh 的 PATH 沒有重複" "[ -z \"\$(~/.local/bin/zsh -i -c 'print -l \$path' 2>/dev/null | sort | uniq -d)\" ]"
}

# userspace tailscale(#224):完整會勾 tailscale(#273 起精簡不勾),在完整的使用者上驗。
# 腳本重跑、下載失敗、拿到 root 用的 curl-log、sudo-ok stub 在 noroot_slim_checks 放好了。
noroot_tailscale_checks() {
  bold "▶ 完整:userspace tailscale"
  check_skipped "tailscale"
  # userspace tailscale 由 apply 裝到家目錄(#224):彙整那筆只剩登入、常駐與 ProxyCommand 的說明,不再要人下載
  check "tailscale 的彙整只剩登入與說明(登入、常駐、ssh ProxyCommand,沒有下載步驟)" \
    "s=\$(sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log) && grep -q 'tailscaled.sock up' <<<\"\$s\" && grep -q 'enable-linger' <<<\"\$s\" && grep -q 'nc %h %p' <<<\"\$s\" && ! grep -qE 'pkgs.tailscale.com|--tun=userspace-networking' <<<\"\$s\""
  check "userspace tailscale 裝到 ~/.local/bin、tailscale version 能跑、建好 ~/.local/state/tailscale" \
    "[ -x ~/.local/bin/tailscale ] && [ -x ~/.local/bin/tailscaled ] && ~/.local/bin/tailscale version && [ -d ~/.local/state/tailscale ]"
  # 勾了 tailscale、沒有 root、系統 tailscaled 沒在跑 = userspace:只有 company-ec2(含帶轉發的別名)帶 ProxyCommand
  check "ssh config:company-ec2 經 userspace tailscale 的 ProxyCommand" \
    "ssh -G company-ec2 | grep -E \"^proxycommand \$HOME/.local/bin/tailscale --socket=\$HOME/.local/state/tailscale/tailscaled.sock nc \""
  check "ssh config:其他 Host 沒有 ProxyCommand(company-ec2-public、github.com)" \
    "! ssh -G company-ec2-public | grep -qi '^proxycommand' && ! ssh -G github.com | grep -qi '^proxycommand'"
  step "放時間標記(之後看 tailscale 有沒有重新下載)" "touch ~/.e2e-marker-ts"
  check "再 apply 一次 exit 0" "chezmoi apply --no-tty"
  check "再 apply 沒有重新下載 tailscale" \
    "[ ! ~/.local/bin/tailscale -nt ~/.e2e-marker-ts ] && [ ! ~/.local/bin/tailscaled -nt ~/.e2e-marker-ts ]"
  # 腳本內容改了(run_onchange 會重跑)也不重下載:直接渲染再跑一次,PATH 前面放記錄呼叫、一定失敗的 curl
  check "tailscale 已經裝過:腳本重跑不下載、exit 0" \
    "rm -f /tmp/e2e-curl.log && chezmoi execute-template --override-data '{\"tools\":[\"tailscale\"]}' < ~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_after_install-tailscale.sh.tmpl > /tmp/ts-\$(id -un).sh && out=\$(PATH=/opt/e2e-stub/curl-log:\$PATH sh /tmp/ts-\$(id -un).sh 2>&1) && echo \"\$out\" && grep -q '已經裝過' <<<\"\$out\" && [ ! -e /tmp/e2e-curl.log ]; r=\$?; rm -f ~/.local/state/dotfiles/root-skipped; exit \$r"
  # 同一支渲染好的腳本,換一個空的 HOME 跑:沒裝過、curl 失敗
  check "tailscale 下載失敗:記進略過彙整、exit 0、不留半套" \
    "rm -rf /tmp/ts-home-\$(id -un) && mkdir -p /tmp/ts-home-\$(id -un) && out=\$(HOME=/tmp/ts-home-\$(id -un) PATH=/opt/e2e-stub/curl-log:\$PATH sh /tmp/ts-\$(id -un).sh 2>&1) && echo \"\$out\" && grep -q '^- tailscale:.*下載失敗' /tmp/ts-home-\$(id -un)/.local/state/dotfiles/root-skipped && [ ! -e /tmp/ts-home-\$(id -un)/.local/bin/tailscale ] && [ ! -e /tmp/ts-home-\$(id -un)/.local/bin/tailscaled ]; r=\$?; rm -rf /tmp/ts-home-\$(id -un); exit \$r"
  # 之後拿到 root:~/.local/bin 的 userspace 版不算已安裝(它沒有系統 unit,systemctl enable 會失敗),要走官方 installer。
  # 用會成功的 sudo stub 渲染成有 root 那版,curl stub 記錄呼叫(一定失敗,腳本停在下載)
  check "有 root 時不把 ~/.local/bin 的 userspace tailscale 當成已安裝,改跑官方 installer" \
    "rm -f /tmp/e2e-curl.log && PATH=/opt/e2e-stub/sudo-ok:\$PATH chezmoi execute-template --override-data '{\"tools\":[\"tailscale\"]}' < ~/.local/share/chezmoi/home/.chezmoiscripts/run_onchange_after_install-tailscale.sh.tmpl > /tmp/ts-root.sh && out=\$(PATH=/opt/e2e-stub/curl-log:/opt/e2e-stub/sudo-ok:\$PATH sh /tmp/ts-root.sh 2>&1); echo \"\$out\"; ! grep -q '已安裝' <<<\"\$out\" && grep -q 'tailscale.com/install.sh' /tmp/e2e-curl.log"
  # userspace tailscaled 常駐:用一支叫 tailscaled 的假程式(只會等),看開 zsh 時沒在跑會不會被起來、在跑時不會多起一支。
  # 前面的 zsh -i 已經把 apply 裝的真 tailscaled 起過了:先停掉、把真的移開,測完放回去。
  # 用 KILL:真的 tailscaled 收到 TERM 後要一陣子才結束,接著的「沒在跑」會誤判
  check "userspace tailscaled 沒在跑時,開 zsh 會背景起來;已在跑不會多起" \
    "pkill -KILL -xu \"\$(id -u)\" tailscaled; sleep 1; mv ~/.local/bin/tailscaled ~/.local/bin/tailscaled.real && printf '#!/bin/sh\\nwhile :; do sleep 1; done\\n' > ~/.local/bin/tailscaled && chmod +x ~/.local/bin/tailscaled && ! pgrep -xu \"\$(id -u)\" tailscaled && ~/.local/bin/zsh -i -c exit >/dev/null 2>&1 && sleep 1 && [ \"\$(pgrep -xu \"\$(id -u)\" tailscaled | wc -l)\" = 1 ] && ~/.local/bin/zsh -i -c exit >/dev/null 2>&1 && sleep 1 && [ \"\$(pgrep -xu \"\$(id -u)\" tailscaled | wc -l)\" = 1 ]; r=\$?; pkill -xu \"\$(id -u)\" tailscaled; mv -f ~/.local/bin/tailscaled.real ~/.local/bin/tailscaled; exit \$r"
}

noroot_full_checks() {
  for s in tailscale headless-chrome "nvm 與 Node" codegraph playwright-cli 系統套件; do
    check_skipped "$s"
  done
  check "已經有 ~/.bash_profile 時不補 ~/.profile" "[ -e ~/.bash_profile ] && [ ! -e ~/.profile ]"
  check "系統套件的手動方式不含 mise 裝的(vim、btop、ffmpeg、poppler-utils)與 jq、zsh" \
    "! sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | grep -F -- '- 系統套件:' | grep -qwE 'vim|btop|ffmpeg|poppler-utils|jq|zsh'"
  check "改由 mise 裝的不在略過彙整(gh、fastfetch、code-server、cloudflared)" \
    "! sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | grep -qE -- '^- (gh|fastfetch|code-server|cloudflared):'"
  # 勾的、走 apt 的選裝工具(vim 除外,系統已有)每一項經 shims 跑得起來;claude 的 poppler-utils 看 pdftoppm
  for t in btop gh fastfetch code-server eza fzf bat rg starship ttyd cloudflared; do check_mise "$t"; done
  check_mise ffmpeg -version
  check_mise pdftoppm -v
  check_mise_skips_system_vim
  check "zsh 會把 mise 的 shims 加進 PATH" "grep -q 'mise/shims' ~/.zshrc"
  check "headless-chrome 的說明寫了缺系統函式庫" \
    "sed -n '/^$SKIP_HEADER/,\$p' ~/e2e-init.log | grep -F -- '- headless-chrome:' | grep -q '系統函式庫'"
  # 不用 root 的照常裝好
  for t in herdr wakatime claude codex opencode agent-config; do check_tool "$t"; done
  check_ssh_client
  check_no_browser_wrappers
  check_personal_chrome_attach yes
  check "modify_ 用家目錄的 jq 照常產出 ~/.claude/settings.json" \
    "~/.local/bin/jq -e '.enabledPlugins[\"chrome-devtools-mcp@claude-plugins-official\"] == false' ~/.claude/settings.json"
  check "第二次 apply exit 0、mise 的安裝腳本沒重跑" \
    "out=\$(chezmoi apply --no-tty 2>&1); r=\$?; echo \"\$out\"; [ \$r = 0 ] && ! grep -q 'mise' <<<\"\$out\""
  check "再跑 mise install 不重新下載(mise 回報都已安裝)" \
    "~/.local/bin/mise install 2>&1 | tee /dev/stderr | grep -q 'all tools are installed'"
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
  # apt-get 用 stub 讓它失敗:apply 不能因此失敗,改記進略過彙整
  put_root_file /opt/e2e-stub/aptfail/apt-get 755 <<'SH'
#!/bin/sh
echo "E: e2e stub 失敗" >&2
exit 100
SH
  check "apt-get 失敗:install-ssh-client exit 0、記進略過彙整、家目錄沒有半套 ssh" \
    "chezmoi --source /opt/e2e-src --config /tmp/none.toml execute-template < /opt/e2e-src/home/.chezmoiscripts/run_onchange_after_install-ssh-client.sh.tmpl > /tmp/ssh-client.sh && rm -f ~/.local/state/dotfiles/root-skipped && out=\$(PATH=/opt/e2e-stub/aptfail:\$PATH sh /tmp/ssh-client.sh 2>&1) && echo \"\$out\" && grep -q '略過 ssh' <<<\"\$out\" && grep -q '^- ssh:' ~/.local/state/dotfiles/root-skipped && [ ! -e ~/.local/bin/ssh ] && [ ! -e ~/.local/opt/openssh ]; r=\$?; rm -f ~/.local/state/dotfiles/root-skipped; exit \$r"
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
  noroot_init minimal
  noroot_slim_checks
  noroot_tailscale_running_checks

  use_user full
  # 「已經有 .bash_profile 就不補 .profile」:把 skel 的 .profile 改名成 .bash_profile(內容照用,PATH 一樣)
  step "完整:只有 ~/.bash_profile、沒有 ~/.profile" "mv ~/.profile ~/.bash_profile"
  noroot_init full
  noroot_full_checks
  noroot_tailscale_checks

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
