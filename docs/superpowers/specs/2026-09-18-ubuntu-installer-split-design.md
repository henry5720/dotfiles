# Ubuntu 安裝腳本拆分與選單設計

## 目標

將 Ubuntu 安裝入口改成可選擇執行哪些腳本，並把 AI 工具與一般工具分開；本輪一般工具新增 Tailscale 與 WakaTime zsh terminal tracking。

## 決定

- `setup.sh` 顯示腳本多選單，可選 `install-base.sh`、`install-tools.sh`、`install-tools-ai.sh`。
- 直接按 Enter 不執行任何腳本，避免新機器誤裝所有工具。
- `install-tools.sh` 管理 fastfetch、btop、nvm、code-server、Tailscale、WakaTime。
- `install-tools-ai.sh` 管理 Claude Code、Codex、OpenCode、文件／影音依賴與 AI 文件／影音 Python venv。
- `install-docker.sh` 與 `setup-swap.sh` 保持獨立手動腳本，不列入 setup 選單；前者會移除衝突套件，後者會修改 WSL／系統 swap 設定。
- Tailscale 只安裝 daemon，不執行 `tailscale up`；登入與加入 tailnet 由使用者手動完成。
- WakaTime 安裝 CLI 並啟用 `sobolevn/wakatime-zsh-plugin`；API key 由 chezmoi secret template 管理，不放進 repo、`.zshrc` 或環境變數。
- `~/.wakatime.cfg` 只在 API key 非空時由 chezmoi 產生，權限為 600；空 key 時不啟用設定。

## 安裝行為

### setup.sh

使用 `INPUT_SRC` 支援非互動測試，顯示三個腳本選項。輸入空白分隔的編號後，依固定順序執行選中的腳本；無效編號忽略。直接 Enter 顯示未選擇並結束。

### install-tools.sh

保留原有冪等選單與 `DRY_RUN`，新增：

- Tailscale：`curl -fsSL https://tailscale.com/install.sh | sh`；若 systemd 可用則啟用 `tailscaled`，否則只完成安裝並提示 WSL systemd 前置條件；不執行登入。
- WakaTime：下載官方 `wakatime-cli` release 到 `~/.local/bin/wakatime-cli`，依架構選 linux-amd64 或 linux-arm64；clone zsh plugin 到 `~/.config/zsh/wakatime-zsh-plugin`，並由 chezmoi 管理的 `.zshrc` 載入。

### chezmoi WakaTime secret

在 `home/.chezmoi.toml.tmpl` 增加可留空的 `promptStringOnce` 欄位。新增 `home/dot_wakatime.cfg.tmpl`，空 key 時不輸出有效設定；非空時輸出 `[settings]` 與 `api_key`。模板不應覆蓋使用者既有額外設定，因此安裝腳本只負責安裝 CLI/plugin，設定檔由 chezmoi 部署。

## 相容性與限制

- WakaTime zsh plugin 是第三方 repository；`.zshrc` 只有在 plugin 檔案存在時才 source，缺少時不阻塞 shell 啟動。
- Tailscale 在 WSL2 未啟用 systemd 時不能假設 daemon 能由 systemctl 啟動；腳本必須明確提示，而不是讓 `systemctl` 失敗中止整個安裝。
- 不在安裝腳本中保存或輸出 API key、Tailscale auth key。
- `install-tools-ai.sh` 的既有 AI 文件媒體環境變數名稱保持不變。

## 驗證

- `bash -n script/ubuntu/*.sh`
- setup 選單的 `DRY_RUN=1`／`INPUT_SRC` 測試：空輸入不執行、可選多個腳本、無效編號忽略。
- tools 選單的 `DRY_RUN=1`／`INPUT_SRC` 測試：Tailscale 與 WakaTime 可獨立選取。
- `python3 -m unittest script/tests/test_ai_profile.py`
- `chezmoi --no-tty execute-template --init < home/.chezmoi.toml.tmpl`
- `chezmoi verify`
