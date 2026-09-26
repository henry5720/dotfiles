#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
DRY_RUN="${DRY_RUN:-0}"
INPUT_SRC="${INPUT_SRC:-/dev/tty}"
TOOLS=(fastfetch btop nvm code-server tailscale wakatime herdr gh ttyd)
TOOL_LABELS=(fastfetch btop nvm code-server tailscale 'WakaTime zsh tracking' herdr 'GitHub CLI (gh)' ttyd)

is_installed() {
  case "$1" in
    fastfetch|btop|code-server|tailscale|herdr|gh|ttyd) command -v "$1" &>/dev/null ;;
    wakatime) command -v wakatime-cli &>/dev/null ;;
    nvm) [ -d "$HOME/.nvm" ] ;;
    *) return 1 ;;
  esac
}

install_fastfetch() {
  is_installed fastfetch && { echo -e "${BLUE}✅ fastfetch 已安裝。${NC}"; return; }
  echo -e "${GREEN}📦 安裝 fastfetch...${NC}"
  local asset url deb arch; arch=$(dpkg --print-architecture)
  case "$arch" in amd64) asset=amd64;; arm64) asset=aarch64;; armhf) asset=armv7l;; *) echo "⚠️ fastfetch 不支援架構 $arch，跳過。"; return;; esac
  url=$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | grep -o 'https://[^"]*/fastfetch-linux-'"$asset"'\.deb' | head -1)
  [ -n "$url" ] || { echo "⚠️ 找不到 fastfetch release asset，跳過。"; return; }
  deb=$(mktemp --suffix=.deb); curl -fsSL "$url" -o "$deb"; sudo dpkg -i "$deb" || sudo apt install -f -y; rm -f "$deb"
}
install_btop() { is_installed btop && { echo -e "${BLUE}✅ btop 已安裝。${NC}"; return; }; sudo apt update; sudo apt install -y btop; }
# daily-worklog、slack-list 兩支 skill 會叫 gh(見 agent-config 的 SKILL.md)。
# ponytail: 用 Ubuntu 套件庫的版本，較舊；它們只用 gh api 與 issue 指令，夠用。要新版再換 GitHub 官方 apt 源。
install_gh() { is_installed gh && { echo -e "${BLUE}✅ gh 已安裝。${NC}"; return; }; sudo apt update; sudo apt install -y gh; echo '登入：gh auth login'; }
install_nvm() {
  is_installed nvm && { echo -e "${BLUE}✅ nvm 已安裝。${NC}"; return; }
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm install --lts
}
install_code_server() {
  is_installed code-server || curl -fsSL https://code-server.dev/install.sh | sh
  echo '設定檔由 chezmoi 部署；臨時用直接跑 code-server，要常駐見 docs/code-server-remote.md'
}
install_tailscale() {
  is_installed tailscale && { echo -e "${BLUE}✅ Tailscale 已安裝。${NC}"; return; }
  curl -fsSL https://tailscale.com/install.sh | sh
  if [ "$(ps -p 1 -o comm=)" = systemd ]; then
    sudo systemctl enable --now tailscaled
  else
    echo '⚠️ WSL PID 1 不是 systemd，已安裝但未啟動 tailscaled；請啟用 WSL systemd 後再啟動。'
  fi
  echo '不會執行 tailscale up；請自行登入與設定。'
}
install_herdr() {
  is_installed herdr && { echo -e "${BLUE}✅ herdr 已安裝。${NC}"; return; }
  echo -e "${GREEN}📦 安裝 herdr...${NC}"
  curl -fsSL https://herdr.dev/install.sh | sh
}
# 把 terminal 開成網頁，臨時給沒有 tailscale／ssh key 的人用。怎麼開、怎麼收見 docs/code-server-remote.md。
install_ttyd() {
  is_installed ttyd && { echo -e "${BLUE}✅ ttyd 已安裝。${NC}"; return; }
  echo -e "${GREEN}📦 安裝 ttyd...${NC}"
  local arch; arch=$(uname -m)
  case "$arch" in x86_64|aarch64) ;; *) echo "⚠️ ttyd 不支援架構 $arch，跳過。"; return;; esac
  mkdir -p "$HOME/.local/bin"
  curl -fsSL -o "$HOME/.local/bin/ttyd" "https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.$arch"
  chmod +x "$HOME/.local/bin/ttyd"
}
install_wakatime() {
  command -v wakatime-cli &>/dev/null && echo -e "${BLUE}✅ wakatime-cli 已安裝。${NC}" || {
    if ! command -v unzip &>/dev/null; then
      echo '📦 缺少 unzip，先安裝。'
      sudo apt update
      sudo apt install -y unzip
    fi
    local arch asset url tmp; arch=$(uname -m)
    case "$arch" in x86_64|amd64) asset=amd64;; aarch64|arm64) asset=arm64;; *) echo "⚠️ WakaTime CLI 不支援架構 $arch，明確停止。" >&2; return 1;; esac
    url=$(curl -fsSL https://api.github.com/repos/wakatime/wakatime-cli/releases/latest | grep -o 'https://[^"]*wakatime-cli-linux-'"$asset"'\.zip' | head -1)
    [ -n "$url" ] || { echo '⚠️ 找不到 WakaTime CLI release asset。' >&2; return 1; }
    tmp=$(mktemp -d); curl -fsSL "$url" -o "$tmp/wakatime.zip"; unzip -q "$tmp/wakatime.zip" -d "$tmp"
    mkdir -p "$HOME/.local/bin"; install -m 755 "$tmp/wakatime-cli" "$HOME/.local/bin/wakatime-cli"; rm -rf "$tmp"
  }
  mkdir -p "$HOME/.config/zsh"
  if [ ! -d "$HOME/.config/zsh/wakatime-zsh-plugin" ]; then
    git clone --depth=1 https://github.com/sobolevn/wakatime-zsh-plugin.git "$HOME/.config/zsh/wakatime-zsh-plugin"
  fi
}

echo '請選擇一般工具（空格分隔多選，直接 Enter = 全部）：'
for i in "${!TOOLS[@]}"; do is_installed "${TOOLS[$i]}" && mark=' ✅' || mark=''; printf '  %d) %s%s\n' "$((i+1))" "${TOOL_LABELS[$i]}" "$mark"; done
printf '> '; picks=(); read -a picks <"$INPUT_SRC" || true
selected=(); if [ "${#picks[@]}" -eq 0 ]; then selected=("${TOOLS[@]}"); else for n in "${picks[@]}"; do [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#TOOLS[@]}" ] && selected+=("${TOOLS[$((n-1))]}"); done; fi
[ "${#selected[@]}" -gt 0 ] || { echo '未選擇任何工具，結束。'; exit 0; }
echo "將安裝：${selected[*]}"
[ "$DRY_RUN" = 1 ] && { echo 'DRY_RUN: 不實際安裝。'; exit 0; }
for tool in "${selected[@]}"; do "install_${tool//-/_}"; done
