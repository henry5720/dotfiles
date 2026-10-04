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
# 輸出存進 $OUT,呼叫端決定要不要印。
in_ctr() {
  OUT=$(docker exec -u "$CTR_USER" -w "/home/$CTR_USER" "$CTR" bash -lc "$1" 2>&1)
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
  copy_repo "/home/$CTR_USER/.local/share/chezmoi"
}

# ===============================================================
# 檢查清單
# ===============================================================
# 基底套件:跟 home/.chezmoidata/packages.yaml 是兩份獨立的期望值,刻意不從 yaml 讀,
# 不然 yaml 少列一個測試也照樣過。
UBUNTU_BASE=(zsh git curl vim build-essential unzip jq python3)

scenario_ubuntu() {
  step "從零 chezmoi init --apply" "chezmoi init --apply --no-tty $(printf '%q ' "${INIT_FLAGS[@]}")"

  bold "▶ 第一次 apply 之後"
  for p in "${UBUNTU_BASE[@]}"; do
    check "基底套件 $p 已安裝" "dpkg-query -W -f='\${Status}' $p | grep -q 'install ok installed'"
  done

  bold "▶ 第二次 apply"
  check "沒有腳本待跑(chezmoi status 無 R)" "! chezmoi status | grep -E '^.?R'"
  check "第二次 apply exit 0、apt 沒被呼叫" \
    "before=\$(grep -c '^Commandline:' /var/log/apt/history.log); chezmoi apply --no-tty && [ \"\$(grep -c '^Commandline:' /var/log/apt/history.log)\" = \"\$before\" ]"
  check "chezmoi verify 通過" "chezmoi verify"

  bold "▶ 套件清單加一個套件"
  step "yaml 加上 tree" "printf '    - tree\n' >> ~/.local/share/chezmoi/home/.chezmoidata/packages.yaml"
  check "套件腳本待跑(chezmoi status 有 R)" "chezmoi status | grep -E '^.?R.*install-packages'"
  check "apply exit 0" "chezmoi apply --no-tty"
  check "只裝了 tree" "tail -n 20 /var/log/apt/history.log | grep '^Commandline:' | tail -n 1 | grep -qx 'Commandline: apt-get install -y tree'"
  check "tree 已安裝" "dpkg-query -W -f='\${Status}' tree | grep -q 'install ok installed'"
}

# ===============================================================
# 目標:termux(代表原生 Termux)
# ===============================================================
setup_termux() {
  red "termux 目標還沒實作(之後的票會補 setup_termux 與 scenario_termux)"
  exit 2
}
scenario_termux() { :; }

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
