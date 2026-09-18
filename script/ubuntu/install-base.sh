#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
DRY_RUN="${DRY_RUN:-0}"

ZSH_PLUGINS_DIR="$HOME/.config/zsh"

echo -e "${BLUE}🚀 安裝基底環境 (zsh + 插件 + chezmoi)...${NC}"
[ "$DRY_RUN" = 1 ] && { echo 'DRY_RUN: 不實際安裝。'; exit 0; }

# 1. apt 基底套件
echo -e "${GREEN}📦 更新系統並安裝 zsh/git/curl/vim/build-essential...${NC}"
sudo apt update && sudo apt upgrade -y
sudo apt install -y zsh git curl vim build-essential

# 2. chezmoi(dotfile 部署工具)
# 檢查兩處:apt 沒有 chezmoi,snap 版落在 /snap/bin,而 Ubuntu 的 /etc/zsh/zprofile
# 不 source /etc/profile,所以 zsh 底下 /snap/bin 可能還不在 PATH 裡,只靠
# command -v 會誤判成沒裝而重裝一次。
if command -v chezmoi &>/dev/null || [ -x /snap/bin/chezmoi ]; then
  echo -e "${BLUE}✅ chezmoi 已安裝,跳過。${NC}"
else
  echo -e "${GREEN}📦 安裝 chezmoi (snap,上游作者自己發布)...${NC}"
  sudo snap install chezmoi --classic
fi

# 3. clone 三個 zsh 插件(冪等)
mkdir -p "$ZSH_PLUGINS_DIR"
clone_if_missing() {  # $1=目錄名 $2=git url
  if [ ! -d "$ZSH_PLUGINS_DIR/$1" ]; then
    echo -e "${GREEN}🔌 下載 $1...${NC}"
    git clone --depth=1 "$2" "$ZSH_PLUGINS_DIR/$1"
  else
    echo -e "${BLUE}✅ $1 已存在,跳過。${NC}"
  fi
}
clone_if_missing powerlevel10k        https://github.com/romkatv/powerlevel10k.git
clone_if_missing zsh-autosuggestions  https://github.com/zsh-users/zsh-autosuggestions
clone_if_missing zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git

# 4. 設預設 shell 為 zsh
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(which zsh)" ]; then
  echo -e "${GREEN}🔄 切換預設 Shell 為 zsh...${NC}"
  sudo chsh -s "$(which zsh)" "$USER"
else
  echo -e "${BLUE}✅ 預設 Shell 已是 zsh,跳過。${NC}"
fi

echo -e "${GREEN}🎉 基底環境安裝完成。${NC}"
