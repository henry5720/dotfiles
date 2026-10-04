#!/data/data/com.termux/files/usr/bin/bash
# 在原生 Termux 跑：把 proot Ubuntu 準備成「一台有一般使用者、能 sudo 的 Ubuntu」，
# 之後進去跑同一支 bootstrap。可以重複執行，已經做過的步驟會跳過。
#
# 用法：bash setup-proot-ubuntu.sh [使用者名稱]    # 預設 henry（跟 ssh config 的 User 一致）
set -euo pipefail

name="${1:-henry}"
if ! [[ "$name" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "使用者名稱不合法：$name（只能小寫英數、_、-，開頭不能是數字或 -）" >&2
  exit 1
fi

# 1. 沒有 proot-distro 就裝
command -v proot-distro >/dev/null || pkg install -y proot-distro

# 2. 還登入不了 ubuntu 就安裝 rootfs
if ! proot-distro login ubuntu -- true >/dev/null 2>&1; then
  proot-distro install ubuntu
fi

# 3. 在 proot Ubuntu 裡以 root 建使用者、裝 sudo、設密碼
#    密碼已經設過就不再問，重跑不會改到現有密碼
proot-distro login ubuntu -- bash -c '
  set -euo pipefail
  name="$1"
  # sudo 會拉進 tzdata，不設 noninteractive 會卡在時區選單
  if ! command -v sudo >/dev/null; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y sudo
  fi
  if id -u "$name" >/dev/null 2>&1; then
    usermod -aG sudo "$name"
  else
    useradd -m -s /bin/bash -G sudo "$name"
  fi
  if [ "$(passwd -S "$name" | cut -d " " -f 2)" != P ]; then
    echo "設定 $name 的密碼（sudo 會用到）："
    passwd "$name"
  fi
' _ "$name"

# 4. 下一步
cat <<MSG

proot Ubuntu 的使用者 $name 準備好了。下一步：
  proot-distro login ubuntu --user $name
進去之後當成一台 Ubuntu，跑 bootstrap：
  bash <(curl -fsSL https://raw.githubusercontent.com/henry5720/dotfiles/main/script/bootstrap.sh)
MSG
