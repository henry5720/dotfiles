#!/usr/bin/env bash
# PROTOTYPE，不會 merge。重跑「Headless 瀏覽器（a1）用哪個工具、留幾支」(#247) 的三項實測。
# 只用 9333（Chrome）、8765（測試頁）、8899（dashboard），不碰 9222。
# 工具裝在暫存目錄，不動全域的 playwright-cli。結果對照 FINDINGS.md。
set -euo pipefail

# 1. 準備：暫存目錄、工具、headless Chrome、測試頁
WORK=$(mktemp -d)
HERE=$(cd "$(dirname "$0")" && pwd)
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
(cd "$WORK" && npm init -y >/dev/null && npm i -s @playwright/cli@0.1.23 agent-browser@0.41.2 && npx playwright install ffmpeg)
P=$WORK/node_modules/.bin/playwright-cli
A=$WORK/node_modules/.bin/agent-browser
google-chrome --headless --remote-debugging-address=127.0.0.1 --remote-debugging-port=9333 \
  --user-data-dir="$WORK/profile" --no-first-run --window-size=1280,800 >"$WORK/chrome.log" 2>&1 &
mkdir -p "$WORK/site" && cp "$HERE/test-page.html" "$WORK/site/index.html"
(cd "$WORK/site" && python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1) &
sleep 3
cd "$WORK"
URL=http://127.0.0.1:8765/
state() { "$P" -s="$1" eval "navigator.language+' | '+innerWidth+'x'+innerHeight+' | cookie='+document.cookie" | grep -A1 '### Result' | tail -1; }

# 2. 實測 11：attach 的 session 是否互相隔離、吃不吃設定
echo '{"browser":{"contextOptions":{"locale":"zh-TW"}}}' >cfg.json
"$P" -s=a attach --cdp=http://127.0.0.1:9333 >/dev/null; "$P" -s=a goto $URL >/dev/null
"$P" -s=a resize 1440 900 >/dev/null; "$P" -s=a cookie-set sid AAA >/dev/null
"$P" -s=b attach --cdp=http://127.0.0.1:9333 --config="$WORK/cfg.json" >/dev/null; "$P" -s=b goto $URL >/dev/null
"$P" -s=d open --config="$WORK/cfg.json" $URL >/dev/null
echo "attach a: $(state a)"; echo "attach b: $(state b)"; echo "open d:   $(state d)"
"$P" -s=a detach >/dev/null; "$P" -s=b detach >/dev/null; "$P" -s=d close >/dev/null

# 3. 實測 8：agent-browser --pin-tab，與 snapshot 大小
other=$(curl -s -X PUT "127.0.0.1:9333/json/new?about:blank" | jq -r .id)
"$A" --session pin --cdp 9333 --pin-tab open $URL >/dev/null
curl -s "127.0.0.1:9333/json/activate/$other" >/dev/null
"$A" --session pin --cdp 9333 --pin-tab click '#b' >/dev/null
echo "pin-tab: $("$A" --session pin --cdp 9333 --pin-tab eval "location.href+' '+document.getElementById('b').textContent")"
for u in https://news.ycombinator.com/ https://playwright.dev/docs/intro; do
  "$A" --session pin --cdp 9333 --pin-tab open "$u" >/dev/null; sleep 2
  "$P" -s=s open "$u" >/dev/null; sleep 2; "$P" -s=s snapshot --filename="$WORK/pw.yml" >/dev/null
  echo "$u agent-browser=$("$A" --session pin --cdp 9333 --pin-tab snapshot | wc -c)B -i=$("$A" --session pin --cdp 9333 --pin-tab snapshot -i | wc -c)B playwright-cli=$(wc -c <"$WORK/pw.yml")B"
done
"$P" -s=s close >/dev/null
echo "daemon port: $(ss -ltnp | grep agent-browser | awk '{print $4}' | head -1)"
"$A" close --all >/dev/null

# 4. 實測 3：show dashboard 能否點擊、打字（座標對應 1600x1000 視窗、目標頁 1280x720）
"$P" -s=tgt open $URL >/dev/null
"$P" show --port 8899 >/dev/null 2>&1 &
sleep 3
"$P" -s=viewer open http://127.0.0.1:8899/ >/dev/null; "$P" -s=viewer resize 1600 1000 >/dev/null; sleep 2
"$P" -s=viewer click "getByRole('option',{name:/proto/})" >/dev/null
"$P" -s=viewer click "getByRole('button',{name:'Enable interactive mode'})" >/dev/null; sleep 1
for xy in "373 309" "498 309"; do "$P" -s=viewer mousemove $xy >/dev/null; "$P" -s=viewer mousedown >/dev/null; "$P" -s=viewer mouseup >/dev/null; sleep 1; done
for k in h i 1; do "$P" -s=viewer press $k >/dev/null; done; sleep 1
echo "dashboard: $("$P" -s=tgt eval "document.getElementById('b').textContent+' | input='+document.getElementById('i').value" | grep -A1 Result | tail -1)"
"$P" close-all >/dev/null; "$P" show --kill >/dev/null 2>&1 || true
