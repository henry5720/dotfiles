#!/bin/bash
# PROTOTYPE — 丟棄式。借 e2e.sh 的函式建容器、跑到 init --apply，補錄影工具後跑 tape。
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HOME/.local/share/chezmoi
sed -n '1,/^case "\$TARGET"/p' "$SRC/script/tests/e2e.sh" | sed '$d' > "$HERE/e2e-lib.sh"
E2E_TAG=demo-proto source "$HERE/e2e-lib.sh"
REPO=$SRC; TARGET=ubuntu; TAG=demo-proto; IMAGE="dotfiles-e2e-ubuntu:$TAG"; CTR="dotfiles-demo-proto"
if [ "${REUSE:-0}" != 1 ]; then
  setup_ubuntu
  step "bootstrap 到 init --apply" "$(bootstrap '~/e2e-init.log' "$FIX/key" --no-tty "${INIT_FLAGS[@]}" --promptMultichoice "$TOOLS_PROMPT=$TOOLS_FIRST")"
  docker exec -u root "$CTR" bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ttyd ffmpeg xz-utils fontconfig >/dev/null && curl -fsSL -o /tmp/v.deb https://github.com/charmbracelet/vhs/releases/download/v0.12.1/vhs_0.12.1_amd64.deb && apt-get install -y -qq /tmp/v.deb >/dev/null' || { echo 補工具失敗; exit 1; }
  docker exec -u ubuntu "$CTR" bash -c 'mkdir -p ~/.local/share/fonts && curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Hack.tar.xz | tar -xJ -C ~/.local/share/fonts HackNerdFont-Regular.ttf HackNerdFontMono-Regular.ttf HackNerdFontMono-Bold.ttf && fc-cache -f' || exit 1
  docker cp "$HERE/fastfetch.jsonc" "$CTR:/tmp/ff.jsonc"
  docker exec -u root "$CTR" bash -c 'install -D -o ubuntu -g ubuntu /tmp/ff.jsonc /home/ubuntu/.config/fastfetch/config.jsonc'
fi
for t in "$@"; do
  docker cp "$HERE/$t" "$CTR:/tmp/$t"
  docker exec -u ubuntu -w /home/ubuntu -e LANG=C.UTF-8 -e VHS_NO_SANDBOX=1 "$CTR" bash -lc "cp /tmp/$t ~/ && vhs $t" || exit 1
  out=$(grep -m1 '^Output' "$HERE/$t" | awk '{print $2}')
  docker cp "$CTR:/home/ubuntu/$out" "$HERE/$out"
done
