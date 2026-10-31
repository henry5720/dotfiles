# 指令檔由 skillshare extras 連到各 client，連結設定由 chezmoi 的 modify_ 釘

取代 [ADR 0002](0002-agent-instructions-in-agent-config-placed-by-chezmoi-symlinks.md)。
目標是 agent 的設定（規則、skills、MCP）都由 skillshare 管：dashboard、`status`、`doctor` 看得到指令檔，
連結斷了也檢查得出來。

給模型讀的指令檔（Instructions）分三半管：

| 管什麼 | 在哪 | 怎麼更新 |
|---|---|---|
| 內容 | agent-config 的 `instructions/<名字>/` | 改完在 agent-config commit，其他機器 `skillshare pull` |
| 連到哪 | 本 repo `home/dot_config/skillshare/modify_config.yaml.tmpl` 釘的 `extras` 段 | 改模板，`chezmoi apply` |
| 建連結 | skillshare（`sync extras`） | `chezmoi apply` 後由 `run_onchange_after_sync-skillshare-extras.sh.tmpl` 跑 |

三個 extras、六個目標：

| extra | 來源 | 連到 |
|---|---|---|
| `agents-md` | `instructions/agents-md/AGENTS.md` | `~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md`、`~/.config/opencode/AGENTS.md`、`~/.config/opencode/routes/personal/AGENTS.md` |
| `agent-commit` | `instructions/agent-commit/instructions.md` | `~/.config/agent-commit/instructions.md` |
| `opencode-commit` | `instructions/opencode-commit/commit-instructions.md` | `~/.config/opencode/commit-instructions.md` |

`script/tests/test_skillshare_extras.py` 驗 `modify_` 的輸出，以及 skillshare sync 後這六個路徑都連對。

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
| `modify_` 只換 `extras` 段 | **選** | 其餘照 skillshare 寫的留著；extras 段照 skillshare 存檔的欄位順序、不放註解，它改寫後再 apply 沒有 diff |

## 代價

- **extras 段要照 skillshare 的格式寫。** 段落內的註解會被 skillshare 存檔拿掉，說明寫在模板的腳本註解裡。
  用 `skillshare extras` 指令改的連結會在下次 `chezmoi apply` 被蓋回去；要改就改模板。
- **兩個 repo 綁著同一組路徑。** agent-config 搬動 `instructions/` 底下的檔案時，要同步改本 repo 的模板與測試。
- **沒勾 `agent-config` 的機器** `config.yaml` 照樣有 extras 段，但沒有 skillshare 去連，各 client 不會有指令檔
  （0002 時是懸空的 symlink）。
