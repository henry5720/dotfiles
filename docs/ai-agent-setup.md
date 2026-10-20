# AI agent 環境:誰管什麼

用 Claude Code、Codex、opencode 時,身上會掛四種東西:規則、skill、MCP、plugin。
它們**放在不同地方、用不同指令更新**,搞混就會出現「我明明更新了怎麼沒變」。
為什麼這樣分,見 [AI agent 環境:為什麼這樣分](ai-agent-principles.md)。

```text
dotfiles(chezmoi)
  ├─ 裝 skillshare、放它的 config.yaml(之後不再碰)─→ agent-config
  ├─ 規則的 symlink,指到 agent-config 的 instructions/ ─→ agent-config
  └─ client 本身的設定 ──────────────────────────────┐
agent-config(skillshare)                               ├─→ Claude Code / Codex / OpenCode
  └─ 規則內容、skills、MCP ────────────────────────────┘
Claude plugin ── Claude 自己的 /plugin 管,兩個 repo 都不碰 ─→ Claude Code
```

## 四種東西

| | 是什麼 | 檔案實際在哪 | 怎麼更新 |
|---|---|---|---|
| **規則** | 你希望 agent 怎麼做事 | agent-config 的 `instructions/`,本 repo 的 `symlink_` 模板連到各 client | 改完在 agent-config commit,其他機器 `skillshare pull`,見[規則](#規則) |
| **skill** | 一套做某件事的步驟,用到才載入 | agent-config,skillshare 同步到各 client | `skillshare update --all`,見 agent-config 的 [docs/skills/README.md](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md) |
| **MCP** | 給 agent 接外部服務的通道 | agent-config 的 `mcp.yaml`,skillshare 寫進各 client 設定檔 | `skillshare sync mcp -g`,見 agent-config 的 [docs/mcp.md](https://github.com/henry5720/agent-config/blob/main/docs/mcp.md) |
| **plugin** | Claude 的擴充包(可同時含 skill、MCP、指令) | `~/.claude/plugins/` | Claude 裡打 `/plugin`,見 [plugin](#plugin) |

- skillshare 怎麼用(裝 skill、加 MCP、跨機器同步)寫在 [agent-config 的 README](https://github.com/henry5720/agent-config#日常操作),這份不重寫。
- 不歸 skillshare 管的例外(obsidian-wiki、plugin…)和 herdr skill 要跟版本的事,見
  agent-config 的 [docs/skills/README.md](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md#從哪來落到哪)。
- **這個 repo 不寫任何 MCP 條目。** dotfiles 自己部署、跟 MCP 有關的只有
  [codegraph](codegraph.md)(CLI、索引、git hook)、[playwright-cli](playwright-cli.md)(操作瀏覽器時代替 MCP)
  和 [opencode](opencode.md) 的設定檔。

## 規則

只有一份真的檔案,其他都是 symlink,由本 repo 的 `symlink_*.tmpl` 放(決策見 [ADR 0002](adr/0002-agent-instructions-in-agent-config-placed-by-chezmoi-symlinks.md)):

```text
agent-config/instructions/agents-md/AGENTS.md   ← 真的檔案,只有這份要改
   ├── ~/.claude/CLAUDE.md
   ├── ~/.codex/AGENTS.md
   ├── ~/.config/opencode/AGENTS.md
   └── ~/.config/opencode/routes/personal/AGENTS.md
agent-config/instructions/agent-commit/instructions.md
   └── ~/.config/agent-commit/instructions.md
agent-config/instructions/opencode-commit/commit-instructions.md
   └── ~/.config/opencode/commit-instructions.md   (opencode.json 的 instructions 引用它)
```

agent-config 在本機 clone 在 `~/.config/skillshare/`,symlink 指的就是那裡。

| 想做什麼 | 怎麼做 |
|---|---|
| 改規則內容 | 改 agent-config 的檔案、在 agent-config commit;其他機器 `skillshare pull` |
| 改「連到哪」(新增或搬動 symlink) | 改本 repo 的 `symlink_` 模板,`chezmoi apply` |
| 從舊的 skillshare extras 做法換過來 | 上面兩個都要跑 |
| 確認規則有生效 | 開新 session 打 `/context`,看 **Memory files** 那區 |

新機器不用為規則另外做事:`chezmoi apply` 先放好 symlink,這時 agent-config 還沒 clone,symlink 是懸空的;
選裝工具 `agent-config` 的 after 腳本 clone 完就指得到檔案。沒勾 `agent-config` 的機器,這幾個 symlink 會一直懸空。

## plugin

Claude 專屬的擴充包,一個 plugin 裡可能同時有 skill、MCP、slash 指令。
**`skillshare update` 完全管不到它們**,這是最容易搞混的地方。

- Claude 裡打 `/plugin` 瀏覽、安裝、更新、移除。檔案在 `~/.claude/plugins/`,清單在 `installed_plugins.json`。
- 新機器要裝哪些、`chrome-devtools-mcp` 為什麼關掉,見[新機器設定 4.5](new-machine-setup.md#45-mcpskills-與-claude-plugin)。
- opencode 也有自己的 plugin,寫在 `opencode.json` 的 `plugin` 欄位,由本 repo 的 [opencode 設定](opencode.md)管,
  跟 Claude 的 plugin 無關。
- ⚠️ **同一套 skill 不要用兩種方式裝。** 有些作者同時提供一般 skill repo 和 Claude plugin
  兩條路(例如 mattpocock),兩邊都裝會變成每個 skill 兩份。選一條。

## 懶人包

| 想做什麼 | 怎麼做 |
|---|---|
| 改 agent 的行為規則 | 改 agent-config 的 `instructions/agents-md/AGENTS.md`,在 agent-config commit |
| 新機器套用規則、要重裝什麼 | 照[新機器設定 Runbook](new-machine-setup.md) 跑 `chezmoi init --apply` |
| 裝／更新 skill、寫自己的 skill、接 MCP | 見 [agent-config 的日常操作](https://github.com/henry5720/agent-config#日常操作) |
| 只給某個專案用的 skill | 放 `<那個repo>/.claude/skills/<名字>/` |
| 關掉不用的 skill | 見 agent-config 的[〈怎麼關〉](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md#怎麼關);新機器裝完 skill 會全部是開的,要重關一次 |
| 讓 agent 用瀏覽器查原因 | `remote-chrome`:WSL 開 Windows Chrome,遠端主機開本機的 headless Chrome(見[新機器設定 4.1](new-machine-setup.md#41-headless-chrome選了-headless-chrome-才有)),再在 session 裡 `/mcp` 確認連上 |
| 讓 agent 點、跑流程、截圖 | 遠端主機勾 `playwright-cli`,見 [playwright-cli](playwright-cli.md) |
| 讓 agent 用 symbol 圖查程式碼,不要一直 grep | `codegraph-setup-repo ~/code/<repo>`,見 [codegraph](codegraph.md) |
| 換過 node 版本後 codegraph／playwright-cli 不見了 | 重裝那個 npm 全域套件,見 [codegraph](codegraph.md#換-node-版本之後) |
| 某個 repo 的共用 git hook 沒生效 | 見 [codegraph](codegraph.md#repo-自己搶走-corehookspath) |
| 改 opencode 的 provider、agent、plugin | 見 [opencode](opencode.md) |
| 更新 Claude plugin | Claude 裡打 `/plugin` |
