# Commit 共同作者改用 git hook 的評估

研究日期：2026-11-21。對應 [評估：commit 共同作者改用 git hook 強制](https://github.com/henry5720/dotfiles/issues/373)。各 agent 的身分 email 與 attribution 設定入口已在 [#153 的研究](agent-commit-attribution.md) 查過，這裡只補 hook 相關的部分。

## 結論

兩者並用：「把名單和提交者的標記合併進 message」交給 `prepare-commit-msg` git hook，「誰有參與、要不要記進名單」仍由 agent 照規則寫。

hook 能做的是把字串放進 message 並去重：`--no-verify`、`--amend`、merge、`merge --squash` 都會觸發它，`git interpret-trailers --if-exists addIfDifferent` 在字串一致時也能去重。hook 不知道的是誰參與過。環境變數只能指出 commit 是在哪個 agent 的子行程裡跑的，而且會被子行程繼承；沒執行 commit、但改過檔的 agent，hook 只能從名單檔得知，名單還是要 agent 自己寫。

| 步驟（[instructions.md](#現況)） | 交給誰 | 理由 |
|---|---|---|
| 2. 留下貢獻後把自己加進名單 | 維持規則 | 「有沒有實際貢獻」只有 agent 知道，hook 判斷不了 |
| 3. commit 前合併名單、本次提交者、既有標記 | **改 git hook** | 純字串處理；hook 在 `--no-verify` 下也會跑，比靠 agent 記得可靠 |
| 4. 提交後驗證 | 規則保留，但會很少失敗 | 有 hook 之後主要防 hook 沒生效的 repo（見下面的 hooksPath 範圍） |
| 5. 全部提交後刪名單 | 維持規則 | 部分提交時要不要留名單，hook 判斷不了 |

不建議改用 agent 自己的 hook（Claude／Codex 的 PreToolUse、OpenCode plugin）去改寫 `git commit` 指令：三家要各寫一份，而且要解析 shell 指令裡的 `-m`、heredoc；Codex 官方文件也說 tool hook 不是完整的強制手段。

## 現況

- 全域規則 `~/.claude/CLAUDE.md` L40–42〈Commit 共同作者〉只有一行：commit 前讀 `~/.config/agent-commit/instructions.md`。兩個檔的實體都在 agent-config（`~/.config/skillshare/instructions/agents-md/AGENTS.md`、`~/.config/skillshare/instructions/agent-commit/instructions.md`），不在這個 repo。
- `instructions.md` 的做法：名單檔放在 `git rev-parse --git-path agent-coauthors`（每個 worktree 一份，例如這個 worktree 是 `~/.local/share/chezmoi/.git/worktrees/research-373-commit-coauthor-hook/agent-coauthors`），agent 結束前把自己的標記加進去，commit 前合併，提交後用 `git show -s --format=%B HEAD` 驗證，全部提交後刪掉。
- 各 agent 的署名設定：
  - Claude Code：[`home/dot_claude/modify_settings.json.tmpl`](../../home/dot_claude/modify_settings.json.tmpl) L7 把 `attribution.commit` 釘成 `Co-Authored-By: Claude Code <noreply@anthropic.com>`。
  - Codex：[`home/.chezmoitemplates/codex-commit-attribution.md`](../../home/.chezmoitemplates/codex-commit-attribution.md) 由 [`home/dot_codex/modify_private_config.toml.tmpl`](../../home/dot_codex/modify_private_config.toml.tmpl) L48 塞進 `developer_instructions`。
  - OpenCode：[`home/dot_config/opencode/modify_private_opencode.json.tmpl`](../../home/dot_config/opencode/modify_private_opencode.json.tmpl) 讓 `instructions` 指向 `~/.config/opencode/commit-instructions.md`。
  - 測試：以上三項由 [`script/tests/test_commit_attribution.py`](../../script/tests/test_commit_attribution.py) 驗。
- 全域 git hooks：[`home/dot_config/git/config`](../../home/dot_config/git/config) L13–14 用 `includeIf "gitdir:~/code/"` 帶入 [`config-code`](../../home/dot_config/git/config-code)，它在 L14–15 設 `core.hooksPath = ~/.config/git/hooks`。目錄裡只有 codegraph 的 `post-checkout`、`post-merge`。L10–13 寫明 repo 自己設了 `core.hooksPath`（husky）時 local 會贏，而且是靜默的。
  - **實測：chezmoi repo 本身不在 `~/code` 底下，所以拿不到這個 hooksPath。** 在這個 worktree 跑 `git config --get core.hooksPath`，沒有輸出。

## 1. hook 怎麼知道是誰在 commit

git hook 會繼承呼叫 `git commit` 那個行程的環境變數（[githooks(5)](https://git-scm.com/docs/githooks) 只列出 git 自己 export 的 `GIT_DIR` 等；其餘是一般的行程繼承）。三家都會在 shell 子行程設可以辨識的變數：

| agent | 變數 | 出處 | 會誤判的情況 |
|---|---|---|---|
| Claude Code 2.1.330 | `CLAUDECODE=1`；`CLAUDE_CODE_CHILD_SESSION=1` | [env-vars](https://code.claude.com/docs/en/env-vars)：`CLAUDECODE` 在 Bash／PowerShell tool、tmux session、hook、status line、stdio MCP 子行程都會設，「IDE extensions also set this in their integrated terminals」；`CLAUDE_CODE_CHILD_SESSION` 只有 Claude Code 自己開的子行程會設，IDE 不會 | 用 `CLAUDECODE` 判斷時，人在 IDE 終端機或 Claude 開的 tmux 裡自己 commit，也會被算成 Claude。要用 `CLAUDE_CODE_CHILD_SESSION` |
| Codex 0.171.0 | `CODEX_THREAD_ID`；`CODEX_SESSION_ID`、`CODEX_VERSION` | [`shell_environment.rs` L173–175](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/protocol/src/shell_environment.rs#L173-L175) 插入 `CODEX_THREAD_ID`（`include_only` 也擋不掉，見 [`exec_env.rs` L30–31](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/core/src/exec_env.rs#L30-L31)）；[`exec_env.rs` L41–50](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/core/src/exec_env.rs#L41-L50) 的 `inject_session_env` 設另外兩個，呼叫處是 [`unified_exec/process_manager.rs` L1499](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/core/src/unified_exec/process_manager.rs#L1499) 和 [`tasks/user_shell.rs` L171](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/core/src/tasks/user_shell.rs#L171) | `user_shell.rs` 是使用者在 TUI 自己打的 shell 指令，所以人透過 Codex 下的 commit 也帶 `CODEX_SESSION_ID`。只看 source，未實測 |
| OpenCode 1.18.35 | `OPENCODE=1`、`AGENT=1`、`OPENCODE_PID` | [`packages/opencode/src/index.ts` L75–77](https://github.com/anomalyco/opencode/blob/v1.18.35/packages/opencode/src/index.ts#L75-L77) 設在 OpenCode 自己的 `process.env`；shell tool 用 `{...process.env, ...extra.env}` 開子行程（[`tool/shell.ts` L416–426](https://github.com/anomalyco/opencode/blob/v1.18.35/packages/opencode/src/tool/shell.ts#L416-L426)） | 從 OpenCode 行程衍生出去的任何東西都帶這幾個變數。只看 source，未實測 |

本機實測（Claude Code 2.1.330，在 `mktemp -d` 建的拋棄式 repo，`.git/hooks/prepare-commit-msg` 印出變數）：

```text
$ git commit -q --allow-empty -m x
hook sees CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1 CODEX_THREAD_ID=unset OPENCODE=unset
$ env -u CLAUDECODE git commit -q --allow-empty -m y
hook sees CLAUDECODE=unset CLAUDE_CODE_CHILD_SESSION=1 CODEX_THREAD_ID=unset OPENCODE=unset
```

同一個 shell 還有一個 `AI_AGENT=claude-code_2-1-330_agent`，但 env-vars 文件沒有這個變數，不要依賴它。

**繼承造成的誤判**：這些變數會繼承給所有子孫行程。Claude 的 Bash tool 裡如果又啟動 `codex exec`，Codex 的 shell 會同時帶 `CLAUDE_CODE_CHILD_SESSION` 和 `CODEX_THREAD_ID`。變數只說「祖先裡有誰」，沒說誰在最內層，所以 hook 要訂優先順序：有 Codex 或 OpenCode 的變數時，不把 `CLAUDE_CODE_CHILD_SESSION` 算進去（Claude 很少被 Codex／OpenCode 當子行程啟動）。這是推論，沒有實測巢狀情況。

**沒執行 commit 的 agent**：環境變數只告訴 hook 誰在跑 `git commit`。A 改檔、B commit 的情況，hook 只能從名單檔得知 A，所以 `instructions.md` 步驟 2 一定要保留。agent 自己的 Stop hook 可以在結束時自動把自己加進名單，但它判斷不了「有沒有實際貢獻」：worktree 有修改不代表是這個 agent 改的。這次不建議做。

## 2. 跟各 agent 原生署名會不會重複或打架

### git 這邊的行為

[githooks(5)](https://git-scm.com/docs/githooks#_prepare_commit_msg)：`prepare-commit-msg` 在預設 message 準備好、開編輯器之前跑，第二個參數是 message 來源（`message`、`template`、`merge`、`squash`、`commit` + commit 名稱）；「it is not suppressed by the `--no-verify` option」。`commit-msg` 則會被 `--no-verify` 跳過。

本機實測（git 2.53.0，拋棄式 repo，`core.hooksPath` 指到暫存目錄；hook 跑 `git interpret-trailers --in-place --if-exists addIfDifferent --trailer "Co-authored-by: Codex <noreply@openai.com>" "$1"`）：

| 指令 | hook 拿到的參數 | 結果 |
|---|---|---|
| `git commit -m first -m "Co-Authored-By: Claude Code <…>\nCo-authored-by: Codex <…>"` | `.git/COMMIT_EDITMSG message` | Codex trailer 只出現一次（已經有，沒再加） |
| `git commit -am second --no-verify` | `.git/COMMIT_EDITMSG message` | hook 有跑、trailer 有加；`commit-msg` 沒跑 |
| `git commit --amend --no-edit` | `.git/COMMIT_EDITMSG commit HEAD` | trailer 維持一次 |
| `git commit -a -C HEAD` | `.git/COMMIT_EDITMSG commit HEAD` | trailer 維持一次 |
| `git merge --no-ff side -m "merge side"` | `.git/MERGE_MSG merge` | merge commit 有 trailer |
| `git merge --squash side2` 再 `git commit --no-edit` | `.git/COMMIT_EDITMSG squash` | trailer 加在 squash message 尾端 |

hook 碰不到的 commit：GitHub 網頁的 squash／rebase merge，以及 Codex 透過 GitHub app／plugin 建的 commit（[`world_state.rs`](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/ext/git-attribution/src/world_state.rs) 的 enabled 指引要模型把 trailer 寫進工具的 `message` 參數）。這些不在本機跑 `git commit`。`git rebase`、`cherry-pick` 會不會觸發這個 hook 沒測。

### 去重的規則

[git-interpret-trailers(1)](https://git-scm.com/docs/git-interpret-trailers)：`addIfDifferent` 是「a new trailer will be added only if no trailer with the same (<key>, <value>) pair is already in the input」。key 大小寫文件沒寫，實測：

```text
$ printf 'x\n\nCo-Authored-By: Codex <noreply@openai.com>\n' \
  | git interpret-trailers --if-exists addIfDifferent --trailer "Co-authored-by: Codex <noreply@openai.com>"
x

Co-Authored-By: Codex <noreply@openai.com>          # key 不分大小寫，沒有重複

$ printf 'x\n\nCo-authored-by: Claude Opus 5.5 <noreply@anthropic.com>\n' \
  | git interpret-trailers --if-exists addIfDifferent --trailer "Co-authored-by: Claude Code <noreply@anthropic.com>"
x

Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>
Co-authored-by: Claude Code <noreply@anthropic.com>  # 同 email、不同 name，兩行都留
```

所以 key 不分大小寫，value 要一字不差才會去重。`instructions.md` 要的是「按 email 去重」，`addIfDifferent` 做不到；hook 要自己先比 email。另外兩個實測：只有 subject 的 message 會自動補空行；編輯器範本的 `#` 註解行會留在 trailer 後面，之後由 git 清掉。

### 各家會不會跟 hook 打架

| agent | 原生署名怎麼加 | 跟 hook 的關係 |
|---|---|---|
| Claude Code | `attribution.commit` 是給模型的指示，不是 Claude Code 自己改 message：[settings-reference](https://code.claude.com/docs/en/settings-reference#attribution) 說「Claude Code tells Claude that your own instructions about attribution, such as a CLAUDE.md or memory rule, take precedence over these commit and PR lines」（managed settings 例外）。本 session 的 system reminder 也是用文字叫模型在 message 結尾加 `Co-Authored-By: Claude Code <noreply@anthropic.com>` | 這裡已經把字串釘成 `Claude Code`，跟 hook 加的一致時，`addIfDifferent` 會去重。沒釘的機器預設 name 是模型名（如 `Claude Opus 5.5`），會跟 hook 的 `Claude Code` 重複 → hook 要按 email 比對 |
| Claude Code `includeGitInstructions` | `false` 會拿掉 Bash tool 說明裡內建的 commit／PR 指引和 git status 快照（[settings-reference](https://code.claude.com/docs/en/settings-reference#includegitinstructions)；`CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1` 優先） | 跟 hook 無關，不用動。文件沒寫它會不會一起拿掉 attribution，未驗 |
| Codex | 原生 git-attribution extension 只在 Codex backend policy 為 enabled 時注入指引，字串是 `Co-authored-by: Codex <noreply@openai.com>`，並要求「Do not add duplicate attribution」（[`world_state.rs` L18–27](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/ext/git-attribution/src/world_state.rs#L18-L27)）。這台 policy 的狀態見 [#153 的追查](agent-commit-attribution.md#追查本機-codex-policy-與使用者可操作入口)。這個 repo 另外用 `developer_instructions` 給同一個字串 | 字串一致，`addIfDifferent` 會去重。policy 從 true 變 false 時會注入「Ignore any earlier instructions requiring Codex attribution and do not add it」，只管模型，管不到 git hook，所以 hook 仍會加上去；要不要尊重這個 policy，開 ticket 時要決定 |
| OpenCode | 沒有原生署名（[#153](agent-commit-attribution.md#opencode官方-logo-身分尚未確認)）；這裡用正文標記 `Generated with OpenCode.` | 這不是 trailer，`interpret-trailers` 不管它；hook 要用 `grep -qxF` 判斷有沒有再補，而且要放在 trailer 區塊前面 |

結論：只要 hook 跟各 agent 用**同一個字串**，並且按 email 比對，就不會重複，也不會蓋掉。hook 用 `addIfDifferent` 只會追加，不會刪掉 agent 寫的東西；`replace`、`doNothing` 才會蓋掉或略過，hook 不要用。

### agent 自己的 hook

三家都能在 shell 指令執行前改寫它，但這次不建議用：

- Claude Code：PreToolUse 回 `updatedInput` 可以換掉 tool 參數，`if` 可以寫 `Bash(git *)` 只對 git 觸發（[hooks](https://code.claude.com/docs/en/hooks)）；用 Monitor tool 啟動的指令 `updatedInput` 不生效。
- Codex：`hooks.json` 或 `config.toml` 的 `[hooks]`，預設開啟；PreToolUse 可以回 `updatedInput`（Bash 要有 `command` 字串），但文件說「Treat tool hooks as a useful guardrail, not a complete enforcement boundary」「Some specialized tool paths can opt out of the default hook path」（[Codex hooks](https://learn.chatgpt.com/docs/hooks)；原始碼 [`hooks/src/events/pre_tool_use.rs`](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/hooks/src/events/pre_tool_use.rs)）。
- OpenCode：plugin 的 `tool.execute.before` 拿得到可以改的 `output.args`，`shell.env` 可以加環境變數（[`packages/plugin/src/index.ts` L266–273](https://github.com/anomalyco/opencode/blob/v1.18.35/packages/plugin/src/index.ts#L266-L273)）。

三家都要從 shell 字串裡找出 `git commit` 的 message 再改，`-m`、`-F`、heredoc、`&&` 串接都要處理，還要各寫一份。git hook 拿到的是已經組好的 message 檔，一份就涵蓋三家。OpenCode 的 `shell.env` 可以設一個比 `OPENCODE` 更明確的變數，但 `OPENCODE=1` 已經夠用。

## 3. 建議與要另開的 ticket

建議兩者並用。這張不改碼，以下兩張另開：

### Ticket A（dotfiles）：全域 `prepare-commit-msg` 合併共同作者

- 新增 `home/dot_config/git/hooks/executable_prepare-commit-msg`，跟同目錄的 codegraph hook 一樣用 `#!/bin/sh`。原生 Termux 沒有 `/bin/sh`（AGENTS.md），要不要改成 `.tmpl` 用 `lookPath "sh"`，兩支既有 hook 一起決定。
- 行為：
  1. 讀 `git rev-parse --git-path agent-coauthors`，檔案不存在就略過。
  2. 依環境變數加上本次提交者：`CODEX_THREAD_ID` → Codex；`OPENCODE` → OpenCode；兩者都沒有且 `CLAUDE_CODE_CHILD_SESSION=1` → Claude Code。都沒有 = 人自己 commit，只合併名單。
  3. trailer 用 `git interpret-trailers --in-place --if-exists addIfDifferent`，加之前先比 email，已經有同 email 的就不加；正文標記用 `grep -qxF` 判斷。
  4. 不刪名單、不擋 commit：hook 失敗時要 `exit 0`，因為非零會讓 commit 中止（githooks(5)）。
- 要先決定：`core.hooksPath` 目前只對 `~/code` 生效，這個 chezmoi repo（`~/.local/share/chezmoi`）和 herdr worktree 都拿不到。要全部 repo 生效就把 hooksPath 搬到 `config`，影響範圍會擴大到 codegraph 那兩支 hook，也會讓其他 repo 原本的 `.git/hooks/` 失效（`config-code` L6–8 只清查過 `~/code`）。
- husky 這類 repo 的 local `core.hooksPath` 會搶走全域設定（`config-code` L10–13），hook 不會跑；這種 repo 靠 `instructions.md` 的驗證步驟補。
- 測試：`script/tests/` 加單元測試，在暫存 repo 驗 `-m`、`--no-verify`、`--amend`、merge、squash、同 email 不同 name、OpenCode 正文標記、名單不存在。另外驗 Termux、Windows 不會部署錯（Windows 白名單預設不放行，確認一下）。
- 要不要尊重 Codex backend 的 disabled policy：要決定。hook 讀不到 policy。

### Ticket B（agent-config）：`instructions.md` 配合 hook

- 步驟 3 改成「有 hook 時由 hook 合併；驗證時發現沒合併（hook 沒裝或被 husky 搶走），照原本手動合併」。
- 步驟 2、4、5 不變。
- `home/.chezmoitemplates/codex-commit-attribution.md` 和 OpenCode 的 commit 指引裡「合併待提交參與者」那句同步改。

## 未查到或未驗

- Codex、OpenCode 的環境變數只看 source（0.171.0、1.18.35 的 tag），沒有在兩家的 shell 裡實際跑 `env`。
- 巢狀情況（Claude 啟動 Codex、herdr pane 有沒有繼承啟動者的變數）沒實測。
- `git rebase`、`cherry-pick`、`git commit -t` 時 `prepare-commit-msg` 的行為沒測。
- `includeGitInstructions: false` 會不會連 attribution 指示一起拿掉：文件沒寫，沒測。
- OpenCode 官方 plugin 文件（[plugins](https://opencode.ai/docs/plugins/)、[build/plugins](https://opencode.ai/docs/build/plugins)）沒有列 hook 事件，只能看 source。

## 出處

- git：[githooks(5)](https://git-scm.com/docs/githooks)、[git-interpret-trailers(1)](https://git-scm.com/docs/git-interpret-trailers)
- Claude Code 2.1.330：[settings-reference](https://code.claude.com/docs/en/settings-reference)（`attribution`、`attribution.commit`、`includeGitInstructions`）、[env-vars](https://code.claude.com/docs/en/env-vars)、[hooks](https://code.claude.com/docs/en/hooks)
- Codex 0.171.0（tag `rust-v0.171.0`，commit `295eca9`）：[Codex hooks](https://learn.chatgpt.com/docs/hooks)（`developers.openai.com/codex/hooks` 308 轉到這裡）、上文各 source 連結
- OpenCode 1.18.35（tag `v1.18.35`）：[plugins](https://opencode.ai/docs/plugins/)、上文各 source 連結
- 先前研究：[agent-commit-attribution.md](agent-commit-attribution.md)（#153）、agent-config 的 `docs/research/agent-instructions-best-practices.md` L82、L136
- 本機指令：`claude --version` → `2.1.330 (Claude Code)`；`codex --version` → `codex-cli 0.171.0`；`opencode --version` → `1.18.35`；`git --version` → `git version 2.53.0`
