# tmux:多 agent 終端工作流

`home/dot_tmux.conf` + `home/dot_config/tmux/` → `~/.tmux.conf` + `~/.config/tmux/`。

本 repo 最客製的一塊,為「同時開很多 agent、很多 session」設計,疊在標準 tmux 之上。

## 組成

| 位置 | 做什麼 |
|---|---|
| `dot_tmux.conf` | 按鍵綁定、TPM 外掛宣告,以及 `status-left` / `status-right` 組裝(呼叫下面的腳本) |
| `dot_config/tmux/tmux-status/` | 狀態列內容 |
| `dot_config/tmux/scripts/` | session 管理與 agent 自動化 |
| `executable_fzf_panes.tmux` | 自製的 fzf MRU pane 選擇器 |

## 外掛(TPM)

`tmux-resurrect` + `tmux-continuum` —— session 持久化,還原 pane 內容與 `lazygit` / `yazi` 等程序。

TPM 本身**不由 chezmoi 部署**；前置是支援 `terminal-features` / `extended-keys` 的 tmux、Python 3、`jq`、`fzf`。copy-mode 的 `y` 走
`set-clipboard on`(OSC 52),不需要 `wl-copy` / `xclip`。外部 agent-tracker binary 不在 repo，缺少時
狀態列相關內容會安靜降級。

第一次初始化 TPM：

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

啟動 tmux 後按 `Ctrl-b`、`I` 安裝設定宣告的外掛（不是更新指令）。

## 狀態列(`tmux-status/`)

| 腳本 | 內容 |
|---|---|
| `left.sh` | 編號 session 標籤,寬度不足時自動收窄 |
| `right.sh` | agent 狀態,資料來自 `agent-tracker` |
| `mem_usage.sh` + `mem_usage_cache.py` | 每 pane / window 記憶體,走 cache 不每次重算(**沒接進狀態列**) |
| `notes_count.sh` | 待辦數(**沒接進狀態列**) |
| `window_task_icon.sh` | window 標籤上的任務狀態圖示;`session_task_icon.sh` 同類但**沒接上** |
| `tracker_cache.sh` | 把 agent-tracker 的輸出快取到 `/tmp/tmux-tracker-cache.json` |

## 腳本(`scripts/`)

`.tmux.conf` 只從 hook、`run-shell` 和 pane 標題格式叫其中幾支(`session_created`、`check_and_run_on_activate`、
`post_resurrect_restore`、`update_theme_color`、`pane_starship_title`)。**沒有任何綁鍵**,
所以下面 session 管理、剪貼簿、agent palette 這幾類部署了但按不到;fzf pane 選擇器也只有
MRU 紀錄在跑。

- **session 管理**:編號 session 的新增 / 重命名 / 排序 / 搬移、版面建構(`layout_builder.sh`)、依位置聚焦 pane
- **剪貼簿**:`copy_to_clipboard.sh` / `paste_from_clipboard.sh`,依環境挑 `wl-copy` / `xclip` / `pbcopy`
- **agent 自動化**:agent palette 彈窗、記住並還原 opencode pane 的工作目錄、
  `restore_agent_run_panes.py` 在 resurrect 還原後重啟 Flutter dev server 這類長跑程序

## 常用按鍵

```text
Ctrl-b                 tmux prefix（保留 tmux 預設）
Alt + ←↑↓→             不用 prefix，切換 pane
Shift-Alt + ←↑↓→       不用 prefix，將 pane 調整 5 格
Ctrl-b  I              TPM 安裝外掛
Ctrl-b  Ctrl-s         resurrect 手動保存
Ctrl-b  Ctrl-r         resurrect 手動還原
```

`tmux-continuum` 每 5 分鐘觸發 `tmux-resurrect` 保存 pane 內容與指定程序；`continuum-restore=off` 代表
**不會在 tmux 啟動時自動還原 session**，不是停用保存；可手動按 `Ctrl-b`、`Ctrl-r` 還原。

## 已知的孤兒

這兩支**沒有被任何設定呼叫**,而且在 repo 裡沒有 `executable_` 前綴(部署後 644、不可執行):

- `tmux-status/ccusage-today.sh` —— 呼叫 `ccusage-codex`,不在 `status-right` 的組裝裡
- `scripts/swap_window_in_session.sh`

要用就補 `executable_` 前綴並接進 `.tmux.conf`,不用就刪掉。

## 改設定

由 chezmoi 部署,直接改家目錄那份會被下次 `chezmoi apply` 蓋掉 ——
用 `chezmoi edit --apply ~/.tmux.conf`,或改完立刻 `chezmoi re-add`。

新增的腳本要可執行的話,檔名記得加 `executable_` 前綴。
