#!/bin/bash
set -euo pipefail

# 用途:在雲端主機 / 純 Linux server 安裝 Docker Engine(官方 apt repo)。
# 這是 native Engine,非 Docker Desktop。請「手動」執行,不交給 chezmoi(會移除衝突套件、改系統設定)。
# 參考:https://docs.docker.com/engine/install/ubuntu/

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'

# WSL 提醒:WSL 慣用做法是 Docker Desktop + WSL integration,而非 native Engine
if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
  echo -e "${YELLOW}⚠️ 偵測到 WSL 環境。WSL 建議改用 Docker Desktop + WSL integration,"
  echo -e "   而非這裡的 native Engine。若確定要繼續,請按 Enter;否則 Ctrl-C 中止。${NC}"
  read -r _ </dev/tty || true
fi

if command -v docker &>/dev/null; then
  echo -e "${BLUE}✅ docker 已安裝($(docker --version)),結束。${NC}"; exit 0
fi

echo -e "${GREEN}📦 安裝 Docker Engine (官方 apt repo)...${NC}"

# 1. 移除可能衝突的舊套件(未安裝也不影響)
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt remove -y "$pkg" 2>/dev/null || true
done

# 2. 加入 Docker 官方 GPG key
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 3. 加入 apt 套件來源(deb822 格式,Suites/Architectures 依系統自動帶入)
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# 4. 安裝 Docker Engine 與外掛(buildx / compose)
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. 免 sudo:將目前使用者加入 docker 群組(需重新登入或 newgrp docker 後生效)
sudo usermod -aG docker "$USER"

echo -e "${GREEN}🎉 Docker 安裝完成。${NC}"
echo -e "${BLUE}ℹ️ 已將 $USER 加入 docker 群組,重新登入(或執行 newgrp docker)後即可免 sudo 使用。${NC}"
echo -e "${BLUE}   驗證:docker run hello-world${NC}"
