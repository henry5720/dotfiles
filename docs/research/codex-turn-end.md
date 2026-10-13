# Codex 什麼時候結束 turn、怎麼從 log 分辨停下的原因

查證日期：2026-10-09。對象：codex-cli 0.161.0（本機 `codex --version`）。對應 ticket：#139（map #137）。

**結論**

1. 結束 turn 由**模型**決定，CLI 只照規則判斷：模型這一輪回應裡有 tool call，或 API 回 `end_turn: false`，就再跑一輪；
   都沒有就結束 turn。CLI 本身不會判斷「任務做完沒」。
2. AGENTS.md、prompt 只是給模型看的文字，影響機率，不能保證；內建 system prompt 本來就寫了「keep going until the query is completely resolved」，
   提前結束的 issue 還是一直有人回報。**真正能從外面擋住結束的只有兩個機制**：`Stop` hook（`decision: "block"` 會把 reason 當新 prompt 繼續同一個 turn）
   和 `/goal`（thread 閒下來時自動開下一個 turn，直到 goal 完成或預算用完）。兩者在 0.161 都預設開啟。
3. 提前結束是已知、跨版本、跨模型的回報（0.145～0.160.1，gpt-5.6-terra、gpt-6.1-sol 等），全部標 `model-behavior`，沒有維護者回應或修正。
4. `~/.codex/sessions` 的 rollout **不記錄核准請求本身**（`ExecApprovalRequest`、`RequestUserInput` 等不落盤），所以「正在等權限」和「CLI 掛掉」
   在 log 裡長得一樣：最後一個 turn 有 `task_started`、沒有 `task_complete`／`turn_aborted`。要靠 process 是否還活著來分。
   正常結束和「停下來問需求」都是 `task_complete`，差別只在最後一則訊息的內容。

來源標示：**[src]** 是 openai/codex 在 tag `rust-v0.161.0` 的原始碼（連結附行號）；**[doc]** 是官方文件；**[issue]** 是 GitHub issue（使用者回報）；
**[本機]** 是讀本機 9 個 rollout 檔（0.155.1 與 0.161.0 產生）得到的格式，只記欄位名，沒抄內容。

原始碼連結前綴：`https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/`，下文簡寫成 `codex-rs/...`。

## 1. turn 怎麼結束

一個 turn = 一次使用者輸入之後，CLI 反覆「送 request 給模型 → 執行模型要的 tool → 再送」的迴圈。迴圈在 `run_turn`
（`codex-rs/core/src/session/turn.rs`）。

```
送 sampling request
  └─ 收到的 output item 是 tool call → needs_follow_up = true，執行 tool        [src] core/src/stream_events_utils.rs#L356
  └─ tool 被拒、要直接回模型（RespondToModel）→ needs_follow_up = true           [src] core/src/stream_events_utils.rs#L424
  └─ response.completed 帶 end_turn: false → needs_follow_up = true            [src] core/src/session/turn.rs#L3000
  └─ 只有文字訊息／reasoning → needs_follow_up 保持 false
needs_follow_up = 模型要 follow-up || 使用者在 turn 中途又送了輸入（steer）       [src] core/src/session/turn.rs#L566
  ├─ true  → 必要時先 auto-compact，然後 continue 下一輪
  └─ false → 跑 Stop hook → 沒被擋就 break，送出 TurnComplete                    [src] core/src/session/turn.rs#L653-L758
```

- `end_turn` 是 Responses API `response.completed` 的欄位，CLI 原樣讀進來；串流被中斷時強制當成 `Some(false)`
  [src] `codex-rs/codex-api/src/sse/responses.rs#L105-L114`、`#L450-L454`。
- 所以「模型講完一段話、沒呼叫 tool」就是結束 turn 的訊號。issue 裡常見的「說要繼續、列了剩下的步驟，然後就停」就是模型輸出了一則
  `final_answer` 訊息、沒有 tool call。

turn 以三種事件之一收尾 [src] `codex-rs/core/src/tasks/mod.rs#L802-L842`：

| 事件 | 何時 | rollout 裡的 `payload.type` |
|---|---|---|
| `TurnComplete`，`error` 為空 | 正常結束 | `task_complete` |
| `TurnComplete`，帶 `error` | 不可重試的錯誤（例如串流錯誤用完重試、用量上限）。`TurnCompleteEvent.error` 欄位 [src] `codex-rs/protocol/src/protocol.rs#L2153-L2159` | `task_complete`，多一個 `error` 鍵 |
| `TurnAborted` | `reason` 是 `interrupted`／`replaced`／`review_ended`／`budget_limited` [src] `protocol.rs#L4280-L4285` | `turn_aborted` |

### `codex exec` 的差別

- 預設 `approval_policy = never`（除非設定的 reviewer 是 auto-review）[src] `codex-rs/exec/src/lib.rs#L589-L591`。
- 收到指令核准、檔案變更核准、`request_user_input` 的請求時直接拒絕：「command execution approval is not supported in exec mode」[src] `exec/src/lib.rs#L2091-L2125`。
  所以 exec **不會停下來等權限或等回答**，被拒的訊息回給模型，模型自己決定要不要繼續。
- 只跑一個 turn，收到該 turn 的 `turn/completed` 就關閉；turn 狀態是 `failed`／`interrupted`，或有不重試的 `error` 通知時 exit code 1，否則 0
  [src] `exec/src/lib.rs#L1340-L1400`。exit 0 只代表 turn 正常收尾，不代表任務完成。

## 2. AGENTS.md、prompt、設定能不能讓它繼續

| 手段 | 效果 | 根據 |
|---|---|---|
| AGENTS.md／prompt 寫「做完才停」 | 只是給模型的文字，不改 CLI 的判斷。內建 prompt 已經寫了「Please keep going until the query is completely resolved… Only terminate your turn when you are sure that the problem is solved」，issue 回報者也說明確指示了仍然停 | [src] `codex-rs/protocol/src/prompts/base_instructions/default.md#L125`；[issue] #35580、#43882 |
| **`Stop` hook** | turn 要結束時執行。輸出 `{"decision":"block","reason":"..."}`（或 exit 2、reason 寫 stderr）→ 不結束，把 reason 當成新的 prompt 繼續**同一個 turn**；`stop_hook_active` 會告訴 hook 這已經是被擋過一次的續跑，避免無限迴圈。子 agent 跑的是 `SubagentStop` | [src] `core/src/session/turn.rs#L654-L708`、`hooks/src/events/stop.rs#L312-L319`、`#L343-L347`、`core/src/hook_runtime.rs#L392-L432`；[doc] https://learn.chatgpt.com/docs/hooks（原 developers.openai.com/codex/hooks，「Hooks are enabled by default」） |
| **`/goal`** | 設一個 goal 之後，thread 一閒下來（turn 結束），goal extension 就自動開下一個 turn，直到 goal 被標完成、預算用完，或 turn 出錯（出錯會把 goal 停掉，避免燒 token 的迴圈）。feature `goals` 是 Stable、預設開 | [src] `features/src/lib.rs#L1761-L1766`、`ext/goal/src/extension.rs#L180-L190`、`#L401-L410`；TUI `/goal` [src] `tui/src/slash_command.rs#L139` |
| hooks 開關 | `[features] hooks = false` 才關；預設 Stable／開 | [src] `features/src/lib.rs#L1253-L1258` |
| 放寬權限（`approval_policy`、sandbox） | 只解決「等權限」那一種停，和模型提前結束無關 | 見第 1 節 |

注意：

- `Stop` hook 只能「看到要結束了就再推一把」，判斷任務做完沒要 hook 自己寫（例如看 `last_assistant_message`、跑檢查）。
- `/goal` 在 `codex exec` 能不能用、會不會自動續跑，這次沒查證。
- [issue] #36506（Windows Desktop，2026-08）回報 Goal 模式下 turn 仍會中途變 idle、goal 還是 active；已關閉並併入 #27352。所以 `/goal` 也不是保證。

## 3. 已知提前結束的 issue

都是使用者回報、標 `model-behavior`，查證時都沒有 OpenAI 維護者回覆或修正。同一現象被拆成很多張，bot 標了一串重複。

| issue | 版本／介面 | 模型 | 現象 |
|---|---|---|---|
| [#35580](https://github.com/openai/codex/issues/35580)（2026-07-27，open） | CLI 0.145.0，WSL2 | gpt-5.6-terra；留言者也在 gpt-5.6-sol 看到 | 明確指示「到某點才停」仍中途停，模型自己列出未完成項目後結束 turn |
| [#43882](https://github.com/openai/codex/issues/43882)（2026-09-08，open） | Desktop、CLI（Windows／macOS） | 留言者：換成 sol medium 後好轉、terra high 嚴重 | 長任務在進度回報後結束；有留言指出 rollout 是正常的 `final_answer` + `task_complete` |
| [#46841](https://github.com/openai/codex/issues/46841)（2026-09-20，open） | CLI 0.155.1 | 5.6 terra | 忘了把任務做完 |
| [#50771](https://github.com/openai/codex/issues/50771)（2026-10-04，open） | Desktop；留言者 CLI 0.160.1（approval never、無限制檔案存取） | gpt-6.1-sol、GPT-6 Luna | 說要繼續就結束 turn；有一個 turn 32.5 秒、沒有可見回覆就結束 |
| [#42937](https://github.com/openai/codex/issues/42937)（2026-09，open） | Desktop（Windows） | GPT-5.6 Sol、GPT-6 Astra | 新模型自主完成度下降、提前停、宣稱完成 |
| [#36506](https://github.com/openai/codex/issues/36506)（2026-08-01，closed→#27352） | Desktop（Windows） | — | Goal 模式仍中途 idle |

能說的範圍：跨 0.145～0.160.1、多個模型都有人回報，最後一則都是正常的 `final_answer`，符合第 1 節「模型沒呼叫 tool 就結束」的機制，
不是 CLI 崩潰。有沒有特定版本變嚴重、是不是模型端改動造成，issue 裡沒有證據，這裡不下結論。沒找到 0.161 專屬的回報。

## 4. 從 `~/.codex/sessions` 分辨四種停法

### 4.1 檔案格式

- 路徑 `~/.codex/sessions/YYYY/MM/DD/rollout-<時間>-<thread id>.jsonl`，一行一筆 JSON，頂層鍵 `timestamp`、`ordinal`、`type`、`payload` [本機]。
- 哪些事件落盤由 `should_persist_event_msg` 決定 [src] `codex-rs/rollout/src/policy.rs#L94-L204`：

| 落盤 | 不落盤（只在當下送給 UI） |
|---|---|
| `task_started`、`task_complete`、`turn_aborted`、`token_count`、`thread_settings_applied`、`thread_goal_updated`、`thread_rolled_back`、`item_completed`（paginated 模式下全部） | `ExecApprovalRequest`、`ApplyPatchApprovalRequest`、`RequestPermissions`、`RequestUserInput`、`ElicitationRequest`、`Error`、`StreamError`、`Warning`、`ExecCommandBegin/End`、`HookStarted/Completed`、`ShutdownComplete` |

- 其他頂層 `type` [本機]：`session_meta`（`cli_version`、`source`=`cli`/`exec`/`vscode`/`{subagent:…}`、`originator`=`codex-tui`/`codex_exec`、`thread_source`）、
  `turn_context`（`approval_policy`、`sandbox_policy.type`、`collaboration_mode.mode`）、`response_item`（`message` 帶 `role` 與 `phase`=`commentary`/`final_answer`、
  `function_call`／`custom_tool_call` 與對應 `*_output`，以 `call_id` 配對）、`world_state`、`token_usage_record`。
- `task_complete` 的鍵 [本機]：`turn_id`、`last_agent_message`、`started_at`、`completed_at`、`duration_ms`、`time_to_first_token_ms`；有錯誤時多 `error` [src]。
  `turn_aborted` 的鍵：`turn_id`、`reason`、時間欄位。

### 4.2 四種情況的痕跡

先找**最後一個 `task_started`**，看它之後有什麼：

| 情況 | rollout 痕跡 | 怎麼確認 |
|---|---|---|
| **正常結束 turn**（含提前結束） | 同 `turn_id` 有 `task_complete`，沒有 `error` 鍵；前面是 `response_item` `message` `phase: final_answer` | 「提前」與否只能看 `last_agent_message` 的內容（還列著剩下的步驟、說「接下來會…」），log 沒有欄位標示 |
| **需求／plan 確認** | 也是 `task_complete`。default 模式沒有 `request_user_input` 工具（只有 Plan 模式有）[src] `protocol/src/config_types.rs#L700-L702`，模型問問題就是一則 `final_answer` 後結束 turn。Plan 模式下若用工具問：最後是一筆 `function_call` `name: request_user_input`、沒有對應 output、沒有 `task_complete` | 看 `last_agent_message` 是否以問題結尾；看 `turn_context.collaboration_mode.mode` 是否 `plan` |
| **權限等待** | 核准請求本身不落盤。痕跡是：最後一個 turn 沒有 `task_complete`／`turn_aborted`，最後一筆 `function_call`（`exec_command`、`apply_patch` 等）沒有配對的 `*_output`。`turn_context.approval_policy` 是 `on-request`／`untrusted`／`granular`（`never` 不會等） | process 還活著（`pgrep -af codex`）、檔案 mtime 停住 = 正在等。等完後：拒絕（「No, continue without running it」）→ output 帶 `rejected by user` 類文字、turn 繼續 [src] `core/src/tools/approvals.rs#L443-L473`；選「No, and tell Codex what to do differently」（Cancel）→ `ReviewDecision::Abort` → turn 被中止 [src] `tui/src/bottom_pane/approval_overlay.rs#L827-L828`，rollout 應出現 `turn_aborted`（reason 未實測） |
| **CLI 異常退出** | 和權限等待一樣：最後一個 turn 沒有收尾事件；最後幾筆可能是 `function_call` 沒 output，或 `token_count`／`response_item` 之後就斷了。若是不可重試的 API 錯誤而非崩潰，則是 `task_complete` **帶 `error`**（錯誤訊息本身的 `Error` 事件不落盤） | process 不在了 = 異常退出。exec 另外看 exit code（≠0 是 failed／interrupted／error）|
| 使用者按 Esc 中斷 | `turn_aborted`，`reason: interrupted` [本機有 3 筆] | — |

判斷順序（給下一張分類實例的 ticket 用）：

```
最後一個 task_started 之後
├─ 有 turn_aborted        → 中斷（看 reason）
├─ 有 task_complete
│   ├─ 帶 error           → 錯誤收尾（API／用量／compaction）
│   └─ 不帶 error         → 模型自己結束：讀 last_agent_message
│                            ├─ 問問題／要確認   → 需求確認
│                            ├─ 說還有事沒做     → 提前結束
│                            └─ 交代完成         → 正常結束
└─ 兩者都沒有
    ├─ process 還在       → 等權限（或 Plan 模式等回答；看最後一筆 function_call 的 name）
    └─ process 不在       → CLI 異常退出（或被 kill）
```

### 4.3 讀 log 時的陷阱

- **subagent 的 rollout 會帶父 thread 的歷史**：檔頭有兩筆 `session_meta`（第一筆 `thread_source: subagent`，第二筆是父 thread），
  父 thread 當時進行中的 `task_started` 會被複製進來、沒有收尾。判斷「最後一個 turn 有沒有收尾」只看最後一個 `task_started`，不要拿「有 `task_started` 沒配對」直接當異常 [本機]。
- **檔尾不一定是 turn 事件**：本機有 2 個檔在 `task_complete` 之後幾小時又寫了 `thread_settings_applied`（重新打開 thread 時）。要找最後的 turn 事件，不是最後一行 [本機]。
- `Stop` hook 擋下後續跑的提示會寫成一則 `message` 進同一個 turn，`HookStarted/Completed` 本身不落盤 [src] `core/src/session/turn.rs#L680-L690`、`rollout/src/policy.rs#L193-L194`。
- `turn_context.approval_policy` 可能是字串（`never`、`on-request`）或物件（`{"granular": {...}}`）[本機]。

## 查不到／沒做的

- 「Cancel 核准」實際寫進 rollout 的 `turn_aborted.reason` 是哪個值：依原始碼推到 `TurnAborted`，沒有實測。
- `/goal` 在 `codex exec` 下的行為。
- 等權限與 CLI 崩潰無法只靠 rollout 區分；本機也沒有現成的崩潰樣本可對照。
- 提前結束的根因（模型端或 CLI 端某版改動）：issue 都沒有維護者說明。
- 本機最近實例的分類是另一張 ticket，這裡不做。
