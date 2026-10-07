#!/bin/bash
# 容器 e2e:在全新容器裡從本機 repo 跑 bootstrap wizard(script/bootstrap.sh,
# 最後一關就是 `chezmoi init --apply`),檢查機器上看得到的結果。
#
# 用法:
#   bash script/tests/e2e.sh [ubuntu|termux]     # 預設 ubuntu
#
# 環境變數:
#   E2E_TAG=<字串>   容器名與映像 tag 的後綴,平行跑時避免撞名(預設 local)
#   E2E_KEEP=1       跑完不刪容器,方便 `docker exec -it <容器> bash` 進去看
#
# 測的是 repo 的工作目錄(含未 commit 的修改),不經過 GitHub:
# 工作目錄在主機上包成一個暫時的 git repo 放進容器,wizard 用 BOOTSTRAP_REPO 從那裡 clone。
# SSH key 是主機上現產的假 key,從 stdin 餵給 wizard;連 GitHub 驗證那關跳過(要人工驗)。
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

# ===============================================================
# 共用工具
# ===============================================================
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

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

cleanup() {
  if [ "${E2E_KEEP:-0}" = 1 ]; then
    bold "保留容器 $CTR(E2E_KEEP=1),用完 docker rm -f $CTR"
  else
    docker rm -f "$CTR" >/dev/null 2>&1 || true
  fi
}

# 測試要的東西都在主機上做好再放進容器的 $FIX:容器在 bootstrap 之前連 git、ssh-keygen 都沒有。
# 放在家目錄底下,因為 Termux 容器沒有 /tmp(在 Termux 裡是 $PREFIX/tmp)。
#   $FIX/dotfiles        repo 工作目錄(含未 commit、不含 .gitignore 擋掉的)commit 成的 git repo
#   $FIX/key、key.pub     假的 henry5720 key
#   $FIX/agent-config.git agent-config 的假 remote(bare repo,內容是一個 skill + 一個 MCP server)
make_fixtures() {
  FIX=$CTR_HOME/e2e-fixtures
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/dotfiles"
  (cd "$REPO" && git ls-files -co --exclude-standard -z \
    | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
    | tar --null -T - -cf -) | tar -C "$tmp/dotfiles" -xf -
  git -C "$tmp/dotfiles" init -q -b main
  git -C "$tmp/dotfiles" add -A
  git -C "$tmp/dotfiles" -c user.name=e2e -c user.email=e2e@example.com commit -qm e2e
  ssh-keygen -q -t ed25519 -N '' -C e2e -f "$tmp/key"
  mkdir -p "$tmp/ac/skills/e2e-hello"
  printf -- '---\nname: e2e-hello\ndescription: e2e 測試用\n---\nhello\n' > "$tmp/ac/skills/e2e-hello/SKILL.md"
  printf 'servers:\n  e2e-mcp:\n    url: https://example.com/mcp\n    targets: [claude]\n' > "$tmp/ac/mcp.yaml"
  git -C "$tmp/ac" init -q -b main
  git -C "$tmp/ac" add -A
  git -C "$tmp/ac" -c user.name=e2e -c user.email=e2e@example.com commit -qm init
  git clone -q --bare "$tmp/ac" "$tmp/agent-config.git"
  rm -rf "$tmp/ac"
  docker exec -u "$CTR_USER" "$CTR" mkdir -p "$FIX"
  tar -C "$tmp" -cf - . | docker exec -i -u "$CTR_USER" "$CTR" tar -C "$FIX" -xf -
  rm -rf "$tmp"
}

# 印出「跑 bootstrap wizard」的容器內指令,交給 step／check 執行。多給的參數轉給 chezmoi init。
# Termux 容器沒有 app 設的 TERMUX_VERSION,由這裡補上。
# EXTRA_ENV 可以再加環境變數、蓋掉上面的預設(例如 HOME=… 換一個空的家目錄)。
bootstrap() {  # bootstrap <輸出 log> <stdin 檔案> [chezmoi init 參數...]
  local log=$1 stdin=$2; shift 2
  local env="BOOTSTRAP_SKIP_GITHUB=1 BOOTSTRAP_REPO=$FIX/dotfiles AGENT_CONFIG_REMOTE=$FIX/agent-config.git ${EXTRA_ENV:-}"
  [ "$TARGET" = termux ] && env="$env TERMUX_VERSION=e2e"
  echo "set -o pipefail; $env bash $FIX/dotfiles/script/bootstrap.sh $(printf '%q ' "$@") < $stdin 2>&1 | tee $log"
}

# wizard 第一次跑完之後,兩個目標共用的檢查。
check_bootstrap() {  # check_bootstrap <ubuntu|termux>
  check "判斷出機器種類是 $1" "grep -q '偵測到 $1' ~/e2e-init.log"
  check "第 2 關:git、ssh、curl 都有" "command -v git && command -v ssh && command -v curl"
  check "第 3 關:貼上的 key 原封不動放在 ~/.ssh/henry5720,權限 600" \
    "cmp ~/.ssh/henry5720 $FIX/key && [ \"\$(stat -c %a ~/.ssh/henry5720)\" = 600 ]"
  check "第 3 關:產生的 .pub 跟原本的公鑰是同一把" \
    "[ \"\$(awk '{print \$2}' ~/.ssh/henry5720.pub)\" = \"\$(awk '{print \$2}' $FIX/key.pub)\" ]"
}

# 重跑整支 wizard、貼錯 key。放在第一次 apply 的檢查之後。
check_bootstrap_rerun() {  # check_bootstrap_rerun <ubuntu|termux>
  bold "▶ 重跑 bootstrap wizard"
  # stdin 給空的:如果第 3 關沒跳過、又去讀 key,會讀到空內容而失敗
  check "重跑 exit 0(不用再貼 key、不用再給 prompt 旗標)" "$(bootstrap '~/e2e-rerun.log' /dev/null --no-tty)"
  check "第 2 關跳過" "grep -q '都裝了，跳過' ~/e2e-rerun.log"
  check "第 3 關跳過" "grep -q '已存在，跳過貼上' ~/e2e-rerun.log"
  check "第 5 關不重裝 chezmoi" "grep -q 'chezmoi 已安裝' ~/e2e-rerun.log"
  if [ "$1" = termux ]; then
    check "authorized_keys 沒有重複加" \
      "grep -q 'authorized_keys 已有這把 key' ~/e2e-rerun.log && [ \"\$(grep -cF \"\$(awk '{print \$2}' $FIX/key.pub)\" ~/.ssh/authorized_keys)\" = 1 ]"
  fi

  bold "▶ bootstrap wizard 貼錯 key(換一個空的家目錄)"
  step "建一個空的家目錄與一段不是 key 的輸入" "rm -rf $FIX/badhome && mkdir $FIX/badhome && echo 'not a key' > $FIX/badkey"
  check "貼錯時 wizard 失敗" "! { $(EXTRA_ENV="HOME=$FIX/badhome BOOTSTRAP_SKIP_UPGRADE=1" bootstrap '~/e2e-badkey.log' "$FIX/badkey" --no-tty); }"
  check "說明是 key 格式不對" "grep -q '不是 OpenSSH 私鑰' ~/e2e-badkey.log"
  check "沒留下 key 檔" "[ -z \"\$(ls -A $FIX/badhome/.ssh)\" ]"
  check "停在第 3 關,沒有往下跑" "! grep -q '4/5' ~/e2e-badkey.log"
  check "BOOTSTRAP_SKIP_UPGRADE=1 時第 1 關只看不升級" "grep -qE '只模擬 upgrade|只列出可升級的套件' ~/e2e-badkey.log"

  # 真的連 GitHub(要能連外的 22 port):假 key 一定被拒。驗的是「被拒就停、不往下 init」;
  # 被接受的那條路要用真的 key,只能人工驗。
  bold "▶ bootstrap wizard 連 GitHub 驗證假 key"
  check "GitHub 拒絕時 wizard 失敗" "! { $(EXTRA_ENV="BOOTSTRAP_SKIP_GITHUB=0 BOOTSTRAP_SKIP_UPGRADE=1" bootstrap '~/e2e-github.log' /dev/null --no-tty); }"
  check "說明是 GitHub 不接受這把 key、停在第 4 關" \
    "grep -q 'GitHub 不接受這把 key' ~/e2e-github.log && grep -q 'Permission denied (publickey)' ~/e2e-github.log && ! grep -q '5/5' ~/e2e-github.log"
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
ZSH_EXTERNALS=(powerlevel10k zsh-autosuggestions zsh-syntax-highlighting)

check_zsh_env() {  # check_zsh_env <印出預設 shell 路徑的容器內指令>
  check "預設 shell 是 zsh" "[ \"\$($1)\" = \"\$(command -v zsh)\" ]"
  for d in "${ZSH_EXTERNALS[@]}"; do
    check "~/.config/zsh/$d 是 git clone" "git -C ~/.config/zsh/$d rev-parse --is-inside-work-tree"
  done
  check "~/.p10k.zsh 已部署" "grep -q POWERLEVEL9K_LEFT_PROMPT_ELEMENTS ~/.p10k.zsh"
  # 沒有 tty 時 p10k 本來就不會跑 wizard,所以另外確認:p10k 有載入、設定檔有被讀到、stderr 是空的。
  # termux-docker 沒有 Android 系統 library,.zshrc 開頭的 fastfetch 一定 link 失敗(真機不會),
  # 只濾掉這一種訊息,其他 stderr 照樣算錯。
  check "zsh -i -c exit 不出錯、p10k 與兩個插件有載入、設定檔有讀到" \
    "if ! err=\$(zsh -i -c '(( \${+functions[p10k]} && \${+functions[_zsh_autosuggest_start]} && \${+ZSH_HIGHLIGHT_VERSION} )) && [[ -n \$POWERLEVEL9K_LEFT_PROMPT_ELEMENTS ]]' 2>&1 >/dev/null); then echo \"zsh 回傳非 0:\$err\"; false; else err=\$(printf '%s\\n' \"\$err\" | grep -v 'CANNOT LINK EXECUTABLE \"fastfetch\"'); [ -z \"\$err\" ] || { echo \"\$err\"; false; }; fi"
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
# 第一次 init 只勾這些;ttyd、wakatime、opencode 故意不勾,之後模擬 edit-config 補勾 wakatime。
# 文件解析兩項一般用不到又重,不在這裡實裝,只做下面的渲染檢查:
# - document-media:apt 裝 ffmpeg、mupdf-tools、pandoc,相依套件一大串
# - ai-document-media:docling + faster-whisper 的 venv,好幾 GB(實裝在一次性容器手動驗過,見 #65)
TOOLS_FIRST=fastfetch/btop/gh/nvm/code-server/tailscale/herdr/claude/codex/codegraph/headless-chrome/playwright-cli/agent-config

# agent-config 的 remote 是 git@github.com(SSH),容器裡沒有能用的 key。
# 測試用 AGENT_CONFIG_REMOTE 換成 $FIX/agent-config.git(見 make_fixtures),
# skillshare 本身照樣從網路裝、照樣 init/install/sync。真的 git@ clone 只在有 key 的機器上會走到。

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
  [wakatime]="command -v wakatime-cli && [ -r ~/.config/zsh/wakatime-zsh-plugin/wakatime.plugin.zsh ]"
  [claude]="command -v claude && claude --version"
  [codex]="command -v codex && codex --version"
  [opencode]="command -v opencode || [ -x ~/.opencode/bin/opencode ]"
  [document-media]="[ \$(dpkg-query -W -f='\${Status}\\n' ffmpeg mupdf-tools pandoc 2>/dev/null | grep -c 'install ok installed') = 3 ]"
  [ai-document-media]="~/.local/share/ai-document-media/venv/bin/python -c 'import docling, faster_whisper'"
  # npm 全域套件裝在 nvm 的 Node 底下,bash -l 不會載入 nvm(那是 .zshrc 的事)
  [codegraph]=". ~/.nvm/nvm.sh && codegraph --version"
  # 真的能 headless 開頁,而且中文／emoji 字型在
  [headless-chrome]="google-chrome --headless --no-sandbox --disable-gpu --dump-dom 'data:text/html,<p>e2e-ok</p>' 2>/dev/null | grep -q e2e-ok && [ \$(dpkg-query -W -f='\${Status}\\n' fonts-noto-cjk fonts-noto-color-emoji 2>/dev/null | grep -c 'install ok installed') = 2 ]"
  # 用 headless-chrome 裝的那支 Chrome 真的開得了頁(它預設找 /opt/google/chrome/chrome,不會自己下載)。
  # 容器擋 user namespace,Chrome sandbox 起不來,所以關掉(同上面 headless-chrome 的 --no-sandbox)
  [playwright-cli]=". ~/.nvm/nvm.sh && playwright-cli --version && PLAYWRIGHT_MCP_SANDBOX=false playwright-cli -s=e2e open 'data:text/html,<title>e2e-ok</title>' | grep -q e2e-ok; r=\$?; playwright-cli -s=e2e close >/dev/null 2>&1; [ \$r = 0 ]"
  # skillshare 從假 remote init 完:repo 在、skill 連進 Claude、MCP 寫進 Claude 的設定
  [agent-config]="command -v skillshare && [ -d ~/.config/skillshare/.git ] && [ -r ~/.claude/skills/e2e-hello/SKILL.md ] && grep -q e2e-mcp ~/.claude.json"
)
check_tool()     { check "選裝工具 $1 已安裝" "${TOOL_CHECK[$1]}"; }
check_no_tool()  { check "選裝工具 $1 沒有安裝" "! { ${TOOL_CHECK[$1]}; }"; }

# 選裝腳本在 chezmoi 裡的名字(scriptState 的 name、dry-run 的 diff 標頭)。從 TOOL_CHECK 產生,
# 加工具時不用再改這裡。名字帶腳本所在的 .chezmoiscripts/;codegraph 的腳本叫 npm-install-codegraph,
# 所以檔名前綴是 (npm-)?install-。
TOOL_SCRIPT_RE="\\.chezmoiscripts/(npm-)?install-($(IFS="|"; echo "${!TOOL_CHECK[*]}"))"

# ===============================================================
# 目標:ubuntu(代表 WSL、雲端主機、proot Ubuntu)
# ===============================================================
# 映像模擬一台全新的 Ubuntu:只有一般使用者 + sudo 免密碼,沒有 git／curl／ssh／chezmoi,
# 全部由 bootstrap wizard 裝。apt 清單刪掉,所以 wizard 一定要自己 apt-get update。
setup_ubuntu() {
  CTR_USER=ubuntu  # ubuntu:24.04 內建的 uid 1000
  CTR_HOME=/home/ubuntu
  docker build -q -t "$IMAGE" - >/dev/null <<'DOCKERFILE' || { red "✗ 建映像失敗"; exit 1; }
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends sudo \
 && rm -rf /var/lib/apt/lists/* \
 && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu
DOCKERFILE
  docker rm -f "$CTR" >/dev/null 2>&1 || true
  docker run -d --name "$CTR" "$IMAGE" sleep infinity >/dev/null
  make_fixtures
}

# 基底套件:跟 home/.chezmoidata/packages.yaml 是兩份獨立的期望值,刻意不從 yaml 讀,
# 不然 yaml 少列一個測試也照樣過。
UBUNTU_BASE=(zsh git curl vim build-essential unzip jq python3)

# 容器裡做不到、刻意不驗的事:
# - tailscale:容器 PID 1 不是 systemd,`systemctl enable --now tailscaled` 一定會跳過。
#   只驗 tailscale 有裝、而且安裝腳本有印出「跳過 systemd」的訊息(證明走到了那個分支、沒有失敗)。
#   真的啟用 tailscaled 要在有 systemd 的機器上人工確認。
# - nvm／code-server／herdr／fastfetch／wakatime 都會連網抓上游 installer 或 release;
#   上游掛掉測試就會紅,這是預期的(它就是要驗真的裝得起來)。
scenario_ubuntu() {
  step "全新機器跑 bootstrap wizard,最後 init --apply(選單只勾一部分)" \
    "$(bootstrap '~/e2e-init.log' "$FIX/key" --no-tty "${INIT_FLAGS[@]}" --promptMultichoice "$TOOLS_PROMPT=$TOOLS_FIRST")"
  check_bootstrap ubuntu
  check "第 1 關有升級:沒有可升級的套件" "apt-get -s upgrade | grep -q '^0 upgraded'"
  check "第 5 關 chezmoi 裝在 ~/.local/bin" "[ -x ~/.local/bin/chezmoi ]"

  bold "▶ 第一次 apply 之後"
  for p in "${UBUNTU_BASE[@]}"; do
    check "基底套件 $p 已安裝" "dpkg-query -W -f='\${Status}' $p | grep -q 'install ok installed'"
  done
  for t in ${TOOLS_FIRST//\// }; do check_tool "$t"; done
  check_no_tool ttyd
  check_no_tool wakatime
  check_no_tool opencode
  check_no_tool document-media
  check_no_tool ai-document-media
  # skillshare 的設定(create_config.yaml)是一般檔案,所有 after_ 腳本都在檔案部署之後跑。
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
  check_zsh_env "getent passwd \$(id -un) | cut -d: -f7"
  check_bootstrap_rerun ubuntu

  bold "▶ 第二次 init／apply"
  check "再 init 一次不問選單(沒給任何 prompt 旗標也能跑完)" "chezmoi init --no-tty"
  check "選擇沒變" "grep -qF 'tools = [\"fastfetch\", \"btop\", \"gh\", \"nvm\", \"code-server\", \"tailscale\", \"herdr\", \"claude\", \"codex\", \"codegraph\", \"headless-chrome\", \"playwright-cli\", \"agent-config\"]' ~/.config/chezmoi/chezmoi.toml"
  check "沒有腳本待跑(chezmoi status 無 R)" "! chezmoi status | grep -E '^.?R'"
  check "換 shell 腳本已記為跑過、第二次不會再跑" \
    "chezmoi state dump --format json | jq -e '[.scriptState[].name] | index(\".chezmoiscripts/set-default-shell.sh\")' && ! chezmoi status | grep -q set-default-shell"
  check "第二次 apply exit 0、apt 沒被呼叫" \
    "before=\$(grep -c '^Commandline:' /var/log/apt/history.log); chezmoi apply --no-tty && [ \"\$(grep -c '^Commandline:' /var/log/apt/history.log)\" = \"\$before\" ]"
  check "chezmoi verify 通過" "chezmoi verify"

  # --prompt 會重問所有問題:非秘密欄位(git 身分)與選單預設帶現值,直接 Enter 保留;
  # 憑證不帶現值(不想明文顯示在提示上),這裡照樣用旗標給。--promptDefaults = 每題都直接 Enter
  # (沒有預設值的題目它還是會去讀 stdin,所以四個憑證都要給)。
  bold "▶ init --prompt 直接 Enter,git 身分與選單保留原值"
  step "記下現在的 tools" "grep '^    tools = ' ~/.config/chezmoi/chezmoi.toml > /tmp/tools-before"
  check "init --prompt --promptDefaults(只給憑證旗標)exit 0" \
    "chezmoi init --prompt --promptDefaults --no-tty $(printf '%q ' "${INIT_FLAGS[@]:0:8}") </dev/null"
  check "gitUserName 保留 e2e" "grep -qx '    gitUserName = \"e2e\"' ~/.config/chezmoi/chezmoi.toml"
  check "gitUserEmail 保留 e2e@example.com" "grep -qx '    gitUserEmail = \"e2e@example.com\"' ~/.config/chezmoi/chezmoi.toml"
  check "tools 保留原本的勾選" "grep -qxFf /tmp/tools-before ~/.config/chezmoi/chezmoi.toml"
  check "之後沒有腳本待跑" "! chezmoi status | grep -E '^.?R'"

  # 改選裝工具的正規做法:chezmoi edit-config 改 [data] tools 那一行,再 apply。
  # edit-config 只是開編輯器,這裡直接 sed config 模擬。
  bold "▶ edit-config 在 tools 多加 wakatime"
  step "config 的 tools 加上 wakatime" \
    "sed -i 's/^    tools = \\[\\(.*\\)\\]\$/    tools = [\\1, \"wakatime\"]/' ~/.config/chezmoi/chezmoi.toml && grep -q '\"wakatime\"\\]\$' ~/.config/chezmoi/chezmoi.toml"
  check "只有 wakatime 的安裝腳本待跑" \
    "[ \"\$(chezmoi status | grep -E '^.?R')\" = \"\$(chezmoi status | grep -E '^.?R.*install-wakatime')\" ] && chezmoi status | grep -qE '^.?R.*install-wakatime'"
  check "apply exit 0" "chezmoi apply --no-tty"
  check_tool wakatime
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

  # WSL 用 Windows 的 Chrome(chrome-mcp),選單不列 headless Chrome。
  # 用 --override-data 蓋 kernel.osrelease 模擬 WSL;--config 指向不存在的檔,
  # promptMultichoiceOnce 才會真的問(--no-tty 沒給旗標 = 用預設值,也就是全部列出來的選項)。
  bold "▶ (渲染)WSL 選單不列 headless Chrome、playwright-cli"
  local wsl='{"chezmoi":{"kernel":{"osrelease":"5.15.167.4-microsoft-standard-WSL2"}}}'
  local tmpl=~/.local/share/chezmoi/home scripts=~/.local/share/chezmoi/home/.chezmoiscripts
  check "(對照)非 WSL 的選單有 headless-chrome" \
    "chezmoi --config /tmp/fresh-linux.toml execute-template --init --no-tty $(printf '%q ' "${INIT_FLAGS[@]}") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"headless-chrome\"'"
  check "(對照)非 WSL 的選單有 playwright-cli" \
    "chezmoi --config /tmp/fresh-linux.toml execute-template --init --no-tty $(printf '%q ' "${INIT_FLAGS[@]}") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"playwright-cli\"'"
  check "WSL 的選單沒有 headless-chrome、playwright-cli(其他 AI 工具照常列)" \
    "chezmoi --config /tmp/fresh-wsl.toml execute-template --init --no-tty --override-data '$wsl' $(printf '%q ' "${INIT_FLAGS[@]}") < $tmpl/.chezmoi.toml.tmpl > /tmp/wsl.toml && grep -q '\"agent-config\"' /tmp/wsl.toml && ! grep -q headless-chrome /tmp/wsl.toml && ! grep -q playwright-cli /tmp/wsl.toml"
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
    "chezmoi --config /tmp/fresh-mint.toml execute-template --init --no-tty --override-data '{\"chezmoi\":{\"osRelease\":{\"id\":\"linuxmint\",\"idLike\":\"ubuntu debian\"}}}' $(printf '%q ' "${INIT_FLAGS[@]}") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"fastfetch\"'"

  # 文件解析兩項不在 e2e 實裝(見 TOOLS_FIRST 上方);只驗勾了才有內容、而且語法對。
  bold "▶ (渲染)document-media"
  check "沒勾時套件腳本不含 ffmpeg" \
    "! chezmoi execute-template < $scripts/run_onchange_before_install-packages.sh.tmpl | grep -q ffmpeg"
  check "勾了套件腳本會裝 ffmpeg、mupdf-tools、pandoc" \
    "chezmoi execute-template --override-data '{\"tools\":[\"document-media\"]}' < $scripts/run_onchange_before_install-packages.sh.tmpl > /tmp/dm.sh && grep -q ffmpeg /tmp/dm.sh && grep -q mupdf-tools /tmp/dm.sh && grep -q pandoc /tmp/dm.sh && sh -n /tmp/dm.sh"

  # 容器的 config 已經勾了 playwright-cli,要蓋成空的才是「沒勾」
  bold "▶ (渲染)playwright-cli"
  check "沒勾時安裝腳本是空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[]}' < $scripts/run_onchange_after_npm-install-playwright-cli.sh.tmpl | tr -d '[:space:]')\" ]"

  bold "▶ (渲染)ai-document-media"
  check "沒勾時安裝腳本是空的" \
    "[ -z \"\$(chezmoi execute-template < $scripts/run_onchange_after_install-ai-document-media.sh.tmpl | tr -d '[:space:]')\" ]"
  check "勾了會渲染出可執行的 sh 腳本" \
    "chezmoi execute-template --override-data '{\"tools\":[\"ai-document-media\"]}' < $scripts/run_onchange_after_install-ai-document-media.sh.tmpl > /tmp/aidm.sh && grep -q docling /tmp/aidm.sh && sh -n /tmp/aidm.sh"
}

# ===============================================================
# 目標:termux(代表原生 Termux)
# ===============================================================
# 映像模擬一台剛裝好的 Termux:什麼都沒裝。git／openssh／chezmoi 由 bootstrap wizard 裝,
# python、jq、zsh 等由 chezmoi 的套件腳本裝。
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
# 加上 modify_ 自己要用的 jq(改 JSON)與 python(改 TOML,套件名是 python,指令是 python3)。
TERMUX_BASE=(zsh git curl vim openssh fastfetch jq python)
APT_LOG='$PREFIX/var/log/apt/history.log'
# nerd-fonts v3.5.1 Hack.tar.xz 裡 HackNerdFont-Regular.ttf 的 sha256,在主機上下載後算的
# (fc-query 確認 family=Hack Nerd Font、style=Regular)。URL 釘 tag,這個值不會變。
HACK_SHA256=8cba545f0ab36d8f313a448676df9988d6c679a014ffed863e52305844e7b113

scenario_termux() {
  # termux-change-repo 是全螢幕選單,容器裡沒辦法操作;先放好它選完會留下的 symlink,
  # 讓 wizard 走「已選過」那條路。真的選 mirror 要在真機上人工驗。
  step "模擬已選過 mirror" "ln -sfn \$PREFIX/etc/termux/mirrors/default \$PREFIX/etc/termux/chosen_mirrors"
  # init 輸出留在 ~/e2e-init.log,給 reload 那項檢查看。
  step "全新 Termux 跑 bootstrap wizard,最後 init --apply" \
    "$(bootstrap '~/e2e-init.log' "$FIX/key" --no-tty "${INIT_FLAGS[@]}")"
  check_bootstrap termux
  check "第 1 關有升級:沒有可升級的套件" "[ -z \"\$(apt list --upgradable 2>/dev/null | grep -v '^Listing')\" ]"
  check "第 1 關跳過 termux-change-repo" "grep -q '已選過 mirror' ~/e2e-init.log"
  check "第 1 關 termux-setup-storage 失敗只警告(容器沒有 Android)" "grep -q 'termux-setup-storage 失敗' ~/e2e-init.log"
  check "第 4 關把公鑰加進 authorized_keys" "[ \"\$(grep -cF \"\$(awk '{print \$2}' $FIX/key.pub)\" ~/.ssh/authorized_keys)\" = 1 ]"
  check "第 5 關 chezmoi 用 pkg 裝" "dpkg-query -W -f='\${Status}' chezmoi | grep -q 'install ok installed'"

  bold "▶ 第一次 apply 之後"
  for p in "${TERMUX_BASE[@]}"; do
    check "基底套件 $p 已安裝" "dpkg-query -W -f='\${Status}' $p | grep -q 'install ok installed'"
  done
  check "modify_ 產物:~/.claude/settings.json 關掉 chrome-devtools plugin" \
    "jq -e '.enabledPlugins[\"chrome-devtools-mcp@claude-plugins-official\"] == false' ~/.claude/settings.json"
  check "modify_ 產物:~/.codex/config.toml 有 codex-lb provider" \
    "python3 -c 'import tomllib,sys; c=tomllib.load(open(sys.argv[1],\"rb\")); assert c[\"model_provider\"]==\"codex-lb-gcp\" and \"codex-lb-gcp\" in c[\"model_providers\"]' ~/.codex/config.toml"
  check "modify_ 產物:~/.codex/personal.config.toml 有 chatgpt 登入" \
    "python3 -c 'import tomllib,sys; c=tomllib.load(open(sys.argv[1],\"rb\")); assert c[\"forced_login_method\"]==\"chatgpt\"' ~/.codex/personal.config.toml"
  check "modify_ 產物:~/.config/opencode/opencode.json 有 repo 的 model" \
    "jq -e '.model == \"codex-lb-gcp/gpt-6-astra\" and .mcp == {}' ~/.config/opencode/opencode.json"
  check "移除 chezmoi MCP 的 python 腳本被排除" "! chezmoi managed --include scripts | grep -q remove-chezmoi-mcp"
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
  check_bootstrap_rerun termux

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
