#!/data/data/com.termux/files/usr/bin/bash
# 原生 Termux 的 xfce 桌面套件（平板用，手動跑一次）
# 系統更新、git、openssh、字型都由 bootstrap 和 chezmoi 處理，這裡只裝桌面。
# 啟動桌面：bash ~/.local/share/chezmoi/script/termux/startxfce_native.sh
set -euo pipefail

# 1. 桌面套件在 x11-repo，先開這個套件庫
pkg install -y x11-repo

# 2. 裝桌面與常用 GUI 程式
pkg install -y termux-x11-nightly xfce4 pulseaudio xfce4-terminal xfce4-taskmanager chromium code-oss

# 3. 終端機字型只能手動選（xfconf 要桌面的 dbus session 才改得到）
cat <<'MSG'

桌面套件裝好了。剩一步要手動做：
  進桌面後開 xfce4-terminal → 偏好設定（Preferences）→ 外觀（Appearance）
  → 取消「使用系統字型」→ 字型選 Hack Nerd Font
MSG
