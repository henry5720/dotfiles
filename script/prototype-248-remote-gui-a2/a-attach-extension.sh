#!/usr/bin/env bash
# PROTOTYPE，不會 merge。實測 a：ec2 上的 playwright-cli attach --extension 接 Windows 日常 Chrome。
# 在 ec2 跑。人那邊要先開 ssh -N -L 9555:127.0.0.1:9555 company-ec2（見 FINDINGS.md）。
# 用法：PWCLI=<playwright-cli 路徑> [PLAYWRIGHT_MCP_EXTENSION_TOKEN=...] bash a-attach-extension.sh
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$DIR/out}; export OUT
PWCLI=${PWCLI:-playwright-cli}
S=a2ext
mkdir -p "$OUT"; rm -f "$OUT/connect-url.txt"

# 1. attach：relay 起來後 shim 寫出 connect 網址，等人在 Windows Chrome 打開（給 5 分鐘）
PLAYWRIGHT_MCP_EXECUTABLE_PATH=$DIR/shim.sh PWTEST_EXTENSION_CONNECT_TIMEOUT=300000 \
  "$PWCLI" -s=$S attach --extension=chrome >"$OUT/attach.log" 2>&1 &
pid=$!
for _ in $(seq 30); do [ -s "$OUT/connect-url.txt" ] && break; sleep 1; done
echo "== 把這個網址貼到 Windows Chrome 的網址列："
cat "$OUT/connect-url.txt" 2>/dev/null || { echo "shim 沒寫出網址"; cat "$OUT/attach.log"; exit 1; }
wait $pid; echo "== attach exit $?"; cat "$OUT/attach.log"

# 2. 能做什麼：分頁、操作、日常登入狀態、snapshot 大小、截圖
run() { echo "== $*"; "$PWCLI" -s=$S "$@" 2>&1 | head -40; }
run tab-list
run goto https://github.com/
run eval "document.querySelector('meta[name=user-login]')?.content || '(沒登入)'"
run snapshot --filename="$OUT/github.yml"; wc -c "$OUT/github.yml"
run screenshot --filename="$OUT/github.png"
run goto https://news.ycombinator.com/
run snapshot --filename="$OUT/hn.yml"; wc -c "$OUT/hn.yml"
run tab-list

# 3. 收：detach 後 Chrome 應該留著
run detach
kill "$(cat "$OUT/fwd.pid")" 2>/dev/null || true
