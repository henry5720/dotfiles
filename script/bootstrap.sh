#!/bin/bash
# 新機器的 bootstrap wizard：把一台全新的 Ubuntu 或原生 Termux 帶到
# `chezmoi init --apply` 成功的狀態。之後的套件、zsh、選裝工具全部由 chezmoi 接手。
#
# 用法（repo 是公開的；不要用 `curl | bash`，那樣 stdin 被吃掉，wizard 讀不到你貼的 key）：
#   bash <(curl -fsSL https://raw.githubusercontent.com/henry5720/dotfiles/main/script/bootstrap.sh)
#
# 每一關都能重跑，已經做過的會跳過。多給的參數原樣轉給 `chezmoi init`。
# 之後要改選裝工具用 `chezmoi edit-config` 改 tools 再 `chezmoi apply`，不必重跑這支
# （`--prompt` 也能重選，但會重問憑證、直接 Enter 會清空，見 README）。
#
# 測試用的環境變數（平常不用設，見 script/tests/e2e.sh）：
#   BOOTSTRAP_SKIP_UPGRADE=1  第 1 關只更新套件清單、模擬 upgrade，不真的升級
#   BOOTSTRAP_SKIP_GITHUB=1   第 4 關不連 GitHub 驗證 key（容器裡沒有真的 key）
#   BOOTSTRAP_REPO=<路徑或 URL>  第 5 關改從這裡 init，不走 `--ssh henry5720`
#
# 機器種類用 $TERMUX_VERSION 判斷（Termux app 會設）：有就是原生 Termux，沒有就當 Ubuntu
# （WSL、雲端主機、proot Ubuntu 都一樣）。
set -euo pipefail

KEY=~/.ssh/henry5720   # 檔名寫死：ssh config 的 IdentityFile 就是它，init 時 config 還沒部署
SSH_OPTS="-i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

bold() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '\033[33m   ! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m   ✗ %s\033[0m\n' "$*" >&2; exit 1; }

if [ -n "${TERMUX_VERSION:-}" ]; then
  PLATFORM=termux
else
  PLATFORM=ubuntu
  # 已經是 root（例如 proot 裡還沒建使用者）就不用 sudo
  if [ "$(id -u)" = 0 ]; then SUDO=(); else SUDO=(sudo); fi
fi

# Ubuntu 26.04 裝套件可能拉進 tzdata，不設 noninteractive 會卡在時區選單。
# sudo 會清掉環境變數，所以用 env 帶進去。
apt_get() { "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get "$@"; }
# Termux 升級時保留使用者改過的設定檔，不跳 dpkg 的設定檔衝突問題
pkg_q() { DEBIAN_FRONTEND=noninteractive pkg "$@"; }

echo "bootstrap：偵測到 $PLATFORM"

# 1. 系統更新
bold "1/5 系統更新"
if [ "$PLATFORM" = termux ]; then
  # termux-change-repo 選完會留下 chosen_mirrors 這個 symlink
  if [ -L "$PREFIX/etc/termux/chosen_mirrors" ]; then
    info "已選過 mirror，跳過 termux-change-repo"
  else
    termux-change-repo
  fi
  if [ "${BOOTSTRAP_SKIP_UPGRADE:-}" = 1 ]; then
    apt update
    info "BOOTSTRAP_SKIP_UPGRADE=1，只列出可升級的套件："
    apt list --upgradable 2>/dev/null | sed 's/^/   /'
  else
    pkg_q upgrade -y -o Dpkg::Options::=--force-confold
  fi
  if [ -d ~/storage ]; then
    info "~/storage 已存在，跳過 termux-setup-storage"
  else
    # 會跳出 Android 的權限對話框；沒授權不影響後面的步驟，所以失敗只警告
    termux-setup-storage || warn "termux-setup-storage 失敗，之後可以自己再跑一次"
  fi
else
  apt_get update
  if [ "${BOOTSTRAP_SKIP_UPGRADE:-}" = 1 ]; then
    info "BOOTSTRAP_SKIP_UPGRADE=1，只模擬 upgrade："
    apt_get -s upgrade | tail -n 3 | sed 's/^/   /'
  else
    apt_get upgrade -y
  fi
fi

# 2. 裝 git openssh curl（先有 git，clone 才不依賴 chezmoi 內建 go-git 的 SSH）
bold "2/5 裝 git openssh curl"
if [ "$PLATFORM" = termux ]; then
  pkgs=(git openssh curl)
else
  pkgs=(git openssh-client curl ca-certificates)  # ca-certificates：get.chezmoi.io 走 https
fi
# 算缺哪些套件:home/run_onchange_before_install-packages.sh.tmpl 有同一段。
# 這裡在 chezmoi 之前跑、用不到 chezmoi 的樣板,所以兩份各自維護。
missing=()
for p in "${pkgs[@]}"; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
done
if [ ${#missing[@]} -eq 0 ]; then
  info "都裝了，跳過"
elif [ "$PLATFORM" = termux ]; then
  pkg_q install -y "${missing[@]}"
else
  apt_get install -y --no-install-recommends "${missing[@]}"
fi

# 3. 放 ~/.ssh/henry5720
bold "3/5 SSH key（$KEY）"
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [ -f "$KEY" ]; then
  info "已存在，跳過貼上"
else
  while :; do
    if [ -t 0 ]; then
      info "在舊機器執行 cat ~/.ssh/henry5720，把整段（含 BEGIN/END 那兩行）貼上，"
      info "貼完換行後按 Ctrl-D："
    fi
    tmp="$KEY.tmp"
    # 終端機貼上可能帶 \r；結尾補換行，OpenSSH 少了最後的換行會讀不進去
    tr -d '\r' | sed -e '$a\' > "$tmp"
    chmod 600 "$tmp"
    if ssh-keygen -y -f "$tmp" > "$tmp.pub"; then
      mv "$tmp" "$KEY"
      mv "$tmp.pub" "$KEY.pub"
      info "key 格式正確，已產生 $KEY.pub"
      break
    fi
    rm -f "$tmp" "$tmp.pub"
    [ -t 0 ] || die "讀到的內容不是 OpenSSH 私鑰"
    warn "這不是 OpenSSH 私鑰，再貼一次"
  done
fi
chmod 600 "$KEY"
if [ ! -f "$KEY.pub" ]; then
  ssh-keygen -y -f "$KEY" > "$KEY.pub"
  info "補產生 $KEY.pub"
fi

# 4. 驗證 key；Termux 另外把公鑰加進 authorized_keys，讓 ssh config 的 phone／pad 連得進來
bold "4/5 驗證 key"
if [ "$PLATFORM" = termux ]; then
  auth=~/.ssh/authorized_keys
  blob=$(awk '{print $2}' "$KEY.pub")   # 只比對 key 本體，同一把 key 註解不同也算已經有
  if [ -f "$auth" ] && grep -qF "$blob" "$auth"; then
    info "authorized_keys 已有這把 key，跳過"
  else
    cat "$KEY.pub" >> "$auth"
    chmod 600 "$auth"
    info "已加進 $auth"
  fi
fi
if [ "${BOOTSTRAP_SKIP_GITHUB:-}" = 1 ]; then
  info "BOOTSTRAP_SKIP_GITHUB=1，不連 GitHub 驗證"
else
  # 驗證成功時 GitHub 也回 exit 1（不給 shell），所以看訊息不看 exit code
  github_ok() {
    local out
    # shellcheck disable=SC2086
    out=$(ssh $SSH_OPTS -T git@github.com 2>&1) || true
    printf '   %s\n' "$out"
    grep -q 'successfully authenticated' <<<"$out"
  }
  until github_ok; do
    [ -t 0 ] || die "GitHub 不接受這把 key"
    warn "GitHub 不接受這把 key。確認下面這把公鑰在 https://github.com/settings/keys："
    sed 's/^/   /' "$KEY.pub"
    read -rp "   加好後按 Enter 重試（輸入 q 離開）：" ans || exit 1
    [ "$ans" = q ] && exit 1
  done
fi

# 5. 裝 chezmoi，然後 init --apply
bold "5/5 chezmoi init --apply"
export PATH="$HOME/.local/bin:$PATH"
if command -v chezmoi >/dev/null; then
  info "chezmoi 已安裝（$(command -v chezmoi)），跳過"
elif [ "$PLATFORM" = termux ]; then
  pkg_q install -y chezmoi
else
  # 不用 snap：/snap/bin 的 PATH 問題，而且 proot／容器沒有 snapd
  # 先下載再跑:寫成 sh -c "$(curl …)" 的話 curl 失敗會變成跑一段空字串、exit 0
  installer=$(mktemp)
  curl -fsSL -o "$installer" https://get.chezmoi.io
  sh "$installer" -b ~/.local/bin
  rm -f "$installer"
fi
# ssh config 還沒部署，clone 要明確指定 key。source 已經存在時 chezmoi 不會再 clone，重跑沒事。
if [ -n "${BOOTSTRAP_REPO:-}" ]; then
  repo=("$BOOTSTRAP_REPO")
else
  repo=(--ssh henry5720)
fi
GIT_SSH_COMMAND="ssh $SSH_OPTS" chezmoi init --apply "${repo[@]}" "$@"

bold "完成"
info "重開終端機（或 exec zsh）就是新的 shell。"
