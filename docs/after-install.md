# 裝完之後

機器照[新機器設定 Runbook](new-machine-setup.md) 裝好之後，想改點什麼看這頁。

```text
想做什麼？
│
├─ 改用途、加減選裝工具（Linux）
│    tools ──→ 用途（預設帶現在的）──→ 選單（預設帶現在的勾選；改成完整或精簡就帶那組）
│          ──→ Enter ──→ 自動 apply，新勾的才裝；改用途也不會移除已裝的
│
├─ 移除工具
│    取消勾選不會解除安裝 ──→ 用它自己的方式移除 ──→ 再打 tools 取消勾選
│                              sudo apt remove btop
│                              mise uninstall btop（沒有 root、非 Debian 系由 mise 裝的）
│                              npm uninstall -g <套件>
│
├─ 改 API key、密碼、Git 身分
│    chezmoi edit-config ──→ 改 [data] 那一行 ──→ chezmoi apply ──→ 寫進下表右欄
│
├─ 換提示列主題（starship）
│    starship preset --list ──→ starship preset <名字> -o /tmp/p.toml
│    ──→ export STARSHIP_CONFIG=/tmp/p.toml（只影響這個 shell，先看看）
│    ──→ 決定了：chezmoi edit ~/.config/starship.toml，換成 /tmp/p.toml 的內容（開頭註解留著、改 preset 名字）
│    ──→ chezmoi apply ──→ commit、push，其他機器 chezmoi update --init 跟上
│    各 preset 的截圖：https://starship.rs/presets/　自己調模組：https://starship.rs/config/
│
├─ 拉 repo 最新版
│    chezmoi update --init（= git pull + 照新的 config 樣板重算勾選 + apply）
│    不加 --init，apply 用的是舊的勾選：repo 新加進預設組合的工具不會裝，
│    換掉的工具卻照樣被清掉（例如 #194：p10k 先被刪，starship 要等下次 init 才裝）
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
