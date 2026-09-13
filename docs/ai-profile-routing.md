# AI profile routing

部署後使用四個入口切換環境：

| 入口 | 環境 |
|---|---|
| `codex-work` | 原本的公司 `~/.codex` |
| `codex-personal` | 共用 `~/.codex` 的 `personal` profile，官方 ChatGPT OAuth |
| `opencode-work` | 原本的 OpenCode XDG roots |
| `opencode-personal` | 共用 OpenCode roots，只切 personal routing view |

裸 `codex`、`opencode` 不變；`codex-personal` 只是 `codex --profile personal` 的
明確入口，與公司共用同一組 roots。

個人 profile 不會猜測模型。模型持久資料放在 chezmoi 的非秘密 `data.aiPersonal`：
`codexModel`、`models.astra`、`models.sol`、`models.luna`。留空時只產生合法 setup
config，不會被視為 ready；填妥後由 templates 產生 Codex model、OpenCode main/small
model，以及 OMO roles/council mapping，不由 launcher 生成第二份 runtime config。
模型 ID 必須由實際 entitlement 決定，不要填 placeholder。登入仍由使用者手動完成：

```text
codex-personal login
opencode-personal auth login
```

`codex-personal` 只使用官方 `openai` provider；`opencode-personal` 只允許
`openai`，且拒絕 project 的 gateway、model mapping 與 OMO 覆蓋。公司 credential
不會被 wrapper 清除；個人 child process 會清除公司／其他 provider 的環境變數。

個人 OpenCode 會使用共用 global config、skills、rules、prompt 與 state，只透過 route
view 切換 OMO model。它不宣稱公司 skills、MCP 或 remote attach 受到 model 限制。

公司與個人共用 Codex／OpenCode roots、auth、session、cache、skills、rules 與 prompt。
個人只切 provider/model，不宣稱公司 skills、MCP 或 remote attach 受到 model 限制。
OMO 的共用角色 skills/mcps/prompt 維持 global 設定；personal route view 只改 model、
council 與 ACP allowlist，不複製整套 runtime。
personal route 的 `skills` 與 `oh-my-opencode-slim` 目錄是整個目錄的 symlink，直接使用
global common resources；不再另外放同名 skill，避免 loader collision。

personal launcher 保留原 CLI argv、cwd、roots 與 project/native loader 語意；Codex 個人
入口等價於 `codex --profile personal`。登入、版本與 models 查詢不需要 model，也不會注入
model argv；Codex 的 `login`／`logout` 會原生轉送、不加 `--profile`。登入由使用者手動完成，沒有自動登入或 API-key route。個人 OpenCode route
view 的 OMO plugin 固定 2.2.18；TUI interactive 與首次 plugin 初始化未在此 lane 驗證。

OpenCode 的 work route 使用 global `~/.config/opencode/opencode.json` 與 global OMO；
personal route 只在 `~/.config/opencode/routes/personal/` 提供 routing view。這不是第二份
runtime 或 state；兩者仍共用 global auth、session、cache、skills、rules、prompt 與
TUI。inline `OPENCODE_CONFIG_CONTENT` 只保留非 routing 欄位後套用對應 provider/model。

公司 OMO 的 `teamsync` orchestrator 與 `council.terra` 現行 routing 使用
`codex-lb-gcp/gpt-6-astra`；`terra` 是席位名稱，`sol`／`luna` 與 provider catalog
保留原值。個人 OMO 的 `terra` 席位則使用 `data.aiPersonal.models.astra`，待登入後
再填入實際可用 model ID。
