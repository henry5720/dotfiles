# Codex 與 Claude 的權限設定：哪個組合最接近 Auto Mode

查證日期：2026-10-09。本機 `codex-cli 0.161.0`、`2.1.295 (Claude Code)`，Ubuntu（非 WSL）。對應 issue #138（map #137）。

**結論**

- Codex 最接近 Claude Auto Mode 的組合是 `approval_policy = "on-request"` + `sandbox_mode = "workspace-write"` + `approvals_reviewer = "auto_review"`。
  這正好就是 `codex --approve-for-me` 這個 flag 展開後的三個 key（原始碼測試寫死了這三行）[src-cli]。
- 兩邊的機制不一樣：Claude 是「工作目錄內的讀寫直接放行，其餘每個動作都給 classifier 看」；Codex 是「sandbox 內的指令直接放行、**不經 reviewer**，
  只有要越出 sandbox（寫 workspace 外、上網、寫 `.git`、MCP 需核准的呼叫）才送 reviewer」[cx-ar]。所以 Codex 這組的安全邊界主要是 sandbox，reviewer 只看越界請求。
- `approval_policy = "never"` 不是 Auto Mode 的對應：它不會停，但越界的動作直接失敗回給模型，沒有任何審查；配 `danger-full-access` 就等於 Claude 的 `bypassPermissions`。
- Claude 可以：`~/.claude/settings.json` 寫 `"permissions": { "defaultMode": "auto" }`。**只有 user settings（或 managed／`--settings`）有效**，寫在專案的 `.claude/settings*.json` 會被忽略 [cc-modes]。
  2.1.283 起互動式 terminal 的內建預設本來就是 `auto`，所以釘這個 key 的作用是「明確化、不受內建預設規則變動影響」，不是開啟新功能。
- 兩邊都能用 `modify_` 只釘這幾個 key。Codex 側有一個要注意的地方：TUI 切換 reviewer 時會把 `approvals_reviewer` **寫回** `config.toml` [src-tui]，釘了之後在 TUI 裡切換會造成 `chezmoi diff` 有差異，下次 apply 被蓋回。

來源標示：**[實測]** 本機跑出來的；**[官方]** developers.openai.com／learn.chatgpt.com、code.claude.com 文件；**[原始碼]** `openai/codex` tag `rust-v0.161.0`；**[help]** 本機 `--help` 輸出。

## 1. Codex 0.161 的三個 key

### 1.1 `approval_policy`（`-a/--ask-for-approval`）

| 值 | 什麼時候停下問人 | 來源 |
|---|---|---|
| `on-request`（預設） | sandbox 允許的指令直接跑；要越出 sandbox（寫 workspace 外、要網路）、模型主動要求提權、MCP 有 destructive annotation 的呼叫時發核准請求，交給 `approvals_reviewer` 決定給誰 | [官方 cx-sec]、[原始碼 src-proto] |
| `on-failure` | 已不是獨立的值：0.161 原始碼裡是 `on-request` 的 serde alias | [原始碼 src-proto] `#[serde(alias = "on-failure")]` |
| `never` | 永遠不問。越界的動作直接失敗，錯誤回給模型、不升級給人；sandbox 仍然限制能做什麼 | [help]、[原始碼 src-proto] |
| `untrusted` | 已退役。寫在 `config.toml` 會讓設定載入失敗（`UnsupportedUntrustedApprovalPolicyError`）；只剩「專案被標成 untrusted」時內部使用 | [官方 cx-sec]「can prevent either client from starting」、[原始碼 src-cfg] |
| `{ granular = { ... } }` | 細分五類（`sandbox_approval`、`rules`、`skill_approval`、`request_permissions`、`mcp_elicitations`）。`true` 的類別照常提示，`false` 的自動拒絕 | [原始碼 src-proto]、[官方 cx-sec] |

本機 `codex --help` 的 `-a` 只列 `on-request`、`never` 兩個值 [help]。沒設定時：專案 trusted → `on-request`；專案 untrusted → 內部 untrusted；其他 → `on-request` [原始碼 src-cfg]。

### 1.2 `sandbox_mode`（`-s/--sandbox`）

| 值 | 擋什麼 | 來源 |
|---|---|---|
| `read-only` | 不能寫檔，不能上網 | [help]、[實測] |
| `workspace-write` | 只能寫 workspace（和設定的 writable roots）；`.git`、`.agents`、`.codex` 即使在 workspace 內也唯讀；預設沒網路，要 `[sandbox_workspace_write] network_access = true` 才開 | [官方 cx-sec]、[實測] |
| `danger-full-access` | 沒有 sandbox | [官方 cx-sec] |

沒設定時：目錄有 trust 決定（trusted 或 untrusted）→ `workspace-write`，否則 → `read-only` [原始碼 src-toml `derive_permission_profile`]。

本機實測（`codex sandbox -c 'sandbox_mode="workspace-write"' -- sh -c ...`，在一個暫存目錄）：

```
ws-ok          # workspace 內 touch 成功
home-blocked   # $HOME 寫不進去
git-blocked    # .git/ 底下寫不進去
net-blocked    # curl example.com 解析不到 host
```

不帶 `-c` 時（`/tmp` 底下沒有 trust 決定）連 workspace 都寫不進去：`touch: cannot touch './in-ws': Read-only file system` [實測]，和上面「沒設定 → read-only」一致。

**對長任務的影響**：`workspace-write` 下 `git commit`、`npm install`、`gh` 這類寫 `.git` 或要網路的指令一定會越界 → 每次都發核准請求。reviewer 是 `user` 就每次停下來問人；是 `auto_review` 就交給 reviewer。

### 1.3 `approvals_reviewer`

| 值 | 行為 | 來源 |
|---|---|---|
| `user`（預設） | 核准請求給人 | [原始碼 src-cfgtypes]、[官方 cx-sec] |
| `auto_review` | 核准請求先給一個 reviewer subagent，依風險決定核准或拒絕。舊值 `guardian_subagent` 仍接受 | [原始碼 src-cfgtypes] |

`auto_review` 的細節 [官方 cx-ar]：

- **只在 approval 是互動式時有效**（`on-request` 或 granular）。`never` 時「there is nothing to review」。
- **sandbox 內的例行動作不經過它**；會送審的是提權的 shell 指令、被 sandbox 擋的網路請求、寫 writable roots 以外、需要核准的 MCP／app 工具呼叫。
- 預設擋：把私密資料或 credential 送到不信任的地方、探測 credential／token／cookie、大範圍或持久地削弱安全設定、有重大不可逆風險的破壞性動作。
- 被拒時：理由回給主 agent，主 agent 不能繞路做同一件事，只能換「實質上更安全」的做法，或停下來問人。逾時另外回報，不算「不安全」。
- **斷路器**：同一個 turn 連續 3 次拒絕，或最近 50 次審查裡 10 次拒絕，就中止這個 turn。任何一次非拒絕會重置連續計數。人可以用 TUI 的 `/approve` 對單一被拒動作放行一次重試（重試仍要過 reviewer）。
- 自訂政策：`config.toml` 的 `[auto_review].policy`；企業用 managed requirements 的 `guardian_policy_config`，優先於本機設定。
- 文件明說不是確定性的安全保證。

`--approve-for-me`（隱藏別名 `--not-so-yolo`）在 `codex` 與 `codex exec` 都有 [help]，展開成 [原始碼 src-cli]：

```
approvals_reviewer="auto_review"
approval_policy="on-request"
sandbox_mode="workspace-write"
```

它和 `--sandbox`、`--ask-for-approval`、`--dangerously-bypass-approvals-and-sandbox` 互斥 [原始碼 src-cli 測試 `approve_for_me_conflicts_with_explicit_interactive_permissions`]。
有 GitHub issue 提到舊版文件寫 auto-review「不支援 `codex exec`」，但 0.161 的 `codex exec --help` 有這個 flag，原始碼也有 root → exec 的傳遞測試 [src-cli `approve_for_me_defaults_propagate_from_root_to_exec`]。實際在 `codex exec` 裡 reviewer 跑起來的行為我沒有實測。

## 2. 組合比較：誰最接近 Claude Auto Mode

Claude Auto Mode 的行為 [cc-modes]：讀取與工作目錄內的檔案編輯直接放行（protected paths 除外）；其餘動作（shell、網路、工作目錄外）全部先給 classifier；
classifier 預設擋 `curl | bash`、外送敏感資料、production deploy、force push、`git reset --hard` 等；被擋 3 次連續或 20 次累計就暫停 auto、改回問人；`-p` 模式沒人可問，就只是不執行、繼續跑。另外 Auto Mode 也會「推一下」Claude 少問澄清問題。

| 組合 | 會停下問人的時機 | 擋什麼 | 放什麼 | 風險 |
|---|---|---|---|---|
| **A. `on-request` + `workspace-write` + `auto_review`**（= `--approve-for-me`）**推薦** | 幾乎不問。被拒後主 agent 可能選擇停下問人；連續 3 次／50 次內 10 次被拒會中止 turn | sandbox 擋越界；reviewer 擋外洩、探 credential、削弱安全、不可逆破壞 | workspace 內任何指令（不審）；reviewer 核准的越界請求 | sandbox 內的指令完全不審（例如在 workspace 內 `rm -rf` 自己的檔案）；reviewer 是模型判斷，不是保證；斷路器會讓長任務整個 turn 中止 |
| B. `on-request` + `workspace-write` + `user`（官方「Auto」preset、本機現況） | 每次越界：commit、裝套件、上網、寫 workspace 外 | 同 A 的 sandbox | workspace 內任何指令 | 長任務一直停下來；這就是「無故停下」的權限提示來源 |
| C. `never` + `workspace-write` | 永遠不問 | sandbox 擋越界，失敗直接回給模型 | workspace 內任何指令 | 不會停，但 commit、上網、裝套件都做不到，模型可能繞路或卡住；沒有任何審查 |
| D. `never` + `danger-full-access`（≈ `--dangerously-bypass-approvals-and-sandbox`／`--yolo`） | 永遠不問 | 什麼都不擋 | 全部 | 等同 Claude `bypassPermissions`；官方標「not recommended」，只適合外部已隔離的環境 |
| E. `on-request` + `danger-full-access` + `auto_review` | 只在模型主動要求提權時 | reviewer 只看到模型主動送來的請求 | 沒有 sandbox，大部分指令根本不會產生核准請求 | 官方警告：`danger-full-access` 下「an action can avoid creating the boundary-crossing approval request that review requires」[cx-ar]，reviewer 形同虛設 |

推薦 A，因為它是唯一「不停下來、但越界動作仍有人（模型）審」的組合；C 也不停，但把審查換成直接失敗，長任務會卡在 commit 和網路上。

和 Claude Auto Mode 的差別（A 仍然不同的地方）：

- Claude 的 classifier 會看工作目錄外的每個 shell 指令；Codex 的 reviewer **不看 sandbox 內的指令**，靠 sandbox 擋。
- Claude 被擋太多次是「暫停 auto、改問人」；Codex 是「中止整個 turn」。
- 「少問澄清問題」的提示是 Claude Auto Mode 附帶的；Codex 這三個 key 都不處理需求確認、提前結束 turn 這兩類停下（map #137 Notes 的四種分類裡只處理第一種）。

## 3. Claude Code 2.1.295：`permissions.defaultMode`

值：`default`（CLI 上叫 Manual，也接受 `manual`）、`acceptEdits`、`plan`、`auto`、`dontAsk`、`bypassPermissions` [cc-modes]。本機 `claude --help` 的 `--permission-mode` choices 是 `acceptEdits, auto, bypassPermissions, manual, dontAsk, plan` [help]。

- **能寫進 `~/.claude/settings.json`**：`{"permissions": {"defaultMode": "auto"}}`。官方：「Start in auto mode: pass `--permission-mode auto`, or set `permissions.defaultMode` to `auto` in your user settings」[cc-modes]。
- 寫在 `.claude/settings.json` 或 `.claude/settings.local.json`（專案層）**不生效**，而且會讓 Claude 改用內建預設、連 user settings 的值也不用 [cc-modes]。
- 啟動順序：`--permission-mode` flag > settings 的 `defaultMode` > 內建預設。2.1.283 起互動式 terminal 的內建預設就是 `auto`；`claude -p`／Agent SDK 在會抓 feature flag 的 session 內建預設是 `default` [cc-modes]。
  所以：互動式 session 本機現在已經是 auto（本機 `~/.claude/settings.json` 沒有 `defaultMode`，只有 `permissions.allow` 一條規則 [實測 `jq`]）；**釘 `"auto"` 會讓 `-p` 也走 auto**（照上面的順序，settings 優先於內建預設），這點文件沒有對 `-p` 單獨舉例，我沒實測。
- auto 不可用時（模型不支援、`disableAutoMode`、server 端關掉）會退回 Manual 且不報錯 [cc-modes]。
- user settings 設成 `auto` 以外的值時，Pro／Max／Team 會問一次要不要改成 auto [cc-modes]；設成 `auto` 就沒有這個提示。

## 4. 能不能用 `modify_` 只釘這幾個 key

### Claude：可以，改動很小

`home/dot_claude/modify_settings.json.tmpl` 已經是 `jq` 只改一個 key 的寫法。加一行即可：

```jq
.enabledPlugins["chrome-devtools-mcp@claude-plugins-official"] = false
| .permissions.defaultMode = "auto"
```

`permissions` 是物件，`jq` 的路徑賦值會保留同物件內的 `allow` 等其他 key。Claude 自己不會把 `defaultMode` 寫回去（Shift+Tab 切換只影響當前 session，文件沒提到會持久化）——這點我只查到文件沒寫，沒有實測。

### Codex：可以，但要動兩處、並接受一個漂移來源

`home/dot_codex/modify_private_config.toml.tmpl` 的設計已經考慮到頂層 key：

1. 把 `approval_policy`、`sandbox_mode`、`approvals_reviewer` 加進 `managed_top_keys`（這樣舊值會從 preamble 被丟掉、不會重複）。
2. **`comparable()` 也要同步加**：它用的是另一份寫死的 tuple `("model", "model_provider", "model_reasoning_effort")`，不是 `managed_top_keys`。只改第一處的話，安全檢查會認為「非 managed 設定被改了」而讓 apply 失敗（例如現在的 `approvals_reviewer = "user"` 被換成 `auto_review`）。
3. 在輸出的 heredoc 裡、`model_reasoning_effort` 後面印出這三行。必須在第一個 table 之前，原因腳本註解已經寫了。

漂移來源：Codex TUI 切換 reviewer 時（`AppEvent::UpdateApprovalsReviewer`）會呼叫 `write_config_batch` 把 `approvals_reviewer` 寫回使用者的 `config.toml` [原始碼 src-tui]。
本機那行 `approvals_reviewer = "user"` 很可能就是這樣來的。釘住後如果在 TUI 裡切回 user，`chezmoi diff` 會出現差異，下次 apply 蓋回 `auto_review`。
在同一個檔案裡沒找到 TUI 持久化 `approval_policy`、`sandbox_mode` 的程式碼（只搜了 `tui/src/app/event_dispatch.rs`）。

另一個做法是不釘 key、改在啟動 alias 加 `--approve-for-me`；不選它，因為 `codex-work`／`codex-personal`、Herdr 開的 pane、`codex exec` 都要各自記得加，釘在 `config.toml` 才是單一來源。

## 5. 沒查到或沒實測的

- `auto_review` 在 `codex exec`（非互動）下被拒、觸發斷路器時的實際行為：只看了 flag 傳遞的原始碼測試，沒跑。
- Codex Linux sandbox 在 **Termux** 和 **WSL** 上能不能用：只在這台 Ubuntu 實測成功。`home/` 要支援 Termux，釘 `workspace-write` 前要另外驗。
- `claude -p` 讀 user settings 的 `defaultMode: "auto"` 是否真的進 auto：照文件的啟動順序推論，沒實測。
- reviewer 用哪個模型、走不走公司的 `codex-lb-gcp` provider、會不會多花 token：原始碼有 `resolve_review_model`，沒追。

## 來源

- [cx-sec] Agent approvals & security — https://developers.openai.com/codex/agent-approvals-security（308 轉到 https://learn.chatgpt.com/docs/agent-approvals-security）
- [cx-ar] Auto-review — https://developers.openai.com/codex/concepts/sandboxing/auto-review（https://learn.chatgpt.com/docs/sandboxing/auto-review）
- [cc-modes] Choose a permission mode — https://code.claude.com/docs/en/permission-modes
- [src-proto] https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/protocol/src/protocol.rs（`enum AskForApproval`、`GranularApprovalConfig`，約 986–1026 行）
- [src-cfgtypes] https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/protocol/src/config_types.rs（`enum ApprovalsReviewer`，約 183–203 行）
- [src-cfg] https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/core/src/config/mod.rs（approval 與 reviewer 預設值推導，約 3736–3777 行）
- [src-toml] https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/config/src/config_toml.rs（`derive_permission_profile`，約 840–860 行）
- [src-cli] https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/cli/src/main.rs（`approve_for_me_*` 測試，約 3174–3325 行）
- [src-tui] https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/tui/src/app/event_dispatch.rs（`AppEvent::UpdateApprovalsReviewer`，約 2607–2632 行）
- [help] 本機 `codex --help`、`codex exec --help`、`claude --help`（2026-10-09）
