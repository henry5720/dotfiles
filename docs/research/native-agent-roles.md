# Claude 與 Codex 原生角色：格式與能力差異

查證日期：2026-10-09。對象：Claude Code 2.1.295（`claude --version`）、codex-cli 0.161.0（`codex --version`）。
問題來自 [#140](https://github.com/henry5720/dotfiles/issues/140)（map [#137](https://github.com/henry5720/dotfiles/issues/137)）；0.154 時的舊結論在 [#12](https://github.com/henry5720/dotfiles/issues/12)。

**結論**：

- Claude 的角色檔能管的東西多：模型、effort、工具白名單／黑名單、MCP（可加可減）、預載 skill、權限模式、hook、memory。
- Codex 的角色檔實際只吃 `developer_instructions`、`model`、`model_reasoning_effort` 和少數幾個 scalar，外加「只能關、不能開」的 features 與 skills。
  `sandbox_mode`、`mcp_servers`、`approval_policy` 寫了會被**靜默丟掉** —— 官方文件說可以，原始碼和測試說不行，以原始碼為準。
- 自動挑角色：Claude 會照 `description` 主動派；Codex 在使用者、AGENTS.md 或 skill **明確要求開 subagent** 之前不會派，派了才照 `description` 挑角色。
- 0.154 → 0.161 角色機制幾乎沒變，唯一差別是 features 可關的 flag 從 6 個少了 `personality`，剩 5 個。
- 同一份來源：**只有 prompt 本文能共用**。frontmatter／TOML 欄位、模型名稱、effort 值域兩邊不同，要各寫一份薄殼；用 chezmoi 的 `.chezmoitemplates/` 放共用 prompt，兩邊各自 `{{ template }}` 進去可行。

來源標示：**[CC-doc]** = [code.claude.com/docs/en/sub-agents](https://code.claude.com/docs/en/sub-agents)；
**[CX-doc]** = [developers.openai.com/codex/subagents](https://developers.openai.com/codex/subagents)（308 轉到 `learn.chatgpt.com/docs/agent-configuration/subagents`）；
**[CX-src]** = [openai/codex](https://github.com/openai/codex) tag `rust-v0.161.0`，行號照該 tag；**[實測]** = 本機指令輸出。

## 1. 能設定什麼

| 維度 | Claude `~/.claude/agents/*.md` | Codex `~/.codex/agents/*.toml` |
|---|---|---|
| 格式 | YAML frontmatter + Markdown 本文（本文就是 system prompt）[CC-doc] | 一個 TOML 檔，`name`、`description`、`developer_instructions` 必填 [CX-doc]；其餘鍵照 `config.toml` 解析 [CX-src `agent-roles/src/agent_role_config.rs:20-28`] |
| 掃描 | `~/.claude/agents/`、各層 `.claude/agents/` 遞迴；身分只看 `name` [CC-doc] | 每個 config layer 的 `agents/` 遞迴掃 `.toml`（#12 已查，0.161 未變） |
| 載入時機 | 檔案監看，改完幾秒生效；`agents/` 目錄是 session 開始後才建的要重開 [CC-doc] | 啟動時讀；壞檔只出 startup warning 不中止 [CX-src `agent-roles/src/loader.rs:119-122`] |
| 模型 | `model`：`sonnet`／`opus`／`haiku`／`fable`／完整 ID／`inherit`。優先序：呼叫時傳的 `model` > frontmatter > `CLAUDE_CODE_SUBAGENT_MODEL` > 主對話 [CC-doc] | `model`。先解出 spawn 參數 → `[agents].default_subagent_model` → 父 agent，**角色檔再蓋過去** [CX-src `core/src/agent/child_config.rs:62-74`]；工具描述會告訴主 agent「這角色的模型不能改」[CX-src `core/src/agent/role.rs:296-330`] |
| reasoning effort | `effort`：`low`／`medium`／`high`／`xhigh`／`max`（依模型）；呼叫時可傳 `effort` 覆寫；`CLAUDE_CODE_EFFORT_LEVEL` 最大 [CC-doc]。extended thinking 跟主對話，不能各別設 [CC-doc] | `model_reasoning_effort`，另有 `model_reasoning_summary`、`model_verbosity`、`personality`、`service_tier` [CX-src `role.rs:37-48`]；套用後會檢查該模型支不支援這個 effort [CX-src `child_config.rs:283-316`] |
| 工具 | `tools` 白名單、`disallowedTools` 黑名單，支援 `mcp__<server>` 整組 [CC-doc]。背景跑的 subagent 內建工具會再被砍一輪 [CC-doc] | 沒有工具清單。只能用 `[features]` **關掉** `shell_tool`、`apps`、`plugins`、`memory_tool`、`request_permissions_tool` 五個 [CX-src `role.rs:91-105`]；寫 `true` 被忽略 |
| MCP | `mcpServers`：引用既有 server 名，或 inline 定義只給這個 subagent 用；配合 `tools`／`disallowedTools` 可縮減 [CC-doc]。plugin 來的 agent 不吃這欄 [CC-doc] | **不行**。`mcp_servers` 不在白名單，子 agent 的 MCP 等於父 agent [CX-src `core/src/agent/role_tests.rs:436-541`，測試名 `apply_role_cannot_expand_parent_authority`，斷言 `config.mcp_servers == parent.mcp_servers` 且角色 layer 不得含 `mcp_servers`] |
| skills | `skills`：把指定 skill 全文**預載**進 context；不限制能用哪些，要禁用就拿掉 `Skill` 工具 [CC-doc] | 只能**關**：`[[skills.config]]` 只保留 `enabled = false` 的項目，`skills.include_instructions` 只能設 `false` [CX-src `role.rs:106-117`] |
| 權限 | `permissionMode`：`default`／`acceptEdits`／`auto`／`dontAsk`／`bypassPermissions`／`plan`。主對話在 `bypassPermissions`、`acceptEdits`、auto 時被忽略，一律跟主對話 [CC-doc] | **不行**。`sandbox_mode`、`approval_policy` 被丟掉，連收緊成 read-only 也不行；spawn 時再把父 turn 的 approval、sandbox、cwd 蓋回去 [CX-src `role_tests.rs:396-433`、`child_config.rs:170-192`] |
| 其他 | `hooks`、`memory`、`maxTurns`、`isolation: worktree`、`background`、`omitClaudeMd`、`color`、`initialPrompt`、`experimental.cacheTtl` [CC-doc] | `nickname_candidates` [CX-src `agent_role_config.rs:20-28`] |
| 寫錯欄位 | 未知欄位靜默忽略；缺 `name` 當成文件、缺 `description` 跳過並寫 debug log。`claude plugin validate ~/.claude/agents` 可預檢 [CC-doc] | 缺必填欄位 → startup warning（#12 實測 `codex doctor --json` 會顯示）；白名單外的合法 config 鍵靜默忽略 |

### 官方文件與原始碼衝突

[CX-doc] 的「Custom agent file schema」寫「You can also include other supported `config.toml` keys ... such as `model`, `model_reasoning_effort`, `sandbox_mode`, `mcp_servers`, and `skills.config`」，
範例還示範在角色檔裡加 `[mcp_servers.openaiDeveloperDocs]` 和 `sandbox_mode = "read-only"`。

原始碼不是這樣：`role.rs` 開頭註解寫「Roles may customize the child or reduce its capabilities, but never replace the parent session's authority」[CX-src `role.rs:1-4`]，
`apply_role_to_config_inner` 只把白名單欄位放進 `AgentRoleOverrides` [CX-src `role.rs:80-89`]，測試明確斷言 `sandbox_mode`、`approval_policy`、`mcp_servers`、`apps` 等鍵「role must not control」[CX-src `role_tests.rs:529-541`]。
同一頁 [CX-doc] 的 CLI 段落也自己承認「Codex also reapplies the parent turn's live runtime overrides ... even if the selected custom agent file sets different defaults」。

**照原始碼設計**：Codex 角色不要寫 `sandbox_mode`、`mcp_servers`，寫了不會報錯但不生效。要限制 subagent 只讀，只能寫進 `developer_instructions` 當軟約束，或在父 session 就用較嚴的權限。

## 2. 主 agent 何時自己挑角色

**Claude**：自動。主 agent 依使用者請求、各角色的 `description`、當下 context 決定要不要派；`description` 寫「use proactively」會更常派 [CC-doc]。
要確定用某角色：在 prompt 點名（Claude 仍可能不派）、`@agent-<name>`（保證這次用它）、`claude --agent <name>` 或 settings 的 `agent`（整個 session 都是它）[CC-doc]。
不想被派：`permissions.deny` 加 `Agent(<name>)` [CC-doc]。

**Codex**：要先被授權才會派，派了才自己挑角色。

- 預設走 multi-agent v1（本機 `codex features list`：`multi_agent stable true`、`multi_agent_v2 stable false` [實測]）。
- v1 的 `spawn_agent` 工具描述寫死：「Do not spawn sub-agents unless the user or applicable AGENTS.md/skill instructions explicitly ask for sub-agents, delegation, or parallel agent work. Requests for depth, thoroughness, research ... do not count」，
  並說角色說明「only helps choose which agent to use after spawning is already authorized」[CX-src `core/src/tools/handlers/multi_agents_spec.rs:727-740`]。
- 授權之後，主 agent 從工具描述裡的「Available roles:」清單（自訂角色在前、內建 `default`／`explorer`／`worker` 在後）挑 `agent_type`；不給就用 `default` [CX-src `role.rs:265-330`、`multi_agents_spec.rs:21`]。
- v1 的完整歷史 fork（`fork_context = true`）不能同時指定 `agent_type`，會直接報錯 [CX-src `child_config.rs:159-166`]。
- 官方文件一致：「Current local Codex releases spawn agents after a direct request or applicable project or skill instruction」[CX-doc]。

所以 Codex 要讓角色被用到，觸發點要放在 skill 或 AGENTS.md（例如「用 `reviewer` subagent 審查」），不能只靠角色的 `description`。

## 3. 0.154 → 0.161 改了什麼

對兩個 tag 做 `diff`：

- `codex-rs/agent-roles/`：**完全相同**。
- `[agents]` 設定（`AgentsToml`：`enabled`、`max_concurrent_threads_per_session`、`max_depth`、`default_subagent_model`、`default_subagent_reasoning_effort`、`interrupt_message`、角色宣告）：欄位相同 [CX-src `config/src/config_toml.rs:753-785`]。
- `core/src/agent/role.rs`：features 可關清單**拿掉 `Feature::Personality`**（0.154 `role.rs:97` 還有），從 6 個變 5 個；personality 是否重設 base instructions 的判斷改寫；layer stack 多帶 cloud config binding。
- `multi_agents_spec.rs`：「不要主動 spawn」那段 0.154 就有（0.154 `multi_agents_spec.rs:696`），沒變；新增 `model_catalog_in_context` 時的模型選單說明，與角色無關。

#12 的結論（白名單、MCP 無對應、skills 只能關、純宣告式）在 0.161 **仍然成立**。

## 4. 能不能從同一份來源產生

能共用的只有 prompt 本文，其他都要各寫：

| 項目 | 能否共用 | 原因 |
|---|---|---|
| `name`、`description` | 可以（值相同） | 兩邊都有。Codex 範例用底線名稱（`pr_explorer`），Claude 名稱不能含 `:` [CC-doc]，用 `a-z0-9_-` 兩邊都安全 |
| prompt 本文 | 可以 | Claude 是 Markdown 本文，Codex 是 `developer_instructions` 字串 |
| 模型 | 不行 | 名稱空間不同（`opus` vs `gpt-*`），Claude 的 `inherit` 在 Codex 等於不寫 |
| effort | 勉強 | 兩邊都有 `low`～`max`，但支援哪些依模型而定，不能保證對應 |
| 工具、MCP、權限、skills、hooks | 不行 | Codex 沒有對應欄位或只能關，見第 1 節 |

chezmoi 做法（推薦）：共用 prompt 放 `home/.chezmoitemplates/agent-prompts/<role>.md`，
兩邊各一個薄殼 `home/dot_claude/agents/<role>.md.tmpl`（frontmatter + `{{ template "agent-prompts/<role>.md" . }}`）和
`home/dot_codex/agents/<role>.toml.tmpl`（`developer_instructions = '''` + 同一個 template + `'''`）。
Codex 那邊用 TOML 的多行**字面**字串 `'''`，prompt 裡的反斜線、雙引號不用跳脫；唯一限制是 prompt 本文不能含 `'''`。

不選「寫一支產生器腳本把一份 YAML 轉成兩種檔」：兩邊能共用的欄位只有三個，產生器要維護的映射比它省下的重複還多。

角色檔都是獨立檔案、不含秘密，不需要 `modify_`、不要加 `executable_`（#12 已說明）。

## 5. 沒查到或沒實測的

- **沒有在 0.161 實際 spawn 一個帶 `mcp_servers`／`sandbox_mode` 的角色**看結果；結論靠原始碼與單元測試（`role_tests.rs:396-541`）。要百分之百確認，可在拋棄式 `CODEX_HOME` 放一個 inline stdio MCP（啟動時 `touch` 標記檔）的角色，叫 Codex spawn 它，看標記檔有沒有出現。
- Claude 側沒有看原始碼（不公開），全部依官方文件；沒有實測 2.1.295 的行為與文件是否一致。
- Codex 角色 TOML 寫錯鍵名（不是合法 config 鍵）時是報錯還是忽略：`RawAgentRoleFileToml` 有 `deny_unknown_fields` 又 `flatten` 了 `ConfigToml`，serde 這個組合的行為沒實測。
- multi-agent v2（`multi_agent_v2`，預設關）的 `agent_type` 描述是「Omit unless explicitly asked」[CX-src `multi_agents_spec.rs:661`]，比 v1 更保守；本機沒開，沒深入看。
