#!/usr/bin/env bash
# PROTOTYPE，不會 merge。假的「瀏覽器執行檔」，給 PLAYWRIGHT_MCP_EXECUTABLE_PATH 用。
# playwright-cli attach --extension 會 spawn「瀏覽器 connect.html 網址」；ec2 沒有那個瀏覽器，
# 所以這裡不開瀏覽器，只做兩件事：
# 1. 把 relay 的隨機 port 轉到固定的 $FIXED_PORT，人那邊的 ssh -L 才能寫死
# 2. 把改過 port 的 connect 網址寫到 $OUT/connect-url.txt，讓人貼到 Windows Chrome
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$DIR/out}
FIXED_PORT=${FIXED_PORT:-9555}
mkdir -p "$OUT"
url=${!#}

read -r relay_port new_url < <(python3 -I - "$url" "$FIXED_PORT" <<'EOF'
import sys, urllib.parse as u
url, fixed = sys.argv[1], sys.argv[2]
p = u.urlsplit(url); q = dict(u.parse_qsl(p.query))
r = u.urlsplit(q['mcpRelayUrl'])
q['mcpRelayUrl'] = r._replace(netloc=f'127.0.0.1:{fixed}').geturl()
print(r.port, p._replace(query=u.urlencode(q)).geturl())
EOF
)

[ -f "$OUT/fwd.pid" ] && kill "$(cat "$OUT/fwd.pid")" 2>/dev/null || true
nohup node "$DIR/fwd.mjs" "$FIXED_PORT" "$relay_port" >"$OUT/fwd.log" 2>&1 &
echo $! >"$OUT/fwd.pid"
printf '%s\n' "$new_url" >"$OUT/connect-url.txt"
