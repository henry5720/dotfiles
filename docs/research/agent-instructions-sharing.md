# 三個 agent 共用偏好與專屬指引：研究

日期：2026-10-09。對應 [查三個 agent 如何共用偏好並保留專屬指引](https://github.com/henry5720/dotfiles/issues/152)。只研究，未改配置、未部署。

## 收尾紀錄（2026-10-09）

本文保留研究當時的來源與建議，並非目前部署方式。後續採用「保留共用 symlink，優先用各工具原生設定與專屬 instruction」，由 [PR #155](https://github.com/henry5720/dotfiles/pull/155) 合併；沒有改成本文示意的三份生成指引。以合併的 commit `8a74a6e` 為準。

只有未來出現原生設定無法表達的工具專屬文字指引時，再評估共用 template；本次研究已保存，無需保留獨立 worktree。

## 結論與建議

**symlink 適合所有工具讀取完全相同內容；需要 agent 專屬指引後，推薦改成 chezmoi 共用 template，加上各 agent 的專屬尾段，部署成普通檔案。** 這是本 repo 的設計建議，不是三家共同宣布的最佳實踐。

共用偏好在 chezmoi source 只保留一份；各入口產生「共用偏好 → 專屬指引」。不推薦把所有 agent 的條件判斷塞进同一份 CLAUDE.md，因為既有 symlink 使每個工具都收到其他工具的條件，新增規則也會同時影響三者。官方原生 attribution 設定優先於自然語言指令；具體 commit 身分由另一個研究 issue 決定。

推薦使用同一種部署方式，而非讓 Claude 用 `@`、OpenCode 用 `instructions`、Codex 再另外生成：三種機制可行，但本 repo 既有 chezmoi 已能在部署前合成文字，統一生成檔可少維護兩種 runtime 引用規則。[chezmoi includeTemplate](https://www.chezmoi.io/reference/templates/functions/includeTemplate/) 支援先查 `.chezmoitemplates`，再查 source 相對路徑。

示意結構（尚未建立）：

```text
home/.chezmoitemplates/agent-preferences.md  共用偏好的唯一來源
  → home/dot_claude/CLAUDE.md.tmpl          共用 + Claude 專屬尾段
  → home/dot_codex/AGENTS.md.tmpl           共用 + Codex 專屬尾段
  → home/dot_config/opencode/AGENTS.md.tmpl 共用 + OpenCode 專屬尾段
```

生成檔不要直接修改；改 source 再 apply。既有 CodeGraph 自動更新區塊需要另做維護決定：目前 `home/dot_claude/CLAUDE.md:50` 明載 installer/upgrade 會改部署檔；若生成檔改由 template 管理，自動寫入如何回收 source 必須確認，不能在遷移時遺失區塊。

## 官方載入行為

| 工具 | 全域與 repo 指引 | 引用與疊加 | 已證實的限制 |
|---|---|---|---|
| Codex | `CODEX_HOME`（預設 `~/.codex`）先選 `AGENTS.override.md`，否則 `AGENTS.md`，只選第一個非空檔。repo root 到 cwd，每層選 override → AGENTS → fallback 中一個；依序串接。 | 文件提供 `project_doc_fallback_filenames`，可加入 `CLAUDE.md`。這是候選檔名，不是 include。 | 全域 override **取代** global base，不是追加專屬尾段。每層最多一份；預設總量 32 KiB。本文所查官方文件沒有保證解析 Markdown `@file`，不能把 Claude import 當成 Codex 機制。啟動時讀取，改動後需新 run/session。[來源 C] |
| Claude Code | `~/.claude/CLAUDE.md` 是個人全域指引；cwd 與祖先的 CLAUDE.md / CLAUDE.local.md 啟動載入，子目錄按需。 | 原生 `@path` import：相對路徑相對包含它的檔案；可用絕對路徑；最多四層。repo AGENTS 自 v2.1.277 支援，預設只有路徑上沒有 project CLAUDE.md / CLAUDE.local.md 才直接載入；全域 CLAUDE.md 不阻擋。 | 每個檔案是串接 context，衝突不保證機械式覆寫。repo 外部 import 有批准規則；user-scope 通常不需要對話框。Cowork desktop 會略過 symlink/hardlink 全域 CLAUDE.md 與越出 cwd 的 user import。Windows symlink 有建立權限與 Git checkout 限制。[來源 A] |
| OpenCode | 全域 `~/.config/opencode/AGENTS.md` 存在時取代 `~/.claude/CLAUDE.md` fallback；project AGENTS 優先於 CLAUDE。 | `opencode.json` 的 `instructions` 可載入路徑、glob、URL，與 AGENTS 一起加入 context；**不自動解析 AGENTS 裡的檔案引用**。 | 官方文件的 precedence 列的是搜尋來源，不是宣告所有內容後者無條件勝出。v1.18.35 原碼按 global → project → configured paths 收集。不能套用 Codex 每個祖先層自動追加的假設。[來源 O、OS] |

來源：

- **C（OpenAI Docs）**：[Custom instructions with AGENTS.md](https://developers.openai.com/codex/guides/agents-md)。已實際抓取全文。
- **A**：[Claude Code memory](https://code.claude.com/docs/en/memory)，包括 “Share one file with other coding tools”、“AGENTS.md”、“Import additional files”。已實際抓取全文。
- **O**：[OpenCode Rules](https://opencode.ai/docs/rules/)。已實際抓取全文。
- **OS**：[OpenCode v1.18.35 instruction.ts](https://github.com/anomalyco/opencode/blob/53d1eabb61e21162157817bf677da0a4ad3332e3/packages/opencode/src/session/instruction.ts#L110)。`systemPaths` 先 global，再 first project-level match，再 `config.instructions`。

### symlink 与重複載入

Claude 官方文件直接說明 `CLAUDE.md → AGENTS.md` symlink 可用，但建議需要 Claude 專屬內容時用 `@AGENTS.md` 加尾段；Windows 建議 import。新版 Claude 同時讀兩種檔名時會去重已 import 或 symlink 的 AGENTS；文件亦說保留既有 import 不會讀兩次。這是 **Claude 的保證**，不是三工具共用契約。[來源 A]

OpenCode v1.18.35 的 `systemPaths` 使用 `Set<string>` 與 `path.resolve`，未用 `realpath` 去重：同一路徑可去重，不同 symlink 路徑指向同一檔案不能假設會去重。若已把共用內容生成在 global AGENTS，勿再把原共用檔加入 `instructions`。[原碼 L113–150](https://github.com/anomalyco/opencode/blob/53d1eabb61e21162157817bf677da0a4ad3332e3/packages/opencode/src/session/instruction.ts#L113)。本文未作模型載入實測。

## 本 repo 現況與 route 影響

研究基準 commit：`9b7dfff065f81945ad0f430c1c2bd540a6bcc556`。

| source | 實際內容／影響 |
|---|---|
| `home/dot_claude/CLAUDE.md:3` | 定義跨 repo、跨 agent 偏好，名稱雖是 Claude，內容定位已是共用。 |
| `home/dot_codex/symlink_AGENTS.md.tmpl:1` | 指向 `~/.claude/CLAUDE.md`。 |
| `home/dot_config/opencode/symlink_AGENTS.md.tmpl:1` | 同樣指向 `~/.claude/CLAUDE.md`。 |
| `home/dot_config/opencode/routes/personal/symlink_AGENTS.md.tmpl:1` | personal route 指回 global OpenCode AGENTS。 |
| `home/dot_local/bin/executable_ai-profile:85` | Codex personal 使用 `--profile personal`，不改 CODEX_HOME；因此 work/personal 共用全域指引。 |
| `home/dot_local/bin/executable_ai-profile:94` | OpenCode personal 使用 `OPENCODE_CONFIG_DIR` 指向 route。 |

OpenCode v1.18.35 [Global.make 原碼 L64](https://github.com/anomalyco/opencode/blob/53d1eabb61e21162157817bf677da0a4ad3332e3/packages/core/src/global.ts#L64) 將 `global.config` 設為 `OPENCODE_CONFIG_DIR ?? Path.config`；instruction loader 從該路徑讀 AGENTS。故 route symlink 仍有明確用途：讓 personal 読到跟 work 相同的內容。遷移只需替換 global AGENTS 的生成方式，不因模型/provider 不同而複製指引。repo 的 `docs/ai-profile-routing.md` 亦明確把 rules 列為共用。

repo 目前根只有 CLAUDE.md，Codex 不會因 global symlink 就自動取得 repo CLAUDE.md；若需要跨工具 project 規範，應另決定使用 AGENTS 或 Codex fallback。這是全域分享與 repo 分享的不同問題，不能只換 global symlink 就宣稱解決。

## 可追溯的公開配置案例

這兩個案例都用「repo AGENTS 為共用來源，Claude wrapper 原生 import」；能證明這是有人實際採用的方式，不能據此宣稱最普遍或最佳。

- [Langflow CLAUDE.md](https://github.com/langflow-ai/langflow/blob/504c02fc47e76087b82b0e7cbe4186e9cdd916d4/CLAUDE.md)：`@AGENTS.md` 再 `@.claude/CLAUDE.md`，檔案文字明說前者是標準、後者是 local hard rules。
- [Misskey CLAUDE.md](https://github.com/misskey-dev/misskey/blob/53ac6808ae4921305e761c545863ee6593edd1f4/CLAUDE.md)：`@AGENTS.md`，文字明說規則與 Codex / Copilot 共用，Claude-specific skills、agents、commands 保留在 `.claude/`。

已透過 GitHub API 讀原檔並固定 commit URL。這些是 repo-level 例子；未找到足以宣稱大家都採用某一種 global chezmoi 方案的證據。

## 驗證與未驗

已執行：

- `gh issue view 152 --repo henry5720/dotfiles --json title,body,assignees`：確認問題與 assignee。
- `curl -fsSL` 抓上述三工具官方頁、chezmoi includeTemplate，以及 OpenCode v1.18.35 原碼：成功。
- `gh api` 抓 Langflow / Misskey 原檔與 commit SHA、OpenCode v1.18.35 tag SHA：成功。
- `codex --version` → `codex-cli 0.161.0`；`claude --version` → `2.1.295`；`opencode --version` → `1.18.35`。
- 讀取列出的 source / wrapper 與 routing 文件；未讀 credential 或 auth state。

未驗：三工具載入完整 context 的實測、Windows / Termux / Cowork、chezmoi template rendering 與部署、CodeGraph installer 回收生成檔的流程、GitHub commit logo。這次只新增研究文件，不執行 apply；logo 由並行研究處理。

官方文件為查閱日現行文件；Claude 功能依版本與插件開啟狀態而異。Codex 的 Markdown import 只列為「查閱文件未承諾」，沒有推斷所有產品永遠不支援。OpenCode 原碼已固定到本機版 tag，避免把 dev branch 當成本機行為。
