# 指令檔內容放 agent-config，放到哪由 chezmoi 的 symlink 負責

給模型讀的指令檔（Instructions）—— 全域 `AGENTS.md`（Claude 那邊叫 `CLAUDE.md`）、
`agent-commit/instructions.md`、opencode 的 `commit-instructions.md` —— 分兩半管：

| 管什麼 | 在哪 | 怎麼更新 |
|---|---|---|
| 內容 | agent-config 的 `instructions/<名字>/` | 改完在 agent-config commit，其他機器 `skillshare pull` |
| 放到哪 | 本 repo 的 `symlink_*.tmpl`，內容只有一行目標路徑（`{{ .chezmoi.homeDir }}/.config/skillshare/instructions/...`） | 改模板，`chezmoi apply` |

六個 symlink：

| 模板 | 部署成 | 指到 |
|---|---|---|
| `home/dot_claude/symlink_CLAUDE.md.tmpl` | `~/.claude/CLAUDE.md` | `instructions/agents-md/AGENTS.md` |
| `home/dot_codex/symlink_AGENTS.md.tmpl` | `~/.codex/AGENTS.md` | `instructions/agents-md/AGENTS.md` |
| `home/dot_config/opencode/symlink_AGENTS.md.tmpl` | `~/.config/opencode/AGENTS.md` | `instructions/agents-md/AGENTS.md` |
| `home/dot_config/opencode/routes/personal/symlink_AGENTS.md.tmpl` | `~/.config/opencode/routes/personal/AGENTS.md` | `instructions/agents-md/AGENTS.md` |
| `home/dot_config/opencode/symlink_commit-instructions.md.tmpl` | `~/.config/opencode/commit-instructions.md` | `instructions/opencode-commit/commit-instructions.md` |
| `home/dot_config/agent-commit/symlink_instructions.md.tmpl` | `~/.config/agent-commit/instructions.md` | `instructions/agent-commit/instructions.md` |

skillshare 不碰這些檔：`create_config.yaml` 沒有 `extras` 段，bootstrap 腳本的 `skillshare sync --all`
只負責 skills 與 MCP。`script/tests/test_instruction_symlinks.py` 驗 apply 後這六個路徑都是指對的 symlink。

## Considered Options

| 做法 | 結果 | 為什麼 |
|---|---|---|
| 全部留在 chezmoi（內容與 symlink 都在本 repo） | 不選 | 指令檔和 skills 是同一類東西（給模型讀、每台一樣），卻要分兩個 repo 改、兩套指令更新；指令檔之間互相引用的路徑（`AGENTS.md` 與 commit 指引都指 `~/.config/agent-commit/instructions.md`）也沒辦法跟 skills 一起在 agent-config 的 `tests/` 驗 |
| 內容放 agent-config，由 skillshare extras 放 symlink（agent-config `475fb40`、本 repo `cd9dc3d`） | 不選 | (1) 「連到哪」寫在 `create_config.yaml` 的 `extras` 段，本 repo 的 `home/dot_claude/` 等目錄看不出 `CLAUDE.md` 從哪來；(2) `create_` 只在檔案不存在時建立，已經裝過 agent-config 的機器 `config.yaml` 早就在，拿不到新加或改過的 extras 設定，只能每台手動 `skillshare extras init` |
| 內容放 agent-config，放到哪由 chezmoi `symlink_` 模板負責 | **選** | 在 `home/` 看得到每個指令檔的來源；模板改了 `chezmoi apply` 就會更新每台機器，不受 `create_` 限制；內容仍跟 skills 一起在 agent-config 改 |

## 代價

- **新機器 bootstrap 時 symlink 先懸空。** `chezmoi apply` 先部署檔案，這時 `~/.config/skillshare/instructions/`
  還不存在；要等 after 腳本 `run_onchange_after_install-agent-config.sh.tmpl` clone 完 agent-config 才指得到檔案。
  沒勾選裝工具 `agent-config` 的機器，這幾個 symlink 會一直懸空。
- **已安裝的機器要兩步才完整。** `skillshare pull` 拿到 `instructions/` 新目錄，`chezmoi apply` 把 symlink
  改指過去；只跑其中一個，symlink 會懸空或還指著舊的 `extras/`。
- **兩個 repo 綁著同一組路徑。** agent-config 搬動 `instructions/` 底下的檔案時，要同步改本 repo 的模板與
  `test_instruction_symlinks.py`。
