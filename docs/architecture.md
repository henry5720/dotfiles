# 架構：repo 怎麼組成、agent 環境誰管什麼

給要改或 fork 這個 repo 的人：repo 裡每塊部署到哪、fork 前要改什麼、coding agent 身上的規則、skill、MCP、plugin 各歸誰管。
改 repo 的規則（檔名前綴、秘密、驗證方式（含容器 e2e）、issue 流程）看 [`AGENTS.md`](../AGENTS.md)；
某個決定當時的理由看 [`adr/`](adr/)；`docs/superpowers/`、[`research/`](research/) 是當時的 spec、plan 與研究紀錄，不是現行文件。

## repo 結構

```text
.chezmoiroot                    內容是 home：chezmoi 只看 home/，其餘它看不到
home/                           → 部署到 ~（chezmoi apply）
├── .chezmoi.toml.tmpl          → ~/.config/chezmoi/chezmoi.toml：憑證、Git 身分、選裝工具
├── .chezmoidata/               不部署：基底套件與走 apt 的選裝工具清單
├── .chezmoitemplates/          不部署：樣板共用片段（選單的選項與說明、判斷 WSL／Debian、腳本共用函式…）
├── .chezmoiexternal.toml.tmpl  → ~/.config/zsh/*、Termux 字型（apply 時下載）
├── .chezmoiscripts/            不部署，apply 時執行：裝套件、選裝工具、換預設 shell
├── dot_zshenv                  → ~/.zshenv：環境變數、PATH、MCP key（每個 zsh 都讀，非互動的也是）
├── dot_zshrc                   → ~/.zshrc：互動式 shell 的提示列、補全、別名
├── modify_dot_bashrc.tmpl      → ~/.bashrc 最後加段落：starship、沒有 root 時切 zsh
├── dot_gitconfig.tmpl          → ~/.gitconfig：Git 身分、HTTPS clone／SSH push
├── dot_wslconfig               → Windows 主機的 %USERPROFILE%\.wslconfig（只部署到 Windows）
├── Documents/                  → Windows 主機的 Documents\：pwsh 7 與 5.1 的 PowerShell profile（只部署到 Windows）
├── AppData/                    → Windows 主機的 %LOCALAPPDATA%：Windows Terminal 的預設設定檔與字型（只部署到 Windows）
├── dot_config/                 → ~/.config/：nvim、git hooks、zsh、starship、opencode…
├── dot_claude/                 → ~/.claude/：設定（選單勾了 claude 才部署）
├── dot_codex/                  → ~/.codex/：同上（勾了 codex 才部署）
├── dot_local/bin/              → ~/.local/bin/：自己的指令（tools、ai-profile、ttyd-serve…）
├── dot_local/share/fonts/      → ~/.local/share/fonts/：Termux 字型的 symlink
└── private_dot_ssh/            → ~/.ssh/（700）：SSH config（Windows 主機也部署）
script/                         不部署，自己手動跑
├── ubuntu/                     會改系統的：Docker、swap
├── termux/                     平板桌面、proot Ubuntu 的使用者
├── tests/                      容器 e2e 與單元測試
└── demo/                       重錄 README 與工具一覽的截圖、安裝 GIF
docs/                           文件（見 README 的文件索引）
```

- 檔名前綴（`dot_`、`private_`、`symlink_`、`.tmpl`…）決定部署結果，規則見
  [target types](https://www.chezmoi.io/reference/target-types/)；逐檔清單跑 `chezmoi managed`。
- skills、MCP、全域規則（`CLAUDE.md`／`AGENTS.md`）和 commit 指引的內容在 agent-config，這裡只放
  skillshare 的 `config.yaml`，其中 targets、extras 段照選單勾的 client 產生，決定 skills 與規則連到哪（[ADR 0003](adr/0003-agent-instructions-linked-by-skillshare-extras.md)）；見 agent-config 的
  [skill](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md)、[MCP](https://github.com/henry5720/agent-config/blob/main/docs/mcp/README.md)。
- Windows 主機也用這個 repo，只部署 `home/.chezmoiignore` Windows 段白名單上的檔案、只跑 `.ps1` 腳本，見[Windows 主機](how-to/windows.md)；
  為什麼這樣分見 [Wayfinder: Windows 側交給 chezmoi（PowerShell、WSL、Windows Terminal）](https://github.com/henry5720/dotfiles/issues/167)。
- chezmoi 本身的日常用法照官方 [daily operations](https://www.chezmoi.io/user-guide/daily-operations/)。

## fork 前要改什麼

- [ ] GitHub 帳號：改 [`home/.chezmoidata/github.yaml`](../home/.chezmoidata/github.yaml) 的 `githubUser`。agent-config 的 remote、`authorized_keys` 抓誰的公鑰都讀它
- [ ] 安裝指令 `chezmoi init --apply henry5720` 裡的帳號要自己改：這行在 chezmoi 拉 repo 之前就要打，讀不到上一項的 data 檔
- [ ] AI provider、model 與 agent 規則（`home/dot_codex/`、`home/dot_config/opencode/`、agent-config）
- [ ] ssh config 裡的 Tailscale 主機與平板
- [ ] 已有設定的機器先備份；不要未檢查就部署別人的個人 dotfiles
- [ ] 憑證不進 git，`chezmoi init` 時才問、存在 `~/.config/chezmoi/chezmoi.toml`；不信任或共用的機器不要填真實憑證

## AI agent 環境:誰管什麼

用 Claude Code、Codex、opencode 時,身上會掛四種東西:規則、skill、MCP、plugin。
它們**放在不同地方、用不同指令更新**,搞混就會出現「我明明更新了怎麼沒變」。
為什麼這樣分,見 [AI agent 環境:為什麼這樣分](architecture/agent-principles.md)。

```text
dotfiles(chezmoi)
  ├─ 裝 skillshare、放它的 config.yaml(之後只釘 targets、extras 段)─→ agent-config
  └─ client 本身的設定 ──────────────────────────────┐
agent-config(skillshare)                               ├─→ Claude Code / Codex / OpenCode
  ├─ 規則內容與連結(extras)、skills、MCP ──────────────┘
  └─ plugin(skillshare plugin,記在本機 config.yaml)──→ Claude Code 等
```

### 四種東西

| | 是什麼 | 檔案實際在哪 | 怎麼更新 |
|---|---|---|---|
| **規則** | 你希望 agent 怎麼做事 | agent-config 的 `extras/`,skillshare extras 連到各 client | 改完在 agent-config commit,其他機器 `skillshare pull`,見[規則](#規則) |
| **skill** | 一套做某件事的步驟,用到才載入 | agent-config,skillshare 同步到各 client | `skillshare update --all`,見 agent-config 的 [docs/skills/README.md](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md) |
| **MCP** | 給 agent 接外部服務的通道 | agent-config 的 `mcp.yaml`,skillshare 寫進各 client 設定檔 | `skillshare sync mcp -g`,見 agent-config 的 [docs/mcp/README.md](https://github.com/henry5720/agent-config/blob/main/docs/mcp/README.md) |
| **plugin** | 一整包擴充(可同時含 skill、MCP、指令、subagent) | 宣告在 config.yaml 的 `plugins:`,裝進 `~/.claude/plugins/` 等 | `skillshare plugin update`,見 [plugin](#plugin) |

- skillshare 怎麼用(裝 skill、加 MCP、跨機器同步)寫在 agent-config 的 [docs/skills/README.md](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md#跨機器),這份不重寫。
- 不歸 skillshare 管的例外(obsidian-wiki…)和 herdr skill 要跟版本的事,見
  agent-config 的 [docs/skills/README.md](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md#從哪來落到哪)。
- **這個 repo 不寫任何 MCP 條目。** dotfiles 自己部署、跟 MCP 有關的只有
  [codegraph](tools/codegraph.md)(CLI、索引、git hook)、[playwright-cli](tools/playwright-cli.md)(操作瀏覽器時代替 MCP)
  和 [opencode](tools/opencode.md) 的設定檔。

### 規則

只有一份真的檔案,其他都是 skillshare extras 建的 symlink;連到哪寫在本 repo 的
`home/.chezmoitemplates/skillshare-pinned`,照選單勾了哪些 client 產生,由
`home/dot_config/skillshare/modify_config.yaml.tmpl` 釘進 config.yaml(決策見 [ADR 0003](adr/0003-agent-instructions-linked-by-skillshare-extras.md))。
下面是三個 client 都勾的樣子;沒勾的 client 沒有它那幾條,`agent-commit` 勾任一個 agent 就有:

```text
agent-config/extras/agents-md/AGENTS.md   ← 真的檔案,只有這份要改
   ├── ~/.claude/CLAUDE.md                          (claude)
   ├── ~/.codex/AGENTS.md                           (codex)
   ├── ~/.config/opencode/AGENTS.md                 (opencode)
   └── ~/.config/opencode/routes/personal/AGENTS.md (opencode)
agent-config/extras/agent-commit/instructions.md
   └── ~/.config/agent-commit/instructions.md
agent-config/extras/pstack-models/pstack-models.md
   └── ~/.claude/rules/pstack-models.md             (claude;pstack 每個角色用哪個模型)
agent-config/extras/opencode-commit/commit-instructions.md
   └── ~/.config/opencode/commit-instructions.md    (opencode;opencode.json 的 instructions 引用它)
```

agent-config 在本機 clone 在 `~/.config/skillshare/`,symlink 指的就是那裡。

| 想做什麼 | 怎麼做 |
|---|---|
| 改規則內容 | 改 agent-config 的檔案、在 agent-config commit;其他機器 `skillshare pull` |
| 改「連到哪」(新增或搬動連結) | 改本 repo 的 `.chezmoitemplates/skillshare-pinned`,`chezmoi apply`(apply 後會自動 `skillshare sync --all`) |
| 多勾或取消一個 client | 打 `tools` 勾選;skillshare 的 targets、extras 跟著換。取消勾選時已經連出去的檔案留著 |
| 從舊的 `symlink_` 模板做法換過來 | `skillshare pull`、`chezmoi apply` |
| 檢查連結 | `skillshare extras list`,或 dashboard 的 Extras |
| 確認規則有生效 | 開新 session 打 `/context`,看 **Memory files** 那區 |

新機器不用為規則另外做事:選裝工具 `agent-config` 的 after 腳本 clone 完 agent-config 後跑 `skillshare sync --all`,
連結一起建好。沒勾 `agent-config` 的機器沒有 skillshare,也不放 `config.yaml`,各 client 不會有這幾個檔。
targets(skills 同步到哪)也照勾的 client 產生:claude → `claude`、codex → `codex`,opencode 不加 target
(OpenCode 也讀前兩份,再加一份同一支 skill 會出現三次)。用 `skillshare target add` 手動加的 target,下次 `chezmoi apply` 會被蓋掉。

### plugin

一整包擴充,一個 plugin 裡可能同時有 skill、MCP、slash 指令、subagent。
**用 `skillshare plugin` 管,不是 `skillshare update`**,這是最容易搞混的地方。
指令照 agent-config 的 skillshare skill(或 `skillshare plugin --help`)。

- 宣告寫在 skillshare 的 `config.yaml` 的 `plugins:`。chezmoi 只釘 targets、extras 兩段,這段照留;
  但 config.yaml 不進任何 repo,**換一台機器要再 `skillshare plugin add` 一次**。
- skillshare 底下用各 client 原生的 plugin 系統裝,Claude 的 `claude plugin list` 看得到,
  marketplace 名字是 `skillshare-<名字>-<hash>`,不是作者 README 寫的那個。更新走 `skillshare plugin update`。
- WakaTime 的 plugin 例外:由 apply 用 `claude plugin install` 裝(見 [WakaTime](tools/wakatime.md)),不收進 skillshare。
- 新機器要裝哪些、`chrome-devtools-mcp` 為什麼關掉,見[新機器設定 4.5](new-machine-setup.md#45-mcpskills-與-claude-plugin)。
- opencode 也有自己的 plugin,寫在 `opencode.json` 的 `plugin` 欄位,由本 repo 的 [opencode 設定](tools/opencode.md)管,
  跟 Claude 的 plugin 無關。
- ⚠️ **同一套 skill 不要用兩種方式裝。** 有些作者同時提供一般 skill repo 和 Claude plugin
  兩條路(例如 mattpocock),兩邊都裝會變成每個 skill 兩份。選一條。

### 懶人包

| 想做什麼 | 怎麼做 |
|---|---|
| 改 agent 的行為規則 | 改 agent-config 的 `extras/agents-md/AGENTS.md`,在 agent-config commit |
| 新機器套用規則、要重裝什麼 | 照[新機器設定 Runbook](new-machine-setup.md) 跑 `chezmoi init --apply` |
| 裝／更新 skill、寫自己的 skill、接 MCP | skill 見 agent-config 的 [docs/skills/README.md](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md),MCP 見 [docs/mcp/README.md](https://github.com/henry5720/agent-config/blob/main/docs/mcp/README.md) |
| 只給某個專案用的 skill | 放 `<那個repo>/.claude/skills/<名字>/` |
| 關掉不用的 skill | 見 agent-config 的[〈怎麼關〉](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md#怎麼關);新機器裝完 skill 會全部是開的,要重關一次 |
| 讓 agent 用瀏覽器查原因 | 遠端主機勾 `headless-chrome`(見[新機器設定 4.1](new-machine-setup.md#41-headless-chrome選了-headless-chrome-才有)),agent 照[瀏覽器](how-to/remote-access/browser.md#headlessagent-自己的瀏覽器)開 headless Chrome 在 9222,再在 session 裡 `/mcp` 確認連上。WSL 沒有這一項,查原因到遠端主機做 |
| 讓 agent 點、跑流程、截圖 | 遠端主機勾 `playwright-cli`,見 [playwright-cli](tools/playwright-cli.md) |
| 讓 agent 用 symbol 圖查程式碼,不要一直 grep | `codegraph-setup-repo ~/code/<repo>`,見 [codegraph](tools/codegraph.md) |
| 換過 node 版本後 codegraph／playwright-cli 不見了 | 重裝那個 npm 全域套件,見 [codegraph](tools/codegraph.md#換-node-版本之後) |
| 某個 repo 的共用 git hook 沒生效 | 見 [codegraph](tools/codegraph.md#repo-自己搶走-corehookspath) |
| 改 opencode 的 provider、agent、plugin | 見 [opencode](tools/opencode.md) |
| 更新 plugin | `skillshare plugin update --all -g` |
