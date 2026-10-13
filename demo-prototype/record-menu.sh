#!/bin/bash
# PROTOTYPE — 丟棄式。選單 GIF：借 e2e.sh 的函式建乾淨容器，但不跑 bootstrap，
# 先放好假 key 和 6 個 promptString 的值，tape 自己打 README 那行 bootstrap 指令。
#   bash demo-prototype/record-menu.sh menu.tape
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/.." && pwd)
sed -n '1,/^case "\$TARGET"/p' "$SRC/script/tests/e2e.sh" | sed '$d' > "$HERE/e2e-lib.sh"
E2E_TAG=demo-menu source "$HERE/e2e-lib.sh"
REPO=$SRC; TARGET=ubuntu; TAG=demo-menu; IMAGE="dotfiles-e2e-ubuntu:$TAG"; CTR="dotfiles-demo-menu"
if [ "${REUSE:-0}" != 1 ]; then
  setup_ubuntu
  docker exec -u root "$CTR" bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ca-certificates curl ttyd ffmpeg xz-utils fontconfig >/dev/null && curl -fsSL -o /tmp/v.deb https://github.com/charmbracelet/vhs/releases/download/v0.12.1/vhs_0.12.1_amd64.deb && apt-get install -y -qq /tmp/v.deb >/dev/null && curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq /tmp/chrome.deb fonts-noto-cjk >/dev/null' || { echo 補工具失敗; exit 1; }
  docker exec -u ubuntu "$CTR" bash -c 'mkdir -p ~/.local/share/fonts && curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Hack.tar.xz | tar -xJ -C ~/.local/share/fonts HackNerdFont-Regular.ttf HackNerdFontMono-Regular.ttf HackNerdFontMono-Bold.ttf && fc-cache -f' || exit 1
  # VHS 自己下載的 Chromium 在乾淨容器缺函式庫；主 GIF 那次是 bootstrap 的 headless-chrome 帶進來的。
  # 第 3 關：key 已存在就跳過貼上。憑證與 git 身分：promptStringOnce 讀到現值就不問，只剩選單。
  docker exec -u ubuntu "$CTR" bash -c 'mkdir -p ~/.ssh ~/.config/chezmoi && chmod 700 ~/.ssh && cp ~/e2e-fixtures/key ~/.ssh/henry5720 && cp ~/e2e-fixtures/key.pub ~/.ssh/henry5720.pub && chmod 600 ~/.ssh/henry5720 && cat > ~/.config/chezmoi/chezmoi.toml <<EOF
[data]
    codeServerPassword = "demo"
    codexLbApiKey = "demo"
    context7ApiKey = ""
    wakatimeApiKey = ""
    gitUserName = "demo"
    gitUserEmail = "demo@example.com"
EOF' || exit 1
fi
for t in "$@"; do
  docker cp "$HERE/$t" "$CTR:/tmp/$t"
  docker exec -u ubuntu -w /home/ubuntu -e LANG=C.UTF-8 -e VHS_NO_SANDBOX=1 "$CTR" bash -lc "cp /tmp/$t ~/ && vhs $t" || exit 1
  out=$(grep -m1 '^Output' "$HERE/$t" | awk '{print $2}')
  docker cp "$CTR:/home/ubuntu/$out" "$HERE/$out"
  for png in $(grep '^Screenshot' "$HERE/$t" | awk '{print $2}'); do docker cp "$CTR:/home/ubuntu/$png" "$HERE/$png"; done
done
