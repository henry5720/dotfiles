#!/bin/bash
# 重錄 README 的兩支 GIF:docs/demo/menu.gif(安裝選單)、docs/demo/main.gif(裝完的 terminal)。
#
# 用法:
#   bash script/demo/record.sh
#
# 環境變數(跟 script/tests/e2e.sh 同一組):
#   E2E_TAG=<字串>   容器名與映像 tag 的後綴(預設 local)
#   E2E_KEEP=1       錄完不刪容器,錄壞時 `docker exec -it -u ubuntu <容器> bash` 進去看
#
# 在全新的 ubuntu:24.04 容器裡錄,不碰本機家目錄;錄的是 repo 工作目錄(含未 commit 的修改)。
# 建容器與 fixtures(本機 repo、假 agent-config remote)跟 e2e 共用 script/tests/container.sh。
# 一次約 5 分鐘以上,大半是等 apply 裝完。
# 劇本在同目錄的 menu.tape、main.tape;fastfetch.jsonc 只用在錄影容器。
set -uo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
DEMO=$REPO/script/demo
OUT=$REPO/docs/demo
TAG=${E2E_TAG:-local}
IMAGE="dotfiles-e2e-ubuntu:$TAG"
CTR="dotfiles-demo-$TAG"
MAX_BYTES=$((1024 * 1024))
. "$REPO/script/tests/container.sh"

fail() { red "✗ $*"; exit 1; }

# 錄影的環境變數:VHS 在容器裡要關 sandbox;LANG 讓中文正常顯示;
# NPM_CONFIG_UPDATE_NOTIFIER 拿掉選單 GIF 結尾 npm 的新版本提示。
vhs_run() {  # vhs_run <tape>
  bold "▶ 錄 $1"
  docker exec -u "$CTR_USER" -w "$CTR_HOME/demo" \
    -e LANG=C.UTF-8 -e VHS_NO_SANDBOX=1 -e NPM_CONFIG_UPDATE_NOTIFIER=false \
    "$CTR" bash -lc "vhs $1" || fail "vhs $1 失敗"
}

trap cleanup EXIT
bold "== 錄 README demo(容器 $CTR)"

# 1. 全新容器 + fixtures(跟 e2e 同一份)
setup_ubuntu

# 2. 錄影工具:vhs 0.12.1、ttyd、ffmpeg。
#    VHS 自己下載的 Chromium 在乾淨容器缺函式庫,改裝 Google Chrome;fonts-noto-cjk 給中文。
bold "▶ 裝錄影工具"
docker exec -u root "$CTR" bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends ca-certificates curl ttyd ffmpeg xz-utils fontconfig >/dev/null
  curl -fsSL -o /tmp/vhs.deb https://github.com/charmbracelet/vhs/releases/download/v0.12.1/vhs_0.12.1_amd64.deb
  curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt-get install -y -qq /tmp/vhs.deb /tmp/chrome.deb fonts-noto-cjk >/dev/null
' || fail "裝錄影工具失敗"

# 3. Hack Nerd Font:Linux 的 chezmoi 不裝 Nerd Font,p10k 和 eza 的 icon 要它
bold "▶ 裝 Hack Nerd Font"
docker exec -u "$CTR_USER" "$CTR" bash -c '
  set -e
  mkdir -p ~/.local/share/fonts
  curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Hack.tar.xz \
    | tar -xJ -C ~/.local/share/fonts HackNerdFont-Regular.ttf HackNerdFontMono-Regular.ttf HackNerdFontMono-Bold.ttf
  fc-cache -f
' || fail "裝字型失敗"

# 4. 讓 init 在選單之前都不用問人:promptStringOnce 讀到現值就不問,只剩選單
bold "▶ 放憑證假值"
docker exec -u "$CTR_USER" "$CTR" bash -c "
  set -e
  mkdir -p ~/.config/chezmoi
  cat > ~/.config/chezmoi/chezmoi.toml <<'EOF'
[data]
    codeServerPassword = \"demo\"
    codexLbApiKey = \"demo\"
    context7ApiKey = \"\"
    wakatimeApiKey = \"\"
    gitUserName = \"demo\"
    gitUserEmail = \"demo@example.com\"
EOF
" || fail "放假值失敗"

# 5. 劇本放進容器(tar 帶進去,檔案屬於容器裡的使用者)
docker exec -u "$CTR_USER" "$CTR" mkdir -p "$CTR_HOME/demo"
tar -C "$DEMO" -cf - menu.tape main.tape fastfetch.jsonc \
  | docker exec -i -u "$CTR_USER" "$CTR" tar -C "$CTR_HOME/demo" -xf - || fail "放劇本失敗"

# 6. 選單 GIF:tape 自己在有 TTY 的終端機跑 README 的 Ubuntu 那行,裝完才結束
vhs_run menu.tape

# 7. 主 GIF:同一台裝好的機器,fastfetch 換成錄影專用設定(不印容器 ID、ttyd、主機資訊)
docker exec -u "$CTR_USER" "$CTR" install -D -m 644 "$CTR_HOME/demo/fastfetch.jsonc" "$CTR_HOME/.config/fastfetch/config.jsonc" \
  || fail "放 fastfetch 設定失敗"
vhs_run main.tape

# 8. 拷回 repo;超過 1 MB 只警告(錄一次要好幾分鐘,擋下就白錄了)
mkdir -p "$OUT"
for g in menu.gif main.gif; do
  docker cp "$CTR:$CTR_HOME/demo/$g" "$OUT/$g" >/dev/null || fail "拷回 $g 失敗"
  size=$(stat -c %s "$OUT/$g")
  if [ "$size" -gt "$MAX_BYTES" ]; then
    red "⚠ docs/demo/$g 有 $((size / 1024)) KB,超過 1 MB;檔案照樣寫出,要不要 commit 自己決定"
  else
    green "  ✓ docs/demo/$g($((size / 1024)) KB)"
  fi
done
green "== 完成"
