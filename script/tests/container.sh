# 容器 e2e 與 README 錄影共用:建 ubuntu:24.04 映像與容器、做 fixtures。
# 只定義函式,source 進來不會執行任何東西:
#   script/tests/e2e.sh   測試
#   script/demo/record.sh 錄 README 的 GIF
#
# source 之前呼叫端要設好:
#   REPO   repo 根目錄(make_fixtures 打包它的工作目錄)
#   IMAGE  映像名稱(含 tag)
#   CTR    容器名稱
# 環境變數 E2E_KEEP=1:結束時不刪容器(cleanup 讀它)。

# ===============================================================
# 輸出
# ===============================================================
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

# ===============================================================
# 收尾:trap cleanup EXIT
# ===============================================================
cleanup() {
  if [ "${E2E_KEEP:-0}" = 1 ]; then
    bold "保留容器 $CTR(E2E_KEEP=1),用完 docker rm -f $CTR"
  else
    docker rm -f "$CTR" >/dev/null 2>&1 || true
  fi
}

# ===============================================================
# fixtures
# ===============================================================
# 測試要的東西都在主機上做好再放進容器的 $FIX:容器在 chezmoi 套件腳本跑之前連 git、ssh-keygen 都沒有。
# 放在家目錄底下,因為 Termux 容器沒有 /tmp(在 Termux 裡是 $PREFIX/tmp)。
#   $FIX/dotfiles        repo 工作目錄(含未 commit、不含 .gitignore 擋掉的)commit 成的 git repo,
#                        origin 是 GitHub 的 HTTPS URL
#   $FIX/key、key.pub     假的 henry5720 key(Termux 測 authorized_keys 用)
#   $FIX/agent-config.git agent-config 的假 remote(bare repo,內容是一個 skill + 一個 MCP server + instructions/ 的 AGENTS.md)
# CTR_USER／CTR_HOME 由 setup_<目標> 設定。
make_fixtures() {
  FIX=$CTR_HOME/e2e-fixtures
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/dotfiles"
  (cd "$REPO" && git ls-files -co --exclude-standard -z \
    | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
    | tar --null -T - -cf -) | tar -C "$tmp/dotfiles" -xf -
  git -C "$tmp/dotfiles" init -q -b main
  git -C "$tmp/dotfiles" add -A
  git -C "$tmp/dotfiles" -c user.name=e2e -c user.email=e2e@example.com commit -qm e2e
  # 跟 chezmoi init henry5720 clone 下來的一樣(e2e 與錄影都把它 cp 成 chezmoi 的 source)
  git -C "$tmp/dotfiles" remote add origin https://github.com/henry5720/dotfiles.git
  ssh-keygen -q -t ed25519 -N '' -C e2e -f "$tmp/key"
  mkdir -p "$tmp/ac/skills/e2e-hello"
  printf -- '---\nname: e2e-hello\ndescription: e2e 測試用\n---\nhello\n' > "$tmp/ac/skills/e2e-hello/SKILL.md"
  printf 'servers:\n  e2e-mcp:\n    url: https://example.com/mcp\n    targets: [claude]\n' > "$tmp/ac/mcp.yaml"
  mkdir -p "$tmp/ac/instructions/agents-md"
  printf 'e2e-agents\n' > "$tmp/ac/instructions/agents-md/AGENTS.md"
  git -C "$tmp/ac" init -q -b main
  git -C "$tmp/ac" add -A
  git -C "$tmp/ac" -c user.name=e2e -c user.email=e2e@example.com commit -qm init
  git clone -q --bare "$tmp/ac" "$tmp/agent-config.git"
  rm -rf "$tmp/ac"
  # zsh_ok 的 tty 版用(兩邊都有 python3)。檔名不能叫 tty.py,會蓋掉標準庫的 tty
  cat > "$tmp/zsh-tty.py" <<'PY'
import pty, subprocess, sys
# 在 pty 裡跑指令(stdin 是終端機),stdout 丟掉,stderr 原樣印出,回傳它的 exit code
master, slave = pty.openpty()
r = subprocess.run(sys.argv[1:], stdin=slave, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, start_new_session=True)
sys.stderr.buffer.write(r.stderr)
sys.exit(r.returncode)
PY
  docker exec -u "$CTR_USER" "$CTR" mkdir -p "$FIX"
  tar -C "$tmp" -cf - . | docker exec -i -u "$CTR_USER" "$CTR" tar -C "$FIX" -xf -
  rm -rf "$tmp"
}

# ===============================================================
# 目標:ubuntu(代表 WSL、雲端主機、proot Ubuntu)
# ===============================================================
# 映像模擬一台全新的 Ubuntu:一般使用者 + sudo 免密碼,只多 curl(真的 Ubuntu 預設就有,
# README 的安裝指令要用它);沒有 git／ssh／chezmoi。chezmoi 由官方 installer 裝,
# git 等由 chezmoi 的套件腳本裝。apt 清單刪掉,所以套件腳本一定要自己 apt-get update。
setup_ubuntu() {
  CTR_USER=ubuntu  # ubuntu:24.04 內建的 uid 1000
  CTR_HOME=/home/ubuntu
  docker build -q -t "$IMAGE" - >/dev/null <<'DOCKERFILE' || { red "✗ 建映像失敗"; exit 1; }
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends sudo curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu
DOCKERFILE
  docker rm -f "$CTR" >/dev/null 2>&1 || true
  # 固定 hostname:預設是容器 ID,README 的 GIF 裡 fastfetch 標題會印出來
  docker run -d --name "$CTR" --hostname dotfiles "$IMAGE" sleep infinity >/dev/null
  make_fixtures
}
