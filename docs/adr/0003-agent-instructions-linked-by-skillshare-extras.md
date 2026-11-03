# 指令檔由 skillshare extras 連到各 client，連結設定由 chezmoi 的 modify_ 釘

取代 [ADR 0002](0002-agent-instructions-in-agent-config-placed-by-chezmoi-symlinks.md)。
目標是 agent 的設定（規則、skills、MCP）都由 skillshare 管：dashboard、`status`、`doctor` 看得到指令檔，
連結斷了也檢查得出來。

給模型讀的指令檔（Instructions）分三半管：

| 管什麼 | 在哪 | 怎麼更新 |
|---|---|---|
| 內容 | agent-config 的 `instructions/<名字>/` | 改完在 agent-config commit，其他機器 `skillshare pull` |
| 連到哪 | 本 repo `home/.chezmoitemplates/skillshare-pinned`，由 `home/dot_config/skillshare/modify_config.yaml.tmpl` 釘成 `extras` 段 | 改模板，`chezmoi apply` |
| 建連結 | skillshare（`sync --all`，含 extras） | `chezmoi apply` 後由 `run_onchange_after_sync-skillshare.sh.tmpl` 跑 |

三個 extras、六個目標（三個 client 都勾時；後來改成照勾的 client 產生，見下面「照選單產生」）：

| extra | 來源 | 連到 |
|---|---|---|
| `agents-md` | `instructions/agents-md/AGENTS.md` | `~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md`、`~/.config/opencode/AGENTS.md`、`~/.config/opencode/routes/personal/AGENTS.md` |
| `agent-commit` | `instructions/agent-commit/instructions.md` | `~/.config/agent-commit/instructions.md` |
| `opencode-commit` | `instructions/opencode-commit/commit-instructions.md` | `~/.config/opencode/commit-instructions.md` |

同一支 `modify_` 也釘 `targets` 段，其中 Claude target 帶 `agents` 路徑（`~/.claude/agents`），自己寫的 subagent 放 agent-config 的
`agents/` 就會連過去；Codex 的 subagent 是 TOML，native agents target 不能轉檔，沒釘。

### 照選單產生（#211）

`targets` 與 `extras` 兩段照選單勾的 client 產生（`.chezmoitemplates/skillshare-pinned`），每次 apply 整段換掉：

| 勾了 | target | extras |
|---|---|---|
| claude | `claude`（skills、agents） | `~/.claude/CLAUDE.md` |
| codex | `codex`（skills） | `~/.codex/AGENTS.md` |
| opencode | 不加（OpenCode 也讀前兩份，再加一份同一支 skill 會出現三次） | opencode 的 `AGENTS.md`、`routes/personal`、`opencode-commit` |
| 任一個 agent | | `agent-commit` |

手動 `skillshare target add` 加的 target 下次 apply 會被蓋掉，真相只在 repo。沒勾的 client 不部署它的設定目錄
（`.chezmoiignore`），沒勾 `agent-config` 不放 `config.yaml`。取消勾選時已經同步出去的檔案留著。
兩段的內容進了 `run_onchange_after_sync-skillshare` 的 hash，勾選一變就 `skillshare sync --all`，新勾的 client 也拿得到 skills。

`script/tests/test_skillshare_extras.py` 驗 `modify_` 在各種勾法下的輸出、哪些設定目錄被排除，以及 skillshare sync 後只連出有勾的路徑。

## 為什麼 0002 的理由不再成立

0002 不選 extras 有兩點：

1. **`home/` 看不出 `CLAUDE.md` 從哪來。** 現在 `modify_config.yaml.tmpl` 一個檔就列出全部連結，
   找起來比散在六個 `symlink_` 模板還集中。
2. **`create_` 只建一次，已裝過的機器拿不到新的 extras。** 改成 `modify_` 後每次 apply 都會釘 extras 段；
   再由 `run_onchange_` 腳本在段落變動時跑 `skillshare sync extras`，一步 `chezmoi apply` 就生效。

## Considered Options

| 做法 | 結果 | 為什麼 |
|---|---|---|
| 維持 chezmoi `symlink_` 模板（0002） | 不選 | skillshare 看不到這些檔，dashboard 的 Extras 是空的，`status`／`doctor` 也不會檢查 |
| extras 寫在 `create_config.yaml` | 不選 | 0002 的第 2 點：已裝過的機器不會更新 |
| `modify_` 整份覆寫 `config.yaml` | 不選 | skillshare init 與 extras 指令會改寫這個檔（加 schema 註解、重排 key），整份覆寫會一直出 diff |
| `modify_` 只換 `targets`、`extras` 兩段 | **選** | 其餘照 skillshare 寫的留著；extras 段照 skillshare 存檔的欄位順序、不放註解，它改寫後再 apply 沒有 diff |

## 代價

- **extras 段要照 skillshare 的格式寫。** 段落內的註解會被 skillshare 存檔拿掉，說明寫在模板的腳本註解裡。
  用 `skillshare extras` 指令改的連結會在下次 `chezmoi apply` 被蓋回去；要改就改模板。
- **兩個 repo 綁著同一組路徑。** agent-config 搬動 `instructions/` 底下的檔案時，要同步改本 repo 的模板與測試。
- **沒勾 `agent-config` 的機器**不放 `config.yaml`，沒有 skillshare 去連，各 client 不會有指令檔
  （0002 時是懸空的 symlink）。
