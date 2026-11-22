# Commit 共同作者要不要改用 git hook

研究日期：2026-11-21。對應 [評估：commit 共同作者改用 git hook 強制](https://github.com/henry5720/dotfiles/issues/373)。各 agent 的身分 email 與 attribution 設定入口見 [#153 的研究](agent-commit-attribution.md)。

## 結論

不用 hook，也不累積名單：**誰改的誰 commit，每顆 commit 用各家官方 attribution 標自己**。Claude 改、Codex 審＋修時，Claude 的 commit 標 Claude、Codex 的 commit 標 Codex。這個 repo 用 merge commit 合 PR（例如 `b97a5c6 Merge pull request #374`），每顆 commit 的 trailer 都留在歷史裡。

| 要做到的事 | 做法 | 狀態 |
|---|---|---|
| Claude 下的 commit 標 Claude | 官方 `attribution.commit`（[settings-reference](https://code.claude.com/docs/en/settings-reference#attribution)），釘在 [`modify_settings.json.tmpl`](../../home/dot_claude/modify_settings.json.tmpl) | 已設定 |
| Codex 下的 commit 標 Codex | 官方 git-attribution extension，加 [`codex-commit-attribution.md`](../../home/.chezmoitemplates/codex-commit-attribution.md) 補同一個字串 | 已設定 |
| OpenCode 下的 commit | 正文標記 `Generated with OpenCode.`（官方沒有，見 #153） | 已設定 |
| 一顆 commit 同時標好幾個 agent | **不做**，拿掉 `agent-coauthors` 名單機制 | #377、henry5720/agent-config#117 |

已知漏洞：Codex 只審不動手、由 Claude 照建議修並 commit 時，Codex 不會被標。要標就讓提建議的 agent 自己修、自己 commit。

## 為什麼不用 hook

- **沒有成熟做法。** [block/aittributor](https://github.com/block/aittributor) 是 `prepare-commit-msg` hook，README〈Known limitations〉寫「Only one agent is attributed per commit」。[git-ai](https://github.com/git-ai-project/git-ai) 用 agent hook 記每次改檔、寫進 Git Notes，不產生 `Co-authored-by`，GitHub 不顯示頭像。
- **git hook 不知道誰參與過。** 它只看得到 commit 當下的環境變數（Claude `CLAUDE_CODE_CHILD_SESSION`、Codex `CODEX_THREAD_ID`、OpenCode `OPENCODE`），這些會被子行程繼承；改過檔但沒 commit 的 agent，它無從得知。
- **要做穩得兩邊都裝。** agent hook（PostToolUse）記「誰改過檔」，三家各一份，Bash 改檔還抓不到；git hook 在 commit 時合併。為了「A 改、B commit」這種可以改成各自 commit 的情況，不值得。
- **hooksPath 範圍不夠。** [`config-code`](../../home/dot_config/git/config-code) 的 `core.hooksPath` 只透過 `includeIf "gitdir:~/code/"` 生效，這個 repo 和 herdr worktree 都拿不到；husky 這類 repo 也會蓋掉它。

## 查過、之後用得到的事實

- `prepare-commit-msg` 不受 `--no-verify` 影響（[githooks(5)](https://git-scm.com/docs/githooks#_prepare_commit_msg)）；git 2.53.0 實測 `-m`、`--amend`、merge、`merge --squash` 都會觸發。
- `git interpret-trailers --if-exists addIfDifferent`（[文件](https://git-scm.com/docs/git-interpret-trailers)）實測：key 不分大小寫，value 要一字不差；同 email 不同 name 兩行都留。
- Claude 的 `attribution.commit` 是給模型的指示，不是 Claude Code 改 message；CLAUDE.md 的 attribution 規則優先（[settings-reference](https://code.claude.com/docs/en/settings-reference#attribution)）。
- Codex 環境變數出自 [`shell_environment.rs`](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/protocol/src/shell_environment.rs#L173-L175)；OpenCode 出自 [`index.ts`](https://github.com/anomalyco/opencode/blob/v1.18.35/packages/opencode/src/index.ts#L75-L77)。兩者只讀 source，未實測。

版本：Claude Code 2.1.330、codex-cli 0.171.0、opencode 1.18.35、git 2.53.0。
