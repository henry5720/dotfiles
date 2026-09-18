# Ubuntu 安裝腳本拆分與選單 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 Ubuntu setup 改成腳本多選入口，拆出 AI 安裝流程，並在一般工具加入 Tailscale 與 WakaTime zsh tracking。

**Architecture:** `setup.sh` 只負責選擇並依序呼叫安裝腳本。`install-tools.sh` 管理一般工具、Tailscale 與 WakaTime；`install-tools-ai.sh` 管理 AI CLI 與文件／影音解析。WakaTime secret 由 chezmoi template 部署，安裝腳本不接觸 secret 值。

**Tech Stack:** Bash、Ubuntu apt、官方 curl installers、chezmoi Go template、zsh。

## Global Constraints

- 直接執行 `setup.sh` 時 Enter 不得自動執行所有腳本。
- `install-docker.sh` 與 `setup-swap.sh` 不列入 setup 選單。
- Tailscale 安裝與 `tailscale up` 登入必須分離。
- WakaTime API key 不得進 git、`.zshrc` 或環境變數；空值不得產生有效設定。
- 保留既有 `DRY_RUN`、`INPUT_SRC` 與 AI 文件媒體環境變數名稱。

---

### Task 1: 拆出 AI 工具安裝腳本

**Files:**
- Create: `script/ubuntu/install-tools-ai.sh`
- Modify: `script/ubuntu/install-tools.sh`

- [ ] **Step 1: 將 AI 相關函式與選單移到新腳本**

移動 Codex、OpenCode、文件／影音與 AI 文件／影音函式，保留既有冪等判斷、`DRY_RUN`、`INPUT_SRC` 與 `AI_DOCUMENT_MEDIA_*` 介面；Codex 改用官方 installer，新增 Claude Code。

- [ ] **Step 2: 保留一般工具選單並加入 Tailscale、WakaTime placeholder**

讓 `install-tools.sh` 只列 fastfetch、btop、nvm、code-server、tailscale、wakatime；新增的安裝函式在 Task 2 完成。

- [ ] **Step 3: 執行 shell 語法檢查**

Run: `bash -n script/ubuntu/install-tools.sh script/ubuntu/install-tools-ai.sh`
Expected: exit code 0。

### Task 2: 加入 Tailscale 與 WakaTime 安裝

**Files:**
- Modify: `script/ubuntu/install-tools.sh`
- Modify: `home/dot_zshrc`
- Modify: `home/dot_wakatime.cfg.tmpl`
- Modify: `home/.chezmoi.toml.tmpl`

- [ ] **Step 1: 建立 WakaTime optional secret template**

新增可留空的 `promptStringOnce`；template 只有在 key 非空時輸出 `[settings]`／`api_key`，並保持目標檔案 private。

- [ ] **Step 2: 加入 Tailscale 安裝函式**

使用 `curl -fsSL https://tailscale.com/install.sh | sh`；只在 PID 1 為 systemd 時操作 `systemctl enable --now tailscaled`，否則顯示 WSL systemd 提示；絕不呼叫 `tailscale up`。

- [ ] **Step 3: 加入 WakaTime CLI 與 zsh plugin 安裝函式**

依 `dpkg --print-architecture` 下載官方 release 的 amd64/arm64 zip 到 `~/.local/bin/wakatime-cli`，clone `sobolevn/wakatime-zsh-plugin` 到 `~/.config/zsh/wakatime-zsh-plugin`；更新 `.zshrc` 的存在檢查 source 區塊以載入 plugin。

- [ ] **Step 4: 檢查重跑與 dry-run**

Run: `printf '6\n' | DRY_RUN=1 INPUT_SRC=/dev/stdin bash script/ubuntu/install-tools.sh`
Expected: 顯示 WakaTime 選取結果且不下載、不修改檔案。

### Task 3: 改造 setup.sh 多選入口

**Files:**
- Modify: `script/ubuntu/setup.sh`

- [ ] **Step 1: 建立腳本選單**

列出 `install-base.sh`、`install-tools.sh`、`install-tools-ai.sh`，使用 `INPUT_SRC` 讀取空白分隔編號；空輸入不執行任何腳本。

- [ ] **Step 2: 依選單順序執行並支援 DRY_RUN**

只執行選中的腳本；`DRY_RUN=1` 時只顯示將執行的腳本，不呼叫安裝子腳本。

- [ ] **Step 3: 測試選單**

Run: `printf '\n' | INPUT_SRC=/dev/stdin bash script/ubuntu/setup.sh`
Expected: 顯示未選擇任何腳本且不呼叫 installer。

### Task 4: 同步文件與驗證

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/new-machine-setup.md`
- Modify: `docs/no-sudo-setup.md`
- Modify: `docs/herdr-notifications.md`

- [ ] **Step 1: 更新入口與工具分類**

文件改用腳本／工具名稱，不依賴固定選單編號；說明 AI 腳本需明確選擇、Tailscale 不自動登入、WakaTime key 可留空與 zsh tracking 行為。

- [ ] **Step 2: 執行完整驗證**

Run: `bash -n script/ubuntu/*.sh && python3 -m unittest script/tests/test_ai_profile.py && chezmoi --no-tty execute-template --init < home/.chezmoi.toml.tmpl`
Expected: 全部 exit code 0。

- [ ] **Step 3: 檢查狀態與 diff**

Run: `git status --short && git diff --check`
Expected: 只有本計畫列出的檔案變更，沒有 whitespace error 或 secret 值。
