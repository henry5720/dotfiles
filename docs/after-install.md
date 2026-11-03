# 裝完之後

機器照[新機器設定 Runbook](new-machine-setup.md) 裝好之後，想改點什麼看這頁。

```text
想做什麼？
│
├─ 改用途、加減選裝工具（只有 Ubuntu）
│    tools ──→ 用途（預設帶現在的）──→ 選單（預設帶現在的勾選；改成完整或精簡就帶那組）
│          ──→ Enter ──→ 自動 apply，新勾的才裝；改用途也不會移除已裝的
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
| `context7ApiKey` | `~/.config/zsh/env.zsh`（留空或沒勾 zsh 就不部署） | 開新的 zsh |
| `codeServerPassword` | `~/.config/code-server/config.yaml`（沒勾 code-server 就不部署） | 重啟 code-server |
| `gitUserName`、`gitUserEmail` | `~/.gitconfig` | — |

- 不要直接改右欄的檔案：下次 `chezmoi apply` 會被蓋回 `chezmoi.toml` 裡的值。
- `~/.config/chezmoi/chezmoi.toml` 有明文的 key，不要 `cat` 出來貼給別人或 agent。
- 憑證只在勾了用得到它的工具時才問（對照表在[新機器設定](new-machine-setup.md)），沒問過的 key 不會出現在 `[data]`。
  `tools` 新勾的工具用得到、還沒存過的憑證，會在 `tools` 時問；存過的不重問、取消勾選也不刪，只有 `chezmoi edit-config` 改得到。
