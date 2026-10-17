# 裝完之後

機器照[新機器設定 Runbook](new-machine-setup.md) 裝好之後，想改點什麼看這頁。

```text
想做什麼？
│
├─ 加減選裝工具（只有 Ubuntu）
│    tools ──→ 選單（預設帶現在的勾選）──→ Enter ──→ 自動 apply，新勾的才裝
│
├─ 移除工具
│    取消勾選不會解除安裝 ──→ 用它自己的方式移除 ──→ 再打 tools 取消勾選
│                              sudo apt remove btop
│                              npm uninstall -g <套件>
│
├─ 改 API key、密碼、Git 身分
│    chezmoi edit-config ──→ 改 [data] 那一行 ──→ chezmoi apply ──→ 寫進下表右欄
│
├─ 拉 repo 最新版
│    chezmoi update（= git pull + apply）
│
└─ 不小心直接改了家目錄的檔
     chezmoi re-add <檔案> ──→ 收回 repo（不收，下次 apply 會被蓋回去）
```

## 憑證與 Git 身分寫進哪裡

| `[data]` 的 key | 寫進 | 改完 |
|---|---|---|
| `wakatimeApiKey` | `~/.wakatime.cfg`（留空就不部署） | — |
| `codexLbApiKey` | `~/.codex/config.toml`、`~/.config/opencode/opencode.json` | — |
| `context7ApiKey` | `~/.config/zsh/env.zsh` | 開新的 zsh |
| `codeServerPassword` | `~/.config/code-server/config.yaml` | 重啟 code-server |
| `gitUserName`、`gitUserEmail` | `~/.gitconfig` | — |

- 不要直接改右欄的檔案：下次 `chezmoi apply` 會被蓋回 `chezmoi.toml` 裡的值。
- `~/.config/chezmoi/chezmoi.toml` 有明文的 key，不要 `cat` 出來貼給別人或 agent。
- `tools` 不會重問憑證；只有 `chezmoi edit-config` 改得到。
