#!/bin/bash
# 容器 e2e:在全新容器裡從本機 repo 跑 `chezmoi init --apply`,檢查機器上看得到的結果。
#
# 用法:
#   bash script/tests/e2e.sh [ubuntu|termux]     # 預設 ubuntu
#
# 環境變數:
#   E2E_TAG=<字串>   容器名與映像 tag 的後綴,平行跑時避免撞名(預設 local)
#   E2E_KEEP=1       跑完不刪容器,方便 `docker exec -it <容器> bash` 進去看
#
# 測的是 repo 的工作目錄(含未 commit 的修改),不經過 GitHub。
# 秘密類 prompt 用 --promptString 給假值。
#
# 要加檢查項目:改下面「檢查清單」那一段的 scenario_<目標>,其他地方不用動。
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

# 把 repo 工作目錄(含未 commit、不含 .gitignore 擋掉的)複製到容器的 chezmoi source 位置。
copy_repo() {  # copy_repo <容器內目錄>
  docker exec -u "$CTR_USER" "$CTR" mkdir -p "$1"
  (cd "$REPO" && git ls-files -co --exclude-standard -z \
    | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
    | tar --null -T - -cf -) \
    | docker exec -i -u "$CTR_USER" "$CTR" tar -C "$1" -xf -
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
# 目標:ubuntu(代表 WSL、雲端主機、proot Ubuntu)
# ===============================================================
# 映像模擬「bootstrap 跑完、還沒 chezmoi init」的機器:一般使用者 + sudo 免密碼,
# 已有 bootstrap 會裝的 git／curl／openssh-client 與 ~/.local/bin/chezmoi。
# apt 清單刪掉,所以套件腳本一定要自己 apt-get update。
setup_ubuntu() {
  CTR_USER=ubuntu  # ubuntu:24.04 內建的 uid 1000
  CTR_HOME=/home/ubuntu
  docker build -q -t "$IMAGE" - >/dev/null <<'DOCKERFILE' || { red "✗ 建映像失敗"; exit 1; }
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends sudo ca-certificates git curl openssh-client \
 && rm -rf /var/lib/apt/lists/* \
 && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu
USER ubuntu
RUN sh -c "$(curl -fsSL https://get.chezmoi.io)" -- -b /home/ubuntu/.local/bin
DOCKERFILE
  docker rm -f "$CTR" >/dev/null 2>&1 || true
  docker run -d --name "$CTR" "$IMAGE" sleep infinity >/dev/null
  copy_repo "$CTR_HOME/.local/share/chezmoi"
}

# ===============================================================
# 檢查清單
# ===============================================================
# 基底套件:跟 home/.chezmoidata/packages.yaml 是兩份獨立的期望值,刻意不從 yaml 讀,
# 不然 yaml 少列一個測試也照樣過。
UBUNTU_BASE=(zsh git curl vim build-essential unzip jq python3)

# 選裝工具選單。--promptMultichoice 的 key 也是「提示文字」,值用 / 分隔。
TOOLS_PROMPT='選裝工具（空白鍵勾選，Enter 確定）'
# 第一次 init 只勾這些;ttyd、wakatime、opencode、ai-document-media 故意不勾,之後用 --prompt 補勾 wakatime。
# ai-document-media(docling + faster-whisper,venv 好幾 GB)不在這裡實裝,只做下面的渲染檢查;
# 實裝在一次性容器手動驗過(見 #65 的回報)。
TOOLS_FIRST=fastfetch/btop/gh/nvm/code-server/tailscale/herdr/claude/codex/document-media/codegraph/headless-chrome/agent-config
TOOLS_SECOND=$TOOLS_FIRST/wakatime

# agent-config 的 remote 是 git@github.com(SSH),容器裡沒有 key。
# 測試用 AGENT_CONFIG_REMOTE 換成容器裡的本機 bare repo(內容是假的一個 skill + 一個 MCP server),
# skillshare 本身照樣從網路裝、照樣 init/install/sync。真的 git@ clone 只在有 key 的機器上會走到。
AGENT_CONFIG_FIXTURE=/tmp/agent-config.git
make_agent_config_fixture() {
  step "建 agent-config 的假 remote(本機 bare repo)" "set -e
    rm -rf /tmp/agent-config-src $AGENT_CONFIG_FIXTURE
    mkdir -p /tmp/agent-config-src/skills/e2e-hello && cd /tmp/agent-config-src
    printf -- '---\nname: e2e-hello\ndescription: e2e 測試用\n---\nhello\n' > skills/e2e-hello/SKILL.md
    printf 'servers:\n  e2e-mcp:\n    url: https://example.com/mcp\n    targets: [claude]\n' > mcp.yaml
    git init -q -b main && git add -A && git -c user.name=e2e -c user.email=e2e@example.com commit -qm init
    git clone -q --bare . $AGENT_CONFIG_FIXTURE"
}

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
  # skillshare 從假 remote init 完:repo 在、skill 連進 Claude、MCP 寫進 Claude 的設定
  [agent-config]="command -v skillshare && [ -d ~/.config/skillshare/.git ] && [ -r ~/.claude/skills/e2e-hello/SKILL.md ] && grep -q e2e-mcp ~/.claude.json"
)
check_tool()     { check "選裝工具 $1 已安裝" "${TOOL_CHECK[$1]}"; }
check_no_tool()  { check "選裝工具 $1 沒有安裝" "! { ${TOOL_CHECK[$1]}; }"; }

# 容器裡做不到、刻意不驗的事:
# - tailscale:容器 PID 1 不是 systemd,`systemctl enable --now tailscaled` 一定會跳過。
#   只驗 tailscale 有裝、而且安裝腳本有印出「跳過 systemd」的訊息(證明走到了那個分支、沒有失敗)。
#   真的啟用 tailscaled 要在有 systemd 的機器上人工確認。
# - nvm／code-server／herdr／fastfetch／wakatime 都會連網抓上游 installer 或 release;
#   上游掛掉測試就會紅,這是預期的(它就是要驗真的裝得起來)。
scenario_ubuntu() {
  make_agent_config_fixture
  step "從零 chezmoi init --apply(選單只勾一部分)" \
    "set -o pipefail; AGENT_CONFIG_REMOTE=$AGENT_CONFIG_FIXTURE chezmoi init --apply --no-tty $(printf '%q ' "${INIT_FLAGS[@]}" --promptMultichoice "$TOOLS_PROMPT=$TOOLS_FIRST") 2>&1 | tee ~/e2e-init.log"

  bold "▶ 第一次 apply 之後"
  for p in "${UBUNTU_BASE[@]}"; do
    check "基底套件 $p 已安裝" "dpkg-query -W -f='\${Status}' $p | grep -q 'install ok installed'"
  done
  for t in ${TOOLS_FIRST//\// }; do check_tool "$t"; done
  check_no_tool ttyd
  check_no_tool wakatime
  check_no_tool opencode
  check_no_tool ai-document-media
  # skillshare 的設定(create_config.yaml)是一般檔案,所有 after_ 腳本都在檔案部署之後跑。
  # 腳本找不到 config.yaml 會失敗;apply 有跑完、上面 agent-config 的檢查過了,就代表順序對。
  check "agent-config 用的是 chezmoi 放的 skillshare 設定(targets 有 claude、codex)" \
    "grep -q 'path: ~/.claude/skills' ~/.config/skillshare/config.yaml && [ -e ~/.agents/skills/e2e-hello ]"
  check "tailscale 在沒有 systemd 時跳過啟用,而不是失敗" "grep -q 'PID 1 不是 systemd' ~/e2e-init.log"
  check "zshrc 沒被 installer 改動(nvm 等不能往 ~/.zshrc 追加)" "chezmoi verify ~/.zshrc"
  # Termux 用 .chezmoiignore 排除這支;Ubuntu 上要照常跑(scriptState 記下它的名字就是跑完了)。
  check "移除 chezmoi MCP 的 python 腳本有跑" \
    "chezmoi state dump --format json | jq -e '[.scriptState[].name] | index(\"remove-chezmoi-mcp.py\")'"

  bold "▶ 第二次 init／apply"
  check "再 init 一次不問選單(沒給任何 prompt 旗標也能跑完)" "chezmoi init --no-tty"
  check "選擇沒變" "grep -qF 'tools = [\"fastfetch\", \"btop\", \"gh\", \"nvm\", \"code-server\", \"tailscale\", \"herdr\", \"claude\", \"codex\", \"document-media\", \"codegraph\", \"headless-chrome\", \"agent-config\"]' ~/.config/chezmoi/chezmoi.toml"
  check "沒有腳本待跑(chezmoi status 無 R)" "! chezmoi status | grep -E '^.?R'"
  check "第二次 apply exit 0、apt 沒被呼叫" \
    "before=\$(grep -c '^Commandline:' /var/log/apt/history.log); chezmoi apply --no-tty && [ \"\$(grep -c '^Commandline:' /var/log/apt/history.log)\" = \"\$before\" ]"
  check "chezmoi verify 通過" "chezmoi verify"

  bold "▶ init --prompt 多勾 wakatime"
  check "init --prompt exit 0" \
    "chezmoi init --prompt --no-tty $(printf '%q ' "${INIT_FLAGS[@]}" --promptMultichoice "$TOOLS_PROMPT=$TOOLS_SECOND")"
  check "只有 wakatime 的安裝腳本待跑" \
    "[ \"\$(chezmoi status | grep -E '^.?R')\" = \"\$(chezmoi status | grep -E '^.?R.*install-wakatime')\" ] && chezmoi status | grep -qE '^.?R.*install-wakatime'"
  check "apply exit 0" "chezmoi apply --no-tty"
  check_tool wakatime
  check_no_tool ttyd
  check "之後再 apply 沒有腳本待跑" "! chezmoi status | grep -E '^.?R'"

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
    "chezmoi --destination /tmp/linux-home --persistent-state /tmp/linux.boltdb apply --dry-run --verbose --no-tty 2>&1 | grep -q '^diff --git a/install-fastfetch'"
  check "android 上沒有任何選裝工具的腳本會跑" \
    "out=\$(chezmoi --config /tmp/android.toml --override-data '$android' --destination /tmp/android-home --persistent-state /tmp/android.boltdb apply --dry-run --verbose --no-tty 2>&1); ! printf '%s' \"\$out\" | grep -E '^diff --git a/(npm-)?install-(fastfetch|btop|gh|nvm|code-server|tailscale|herdr|ttyd|wakatime|claude|codex|opencode|document-media|ai-document-media|codegraph|headless-chrome|agent-config)'"

  # WSL 用 Windows 的 Chrome(chrome-mcp),選單不列 headless Chrome。
  # 用 --override-data 蓋 kernel.osrelease 模擬 WSL;--config 指向不存在的檔,
  # promptMultichoiceOnce 才會真的問(--no-tty 沒給旗標 = 用預設值,也就是全部列出來的選項)。
  bold "▶ (渲染)WSL 選單不列 headless Chrome"
  local wsl='{"chezmoi":{"kernel":{"osrelease":"5.15.167.4-microsoft-standard-WSL2"}}}'
  local tmpl=~/.local/share/chezmoi/home
  check "(對照)非 WSL 的選單有 headless-chrome" \
    "chezmoi --config /tmp/fresh-linux.toml execute-template --init --no-tty $(printf '%q ' "${INIT_FLAGS[@]}") < $tmpl/.chezmoi.toml.tmpl | grep -q '\"headless-chrome\"'"
  check "WSL 的選單沒有 headless-chrome(其他 AI 工具照常列)" \
    "chezmoi --config /tmp/fresh-wsl.toml execute-template --init --no-tty --override-data '$wsl' $(printf '%q ' "${INIT_FLAGS[@]}") < $tmpl/.chezmoi.toml.tmpl > /tmp/wsl.toml && grep -q '\"agent-config\"' /tmp/wsl.toml && ! grep -q headless-chrome /tmp/wsl.toml"
  check "WSL 上就算 tools 裡有 headless-chrome,安裝腳本也渲染成空的" \
    "[ -z \"\$(chezmoi execute-template --override-data '{\"tools\":[\"headless-chrome\"],\"chezmoi\":{\"kernel\":{\"osrelease\":\"5.15.167.4-microsoft-standard-WSL2\"}}}' < $tmpl/run_onchange_after_install-headless-chrome.sh.tmpl | tr -d '[:space:]')\" ]"

  # ai-document-media 的 venv(docling 會拉 torch)太大,不在 e2e 實裝;只驗勾了才有內容、而且語法對。
  bold "▶ (渲染)ai-document-media"
  check "沒勾時安裝腳本是空的" \
    "[ -z \"\$(chezmoi execute-template < $tmpl/run_onchange_after_install-ai-document-media.sh.tmpl | tr -d '[:space:]')\" ]"
  check "勾了會渲染出可執行的 sh 腳本" \
    "chezmoi execute-template --override-data '{\"tools\":[\"ai-document-media\"]}' < $tmpl/run_onchange_after_install-ai-document-media.sh.tmpl > /tmp/aidm.sh && grep -q docling /tmp/aidm.sh && sh -n /tmp/aidm.sh"
}

# Termux 基底:spec 的 zsh git curl vim openssh fastfetch,
# 加上 modify_ 自己要用的 jq(改 JSON)與 python(改 TOML,套件名是 python,指令是 python3)。
TERMUX_BASE=(zsh git curl vim openssh fastfetch jq python)
APT_LOG='$PREFIX/var/log/apt/history.log'

scenario_termux() {
  step "從零 chezmoi init --apply" "chezmoi init --apply --no-tty $(printf '%q ' "${INIT_FLAGS[@]}")"

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
  # init 沒給 --promptMultichoice 也跑完了,本身就證明沒出選單;再確認存下來的是空清單、選裝腳本一支都沒跑
  check "沒有選裝工具選單(config 的 tools 是空的)" "grep -qx '    tools = \\[\\]' ~/.config/chezmoi/chezmoi.toml"
  check "選裝工具的腳本一支都沒跑" \
    "! chezmoi state dump --format json | jq -r '.scriptState[].name' | grep -E '^install-(fastfetch|btop|gh|nvm|code-server|tailscale|herdr|ttyd|wakatime|claude|codex|opencode|document-media|ai-document-media|codegraph|headless-chrome|agent-config)'"

  bold "▶ 第二次 apply"
  check "沒有腳本待跑(chezmoi status 無 R)" "! chezmoi status | grep -E '^.?R'"
  check "第二次 apply exit 0、pkg 沒被呼叫" \
    "before=\$(grep -c '^Commandline:' $APT_LOG); chezmoi apply --no-tty && [ \"\$(grep -c '^Commandline:' $APT_LOG)\" = \"\$before\" ]"
  check "chezmoi verify 通過" "chezmoi verify"
}

# ===============================================================
# 目標:termux(代表原生 Termux)
# ===============================================================
# 映像模擬「pkg install chezmoi 之後、還沒 init」的 Termux:只有 chezmoi,
# 沒有 git、python、jq、zsh,全部要靠套件腳本裝。
# 基底映像的 entrypoint 會以 root 起動再 su 成 system(uid 1000),第一次執行時跑完
# bootstrap second stage;build 時先跑一次,之後的容器就不用再等。
# 容器裡沒有 Android 系統 CA,go-git 走 https 會 x509 失敗,所以設 SSL_CERT_FILE(真機不需要)。
setup_termux() {
  CTR_USER=system
  CTR_HOME=/data/data/com.termux/files/home
  docker build -q -t "$IMAGE" - >/dev/null <<'DOCKERFILE' || { red "✗ 建映像失敗"; exit 1; }
FROM termux/termux-docker:x86_64
ENV SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
RUN /entrypoint.sh bash -lc 'pkg install -y chezmoi'
DOCKERFILE
  docker rm -f "$CTR" >/dev/null 2>&1 || true
  docker run -d --name "$CTR" "$IMAGE" sleep infinity >/dev/null
  copy_repo "$CTR_HOME/.local/share/chezmoi"
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
