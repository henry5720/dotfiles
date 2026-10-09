# 各 agent 的 commit attribution 與 GitHub 頭像

研究日期：2026-10-09。對應 [查各 agent 的 commit attribution 與 GitHub 頭像身分](https://github.com/henry5720/dotfiles/issues/153)。

## 結論

Claude 與 Codex 都有已證實會被 GitHub 配對到各自帳號頭像的共同作者 email。opencode 尚未找到官方 commit attribution 身分，不能保證同一做法能顯示 opencode logo。

| CLI | 官方 attribution | GitHub 配對證據 | 配置入口 |
|---|---|---|---|
| Claude Code | `Co-Authored-By: <模型名稱> <noreply@anthropic.com>` | 公開 commit 的 authors 包含 `claude`、其 profile path 與 avatar | 原生 `settings.json` 的 `attribution.commit`，預設已有 trailer |
| Codex | `Co-authored-by: Codex <noreply@openai.com>` | 同一公開 commit 的 authors 包含 `codex`、其 profile path 與 avatar | 已安裝版本有原生 attribution extension，讀 Codex backend 的 `commit_attribution_enabled`；未找到 `config.toml` 的同名開關 |
| opencode | 未確認官方 email 或預設 co-author trailer | 未驗證官方 logo 配對 | 查過 config schema、設定實作與 prompt，未找到 attribution 專用欄位；可寫專屬 instructions，但 instructions 本身不會建立官方 GitHub 身分 |

先採用 Claude 與 Codex 原生 attribution，再決定 opencode 的可接受呈現。不要改共用 `git user.name` 或把供應商 email 當成 opencode 身分：那會改作者，或顯示供應商頭像，而不是使用的 CLI。

## GitHub 到底顯示什麼

[GitHub 官方文件](https://docs.github.com/en/pull-requests/committing-changes-to-your-project/creating-and-editing-commits/creating-a-commit-with-multiple-authors)要求共同作者 email 與 GitHub account 配對，commit body 與 trailers 之間留一個空行，每位共同作者一行 `Co-authored-by: NAME <EMAIL>`。因此 trailer 的 name 可是模型名稱，頭像仍由 email 配對的 account 決定。

- 主要作者：git commit 的 author；通常仍是使用者。
- Committer：建立這個 git object 的身分；GitHub squash merge 的例子可能是 `web-flow`。
- 共同作者：message trailers 中被 GitHub 配對出的帳號；不必取代主要作者。
- CLI 與模型供應商：opencode 可以使用 Claude 或 OpenAI 模型，但這不讓 opencode 變成 Claude Code 或 Codex。使用 `noreply@anthropic.com`／`noreply@openai.com` 顯示的是其配對帳號。

REST commit API 的頂層 `author`、`committer` 不包含全部共同作者；只看這兩個欄位會漏掉所需證據。

## Claude Code：已有原生設定

已安裝版本：`claude --version` → `2.1.295 (Claude Code)`。

[官方 settings reference](https://code.claude.com/docs/en/settings-reference#attribution-commit)明列 `attribution.commit` 是 string，預設 trailer 的 email 是 `noreply@anthropic.com`，name 是 commit 當下使用的模型；subagent commit 使用 subagent 模型名。不認得的第三方模型可能用 `Claude Code` 作為 name。若想固定顯示 CLI 名稱，可設定：

```json
{
  "attribution": {
    "commit": "Co-Authored-By: Claude Code <noreply@anthropic.com>"
  }
}
```

這是研究示例，尚未寫入設定。保留預設也能顯示同一帳號頭像。

[設定範圍](https://code.claude.com/docs/en/settings)包含 user、project、local、managed；managed 規則可能優先。[`attribution` 說明](https://code.claude.com/docs/en/settings-reference#attribution)指出 CLAUDE.md／memory attribution 指引可優先於一般設定，但 managed attribution 例外。共用檔不應加入其他 CLI 的 attribution。

版本差異：[官方 reference](https://code.claude.com/docs/en/settings-reference#includecoauthoredby)指出 `includeCoAuthoredBy` 自 v2.0.62 deprecated；新設定用 `attribution`。`attribution: false` 需 v2.1.281+，老版本可能跳過整份含此值的 settings file。本研究不建議關閉 attribution。

## Codex：原生 extension 與 backend policy

已安裝版本：`codex --version` → `codex-cli 0.161.0`。2026-10-09 查 [最新 release API](https://api.github.com/repos/openai/codex/releases/latest)是 `rust-v0.162.0`，發布於 2026-10-08。

先查 [OpenAI 官方 config reference](https://developers.openai.com/codex/config-reference/)，未找到 attribution 或 co-author 設定項。進一步查與本機版本對應的官方 source：

- [`policy.rs`，rust-v0.161.0](https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/ext/git-attribution/src/policy.rs#L52)：使用 Codex backend 的 auth 才呼叫 `get_user_settings()`，讀取 `commit_attribution_enabled`。其他 auth／無 auth 回傳 false；取設定失敗回傳 None。
- [`lib.rs`](https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/ext/git-attribution/src/lib.rs)：policy 失敗本輪視為 disabled，快取與重試會影響何時重新查。這不能由公開 source 推斷使用者目前 account 的開關。
- [`world_state.rs`](https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/ext/git-attribution/src/world_state.rs#L17)：enabled 時給模型 commit trailer 指引，保留 existing trailers、exact attribution 去重、body 與 trailers 留空行，包含 GitHub app/plugin 的 commit message；另要求 PR attribution。disabled policy 會指示忽略先前要求加入 attribution 的指引。
- [官方 integration tests](https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/app-server/tests/suite/v2/git_attribution.rs)：驗 workspace policy、cold resume 與 legacy attribution 替換；本輪只讀 source，未執行 Codex 自身 tests。

因此「只在 AGENTS.md 寫 Codex trailer」不是目前所有環境的保證方案。原生 backend policy 明確 disabled 時，較低優先的個人 instruction 無法可靠覆蓋。使用者目前設定、可切換的 UI 入口與部署後行為仍未驗；不應捏造一個 `config.toml` key。

## 已取得 GitHub 共同作者與 avatar 證據

公開既有 commit：[Fix Astra UX bugs and remaining clawpatch findings (batch 3, includes #44)](https://github.com/bedrock-mc/cinnabar/commit/a4d46fae50cda2c13e8f9af76971abbfc94d7b2b)。

[REST commit API](https://api.github.com/repos/bedrock-mc/cinnabar/commits/a4d46fae50cda2c13e8f9af76971abbfc94d7b2b)的 message 結尾是：

```text
Co-authored-by: Codex <noreply@openai.com>
Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>
```

抓取同一 commit 頁的 `application/json` embedded data，`authors` 實際含以下資料；不是從 trailer 文字推測：

| login | displayName | path | avatarUrl |
|---|---|---|---|
| `codex` | `Codex` | `/codex` | `https://avatars.githubusercontent.com/u/267193182?v=4` |
| `claude` | `Claude Opus 5.5` | `/claude` | `https://avatars.githubusercontent.com/u/81847?v=4` |

該 commit 主要作者是 `HashimTheArab`，committer 是 `web-flow`。共同作者與上述身分分開。

另抓 [Claude 公開 commit](https://github.com/ShaulLavo/mesh/commit/259862219118137b47a635059826e1c64cc44c8f)，模型 name `Claude Opus 5.5 (1M context)` 仍配對到 `/claude`、同一 avatar。可交叉確認 model name 不必固定為 `Claude`。

[Codex account API](https://api.github.com/users/codex)與 [Claude account API](https://api.github.com/users/claude)各自回傳相同 account id/avatar。account 的公開 email 是 null；email 身分依官方 source/docs 與 commit 頁的匹配證據建立，不是 account API 公開 email。

本輪證據是 GitHub commit 頁實際傳回的 authors/profile/avatar data；未在瀏覽器截圖或檢視圖像像素，因此未聲稱已目視驗證 logo 外觀。

## opencode：官方 logo 身分尚未確認

已安裝版本：`opencode --version` → `1.18.35`；[最新 release API](https://api.github.com/repos/anomalyco/opencode/releases/latest)同為 `v1.18.35`。

查 [官方 config docs](https://opencode.ai/docs/config/)、[JSON schema](https://opencode.ai/config.json)、[config 實作，v1.18.35](https://github.com/anomalyco/opencode/blob/v1.18.35/packages/opencode/src/config/config.ts)，未找到 attribution／co-author 專用欄位。也查當日 `dev` commit `388406238bd5ca15564a762840a2362c3a45bd9c` 的 [default prompt](https://github.com/anomalyco/opencode/blob/388406238bd5ca15564a762840a2362c3a45bd9c/packages/opencode/src/session/prompt/default.txt)、[anthropic prompt](https://github.com/anomalyco/opencode/blob/388406238bd5ca15564a762840a2362c3a45bd9c/packages/opencode/src/session/prompt/anthropic.txt)、[shell prompt](https://github.com/anomalyco/opencode/blob/388406238bd5ca15564a762840a2362c3a45bd9c/packages/opencode/src/tool/shell/prompt.ts)，未找到官方 attribution email。這是所查來源範圍的未發現，不能證明所有 plugin 或 cloud workflow 都沒有 attribution。

[官方 rules](https://opencode.ai/docs/rules/)能給專屬指引，但仍需有可信官方 account/email，才可能顯示官方 logo。[`users/opencode` API](https://api.github.com/users/opencode)回傳的是 `Apruzzese Francesco`、account id `265697`；不能憑名稱相同使用該 account。未找到與本工具連結的官方共同作者身份，不產生猜測 email。

## 後續驗收

1. 先確認希望表示 CLI，還是模型；「每個 agent 一個 logo」以 CLI 為準，但 opencode 目前有證據缺口。
2. 在本人授權的下一次正常 commit，檢查 `git show -s --format=fuller HEAD` 與 `git show -s --format=%B HEAD`：作者保持本人，正確 trailer 只一行、既有 trailers 保留。amend 也驗一次；不為補標記重寫其他既有 commit。
3. 正常 push 後，開該 GitHub commit 頁確認共同作者 profile 與 avatar；Claude 應連 `/claude`，Codex 應連 `/codex`。REST 頂層 author／committer 不是共同作者驗收。
4. Codex 未加 trailer 時，先查本次 session 的原生 policy 是否啟用與 auth 類型，不靠反覆追加共用 instructions。
5. opencode 要等官方身份證據或明確決定接受文字標記；不能把未確認 email 的 trailer 算成 logo 達標。

## 驗證

- 已執行 `codex --version`、`claude --version`、`opencode --version`：版本如上。
- 已執行 `curl -fsSL` 讀上述官方文件、版本 source、公開 commit HTML；用 Python 解析 embedded JSON 的 `authors` 和 `committer`：取得 Claude/Codex profile 與 avatar 配對。
- 已執行 `gh api repos/bedrock-mc/cinnabar/commits/a4d46fae50cda2c13e8f9af76971abbfc94d7b2b`：取得 trailers、author、committer；另用 `curl -fsSL https://api.github.com/users/codex`、`users/claude`、`users/opencode` 讀公開 account API，不讀取秘密。
- 未驗：使用者自己的 Codex backend setting、設定切換 UI、本機 agent 正常 commit→push 的 end-to-end、瀏覽器 logo 截圖、opencode 官方 attribution identity。原因：本輪限定只讀研究，不部署、不公開測試 commit／PR；官方來源未建立 opencode 身分。

沒有修改 `home/` 或套用 chezmoi；此檔只記錄研究，未決定最終配置架構。
