#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
DRY_RUN="${DRY_RUN:-0}"
INPUT_SRC="${INPUT_SRC:-/dev/tty}"   # 正式走 tty;測試可覆寫為 /dev/stdin

# 工具清單:編號順序即顯示順序
TOOLS=(fastfetch btop nvm code-server document-media ai-document-media codex opencode)
TOOL_LABELS=(fastfetch btop nvm code-server '文件／媒體解析' 'AI 文件／媒體解析' 'codex CLI' 'opencode')

install_fastfetch() {
  command -v fastfetch &>/dev/null && { echo -e "${BLUE}✅ fastfetch 已安裝。${NC}"; return; }
  echo -e "${GREEN}📦 安裝 fastfetch (GitHub .deb)...${NC}"
  local dpkg_arch asset url deb
  # 檔名用 aarch64/armv7l,包裡的 Architecture 卻是 arm64/armhf,兩套名字要對照
  dpkg_arch=$(dpkg --print-architecture)
  case "$dpkg_arch" in
    amd64) asset=amd64 ;;
    arm64) asset=aarch64 ;;
    armhf) asset=armv7l ;;
    *)
      echo -e "${BLUE}⚠️ fastfetch 沒有 ${dpkg_arch} 的 .deb,跳過。${NC}"
      return 0
      ;;
  esac
  # 結尾釘死 \.deb,否則會抓到同名的 -polyfilled 變體
  url=$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
        | grep -o "https://[^\"]*/fastfetch-linux-${asset}\\.deb" | head -1)
  if [ -z "$url" ]; then
    echo -e "${BLUE}⚠️ 找不到 fastfetch 的 .deb 連結(GitHub API 限流或資產改名?),跳過。${NC}"
    return 0
  fi
  deb=$(mktemp --suffix=.deb)
  curl -fsSL "$url" -o "$deb"
  sudo dpkg -i "$deb" || sudo apt install -f -y
  rm -f "$deb"
  # apt install -f 只補得了缺依賴,架構不符照樣回 0,所以要自己確認真的裝上了
  command -v fastfetch &>/dev/null || {
    echo -e "${BLUE}⚠️ fastfetch 安裝失敗。${NC}" >&2
    return 1
  }
}

install_btop() {
  command -v btop &>/dev/null && { echo -e "${BLUE}✅ btop 已安裝。${NC}"; return; }
  echo -e "${GREEN}📦 安裝 btop (apt)...${NC}"
  sudo apt update
  sudo apt install -y btop
}

install_nvm() {
  [ -d "$HOME/.nvm" ] && { echo -e "${BLUE}✅ nvm 已安裝。${NC}"; return; }
  echo -e "${GREEN}📦 安裝 nvm 與 Node.js LTS...${NC}"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  nvm install --lts
}

install_code_server() {
  if command -v code-server &>/dev/null; then
    echo -e "${BLUE}✅ code-server 已安裝。${NC}"
  else
    echo -e "${GREEN}📦 安裝 code-server (官方安裝腳本)...${NC}"
    curl -fsSL https://code-server.dev/install.sh | sh
  fi

  cat <<'EOF'

  設定檔由 chezmoi 部署(~/.config/code-server/config.yaml),密碼在
  `chezmoi init` 時會問一次;要改密碼用 `chezmoi edit-config` 改完
  再 `chezmoi apply`。
  啟動:systemctl --user enable --now code-server   (預設只綁 127.0.0.1:8080)
  從別台連進來的五種做法:docs/code-server-remote.md
EOF
}

install_document_media() {
  local packages=(ffmpeg mupdf-tools pandoc python3-venv)
  local missing=()
  local package

  for package in "${packages[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
      missing+=("$package")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    echo -e "${BLUE}✅ 文件／媒體解析依賴(ffmpeg、MuPDF、Pandoc、Python venv)已安裝。${NC}"
    return
  fi

  echo -e "${GREEN}📦 安裝文件／媒體解析依賴 (apt): ${missing[*]}...${NC}"
  sudo apt update
  sudo apt install -y "${missing[@]}"
}

install_ai_document_media() {
  local backend="${AI_DOCUMENT_MEDIA_BACKEND:-venv}"
  local data_dir="${AI_DOCUMENT_MEDIA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ai-document-media}"
  local venv_dir="${AI_DOCUMENT_MEDIA_VENV:-$data_dir/venv}"
  local python
  local packages=()
  local tika_label=''

  case "$backend" in
    venv)
      command -v python3 &>/dev/null || {
        echo -e "${BLUE}⚠️ 找不到 python3;請先安裝 Ubuntu Python。${NC}" >&2
        return 1
      }
      if ! python3 -c 'import venv' &>/dev/null; then
        echo -e "${GREEN}📦 安裝 Python venv 支援 (apt)...${NC}"
        sudo apt update
        sudo apt install -y python3-venv
      fi
      if [ ! -x "$venv_dir/bin/python" ]; then
        echo -e "${GREEN}📦 建立 AI 文件／媒體解析 Python venv: $venv_dir${NC}"
        mkdir -p "$data_dir"
        python3 -m venv "$venv_dir"
      fi
      python="$venv_dir/bin/python"
      ;;
    uv)
      command -v uv &>/dev/null || {
        echo -e "${BLUE}⚠️ AI_DOCUMENT_MEDIA_BACKEND=uv 但找不到 uv;請先自行安裝 uv。${NC}" >&2
        return 1
      }
      if [ ! -x "$venv_dir/bin/python" ]; then
        echo -e "${GREEN}📦 用 uv 建立 AI 文件／媒體解析 venv: $venv_dir${NC}"
        mkdir -p "$data_dir"
        uv venv --python python3 "$venv_dir"
      fi
      python="$venv_dir/bin/python"
      ;;
    *)
      echo -e "${BLUE}⚠️ AI_DOCUMENT_MEDIA_BACKEND 只能是 venv 或 uv。${NC}" >&2
      return 1
      ;;
  esac

  "$python" -c 'import docling' &>/dev/null || packages+=(docling)
  "$python" -c 'import faster_whisper' &>/dev/null || packages+=(faster-whisper)
  if [ "${AI_DOCUMENT_MEDIA_INSTALL_TIKA:-0}" = "1" ]; then
    "$python" -c 'import tika' &>/dev/null || packages+=(tika)
    tika_label='、可選 Tika'
  fi

  if [ "${#packages[@]}" -eq 0 ]; then
    echo -e "${BLUE}✅ AI 文件／媒體解析 Python 套件已安裝。${NC}"
  elif [ "$backend" = "uv" ]; then
    echo -e "${GREEN}📦 用 uv 安裝 Python 套件: ${packages[*]}...${NC}"
    uv pip install --python "$python" "${packages[@]}"
  else
    echo -e "${GREEN}📦 用 venv 安裝 Python 套件: ${packages[*]}...${NC}"
    "$python" -m pip install "${packages[@]}"
  fi

  cat <<EOF

  AI 解析環境: $venv_dir
  已管理: Docling、faster-whisper${tika_label}
  安裝器不會下載或初始化任何 AI model。首次使用前，請自行準備本機 model 並以本機路徑指定;
  未準備 model 時，skill 應回報 blocker，不得讓工具連網下載。
EOF
}

install_codex() {
  command -v codex &>/dev/null && { echo -e "${BLUE}✅ codex 已安裝。${NC}"; return; }
  # codex 是 npm global,沒有 npm 就先去裝 nvm(本選單第 3 項)
  command -v npm &>/dev/null || {
    echo -e "${BLUE}⚠️ 找不到 npm;先選第 3 項裝 nvm 再回來。${NC}" >&2
    return 1
  }
  echo -e "${GREEN}📦 安裝 codex (npm -g @openai/codex)...${NC}"
  npm install -g @openai/codex

  cat <<'EOF'

  設定由 chezmoi 部署,預設走公司的 codex-lb(~/.codex/config.toml)。
  那兩份 config 是 modify_ 腳本:repo 只管 provider 那段,codex 自己寫的
  [projects] / [tui...] 原封留著,所以 chezmoi diff 不會被它弄髒。
  個人帳號要另外登入:codex login   (寫 ~/.codex/auth.json,不由 chezmoi 管)
  profile:codex -p codex-gcp(xhigh) / codex -p personal(個人額度)
EOF
}

install_opencode() {
  command -v opencode &>/dev/null && { echo -e "${BLUE}✅ opencode 已安裝。${NC}"; return; }
  echo -e "${GREEN}📦 安裝 opencode (官方腳本 → ~/.opencode/bin)...${NC}"
  # --no-modify-path 一定要帶:官方腳本預設會往 ~/.zshrc 追加 PATH,
  # 而 ~/.zshrc 是 chezmoi 納管的,被改了下次 apply 會蓋回去、中間還多一段 diff。
  # PATH 已經寫在 home/dot_zshrc 裡了。
  curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path

  cat <<'EOF'

  設定由 chezmoi 部署(~/.config/opencode/opencode.json,公司 lb 的 provider
  與 API key;key 在 chezmoi init 時會問一次)。
  agent 分工走 oh-my-opencode-slim plugin,preset 在
  ~/.config/opencode/oh-my-opencode-slim.json,TUI 裡用 /preset 可即時切換。
EOF
}

# 顯示選單並讀取選擇
echo "請選擇要安裝的工具 (空格分隔多選,直接 Enter = 全裝):"
for i in "${!TOOLS[@]}"; do
  printf "  %d) %s\n" "$((i+1))" "${TOOL_LABELS[$i]}"
done
printf "> "
picks=()
read -a picks <"$INPUT_SRC" || true   # EOF/空輸入不因 set -e 中止

# 決定要裝的清單
selected=()
if [ "${#picks[@]}" -eq 0 ]; then
  selected=("${TOOLS[@]}")                 # Enter = 全裝
else
  for n in "${picks[@]}"; do
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#TOOLS[@]}" ]; then
      selected+=("${TOOLS[$((n-1))]}")     # 有效編號
    fi                                      # 無效編號忽略
  done
fi

if [ "${#selected[@]}" -eq 0 ]; then
  echo -e "${BLUE}未選擇任何工具,結束。${NC}"; exit 0
fi

echo -e "${GREEN}將安裝:${selected[*]}${NC}"
if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN: 不實際安裝。"; exit 0
fi

for tool in "${selected[@]}"; do
  "install_${tool//-/_}"     # code-server → install_code_server
done
echo -e "${GREEN}🎉 工具安裝完成。${NC}"
