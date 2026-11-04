#!/usr/bin/env bash
# PROTOTYPE，不會 merge。實測 b：a1（ec2 headless）經 client 的反向 SOCKS 出去，對外 IP 是不是 client 的。
# 在 ec2 跑。人那邊要先開 ssh -N -R 127.0.0.1:1080 company-ec2（-R 只給 port = 反向 SOCKS，OpenSSH 7.6+）。
# 用法：PWCLI=<playwright-cli 路徑> bash b-socks.sh
set -u
PWCLI=${PWCLI:-playwright-cli}
S=a1socks
ip() { "$PWCLI" -s=$S eval "document.body.innerText.trim()" 2>&1 | grep -oE '[0-9]+(\.[0-9]+){3}|[0-9a-f]*:[0-9a-f:]+' | head -1; }  # Chrome 的 SOCKS5 在遠端解析 DNS，常走 IPv6

# 1. 沒 proxy：ec2 自己的 IP
"$PWCLI" -s=$S open https://ifconfig.me/ip >/dev/null 2>&1
echo "== 直連 IP：$(ip)"; "$PWCLI" -s=$S close >/dev/null 2>&1

# 2. 經 client：IP 應該是 client 的家用／公司 IP
PLAYWRIGHT_MCP_PROXY_SERVER=socks5://127.0.0.1:1080 "$PWCLI" -s=$S open https://ifconfig.me/ip >/dev/null 2>&1
echo "== 經 SOCKS IP：$(ip)"

# 3. YouTube：觀看頁 playabilityStatus（被擋時是 LOGIN_REQUIRED／「confirm you're not a bot」）
"$PWCLI" -s=$S goto 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' >/dev/null 2>&1
echo "== YouTube：$("$PWCLI" -s=$S eval "ytInitialPlayerResponse?.playabilityStatus?.status" 2>&1 | tail -1)"
"$PWCLI" -s=$S close >/dev/null 2>&1
