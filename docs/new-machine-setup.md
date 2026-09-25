# 新機器設定 Runbook

## 適用範圍

這份 Runbook 適用 **WSL2 + Ubuntu 24.04**。目的是把一台新機器恢復成這個
dotfiles repo 所描述的 shell、chezmoi 與 AI-agent 工作環境,並確認 OpenCode 能叫到
Claude Code ACP。

它只處理 WSL 裡的使用者環境。Windows 端的 `.wslconfig`、SSH private key、各服務帳號
登入、秘密與 optional tools 不會由文件代替你決定;需要人工確認的地方會停下來。

```text
chezmoi: init → diff → apply ──> 家目錄設定
安裝:   setup.sh → install-base.sh / install-tools.sh / install-tools-ai.sh
```

## 交給 coding agent

以下 prompt 可以直接貼給**已經能正常工作的 coding agent**:

```text
請依照 ~/.local/share/chezmoi/docs/new-machine-setup.md 的順序,協助我重建這台
WSL2 Ubuntu 24.04。你只能執行文件中已列出的可自動化步驟,每完成一步就執行該步的
驗證並回報結果,再進下一步。

遇到 sudo 密碼或權限、任何秘密/API key/password、Claude OAuth、SSH key、需要瀏覽器
登入、或 optional choice 時,請先暫停並詢問我,不要猜測或代替我選擇。不要讀取、列印、
儲存、複製或提交任何憑證;不要把 Claude OAuth 或 SSH private key 寫進 repo。

如果目前沒有可用的 coding agent,不要假裝能執行這些步驟,請我先依文件的「人類
checklist」操作。完成後只回報每一步的結果與尚未處理的人工項目。
```

> 上面 prompt 中的路徑若含空格,請以實際 repo 位置為準。coding agent 必須先存在且
> 能啟動;這份文件不是用來 bootstrap 第一個 agent 的工具。

## 人類 checklist

### 1. 取得 WSL、Ubuntu 與 sudo

先在 Windows 取得可啟動的 WSL2 Ubuntu 24.04,進入 Ubuntu 使用者 shell,並確認自己有
可用的 `sudo`。`script/ubuntu/setup.sh` 會使用 `sudo apt`、`sudo snap`、`sudo chsh`;
沒有 sudo 時不要繼續,改讀 [no-sudo-setup.md](no-sudo-setup.md)。

### 2. 安裝 chezmoi 並部署 dotfiles

以下假設 repo 使用 chezmoi 預設路徑 `~/.local/share/chezmoi`;若實際位置不同,請將
後續路徑改成實際位置。先安裝 chezmoi,初始化後先預覽 diff,確認內容才套用:

```bash
sudo snap install chezmoi --classic
chezmoi init henry5720
chezmoi diff
chezmoi apply
```

`home/.chezmoi.toml.tmpl` 以 `promptStringOnce` 管理 4 個憑證與 2 個 Git 身分欄位。
`chezmoi init` 只會詢問尚未保存的值,不是每次都問:

- 憑證: `code-server 密碼`、`codex-lb API key`、`Context7 API key`、`WakaTime API key`（後兩者可留空）。
- Git 身分: `git user.name`(預設 `henry`)與 `git user.email`(請填自己的身分)。

憑證只在終端機的 chezmoi prompt 輸入,不要交給 coding agent,不要貼到文件或 repo。
這些值會存在 `~/.config/chezmoi/chezmoi.toml`,不是 git 內容；Git 身分不是憑證,但
email 仍不應寫死在公開 repo。

這一步會恢復 chezmoi 管理的規則、OpenCode core config、Claude 的 `modify_`
設定、Context7 key 的 `~/.config/zsh/env.zsh`、`chrome-mcp`、全域 Git 設定／hooks、`codegraph-setup-repo` 等。SSH 只會恢復
設定檔,**不會恢復 SSH private key**;`~/.ssh/henry5720` 要由你用安全方式放入並
執行 `chmod 600 ~/.ssh/henry5720`。

### 3. 執行 Ubuntu 一次性入口

在 chezmoi source repo 執行推薦的一次性入口:

```bash
cd ~/.local/share/chezmoi
bash script/ubuntu/setup.sh
```

它會讓你選擇 `install-base.sh`、`install-tools.sh`、`install-tools-ai.sh`、
`install-docker.sh`（高風險 Docker）與 `setup-swap.sh`（使用主機資源，預設 2G）；空白
Enter 不執行。各工具腳本的選單可用空格分隔多選，直接 Enter 會選該腳本的全部工具。
若只想分開處理，可直接執行上述腳本。需要 Node/npm 的工具請先確認 nvm 或既有 Node。
Docker 選項仍會保留腳本的人工確認；WSL 通常應優先使用 Docker Desktop + WSL integration。
Herdr 位於 `install-tools.sh` 的一般工具選單，只有需要 live pane 時才選取。

若要讓 OpenCode 的 `local-artifact-intake` 在新機上具備基本 PDF／Office／影音解析能力，執行
`bash script/ubuntu/install-tools-ai.sh`，選擇「文件／影音解析」。這個選項是
`ffmpeg`、`mupdf-tools`、`pandoc` 的唯一管理者，並提供 Python venv 所需的 `python3-venv`；
不預裝 LibreOffice、OCR、STT 或 Python AI packages。

三個 AI CLI 在 `install-tools-ai.sh`：Claude Code、Codex（官方
`https://chatgpt.com/codex/install.sh`）、OpenCode（官方腳本帶 `--no-modify-path`，
裝到 `~/.opencode/bin`）；
因為 PATH 已經寫在 `home/dot_zshrc` 裡,讓 installer 去改 `~/.zshrc` 會弄出 chezmoi 漂移)。
兩者的 work 設定由 chezmoi 部署;個人入口需另外登入並填妥 personal model,詳見
[AI profile routing](ai-profile-routing.md),未完成前不要視為可用。

skills 與 MCP 在 `install-tools-ai.sh` 的「agent-config」項,**要在 `chezmoi apply` 之後跑**:
chezmoi 先放好 `~/.config/skillshare/config.yaml`,這一項才會直接從 agent-config 拉下來。
它會先裝 skillshare(裝到 `~/.local/bin`),然後:

```text
還沒 init:skillshare init --git-root root --remote git@github.com:henry5720/agent-config.git ...
          → skillshare install -g → skillshare sync → skillshare sync mcp -g
已經 init:skillshare pull → skillshare sync mcp -g
```

重跑是安全的,第二次只會 pull 跟 sync,沒有變化。用 `DRY_RUN=1` 可以先看會跑哪些指令。
agent-config 的 skill 與 MCP 會用到的系統工具:`ffmpeg`(「文件／影音解析」)、`python3`
(Ubuntu 內建;slack-list 的 script 用它)、`node`/`npx`
(`install-tools.sh` 的 nvm)、`codegraph`(「codegraph CLI」,需要先有 npm)、`gh`
(`install-tools.sh` 的 GitHub CLI,裝完 `gh auth login`)。

若確實需要可選的 AI 文件／媒體解析，在 `install-tools-ai.sh` 選「AI 文件／影音解析」。它會在
`~/.local/share/ai-document-media/venv` 建立獨立 Python venv,只安裝 `docling` 與
`faster-whisper`。也可在執行前設定 `AI_DOCUMENT_MEDIA_BACKEND=uv` 改用已自行安裝的 uv
建立 venv;沒有 uv 時安裝器會停止,不會替你下載 uv。`AI_DOCUMENT_MEDIA_INSTALL_TIKA=1`
只是額外安裝 optional 的 Python `tika` client,不會準備 Tika server JAR。

這個選項不會下載或初始化 Docling／faster-whisper model。使用前由人手把 model 放在本機,
以 `WHISPER_MODEL_DIR` 等 local path 指定,並讓 skill 以 offline mode 執行;沒有本機 model
就回報 blocker,不可讓工具連網下載。Tika 只有在 `TIKA_SERVER_JAR` 指向已存在的本機 JAR
時才可作 fallback。安裝完成後可用下面指令確認 venv 與 package,這些 probe 不會寫入檔案:

```bash
AI_DOCUMENT_MEDIA_VENV="${AI_DOCUMENT_MEDIA_VENV:-$HOME/.local/share/ai-document-media/venv}"
"$AI_DOCUMENT_MEDIA_VENV/bin/python" -c 'import docling, faster_whisper'
```

### 4. 重新載入 zsh

安裝完成後執行:

```bash
source ~/.zshrc
```

也可以關掉目前終端機並開一個新的 zsh。確認 Node/npm 與 `npx` 可用後才進入下一步。

### 5. 安裝／同步 oh-my-opencode-slim

chezmoi 已經管理 OpenCode core config 與 oh-my-opencode-slim agent preset。執行 OmO
installer 時,它偵測到已部署的 config 會保留 config,此處是用 installer 安裝／同步
bundled skills:

```bash
npx --yes oh-my-opencode-slim@latest install --no-tui --skills=yes --background-subagents=no --companion=no
```

OmO 的 `@claude-code` ACP adapter 由 config 以 `npx` 按需啟動,不需要
`npm i -g @agentclientprotocol/claude-agent-acp`。Herdr 是選配;只有想要 live pane 才
在 `install-tools.sh` 選取 Herdr，安裝後執行:

```bash
herdr integration install opencode
```

Herdr 不在跨機器必要設定內,也不影響 OmO background agents。

### 6. 登入 Claude Code

先檢查目前這台機器的登入狀態:

```bash
claude auth status
```

只有顯示尚未登入時才執行 `claude auth login`,並由人類完成 OAuth。Claude OAuth 登入
狀態不能搬到另一台機器,也不能放進 repo。

### 7. 驗證 OpenCode 與 Claude Code ACP

啟動 OpenCode:

```bash
opencode
```

在互動介面輸入 `ping all agents`;需要單獨確認 Claude 時,再用 `@claude-code` 做一個
短 smoke test。這個驗證只確認 agent 路徑,不代表所有 optional MCP 都已安裝。

### 8. MCP、skills 與 Claude plugin

MCP 不歸 chezmoi 管。chrome-devtools、context7、gh_grep、codegraph 四個 server 在
agent-config 的 `mcp.yaml`,由 skillshare 寫進 Claude Code、Codex、OpenCode 三邊。
`~/.config/skillshare/config.yaml` 由 chezmoi 放好(`create_`,init 之後就不再動它)。
新機器與已 init 的機器都跑同一項:`install-tools-ai.sh` 的「agent-config」(見第 3 步)。
之後要手動更新也是同樣兩行:

```bash
skillshare pull              # 拉 agent-config 最新的 skills
skillshare sync mcp -g       # pull 不會同步 MCP,這行不能省
```

從舊版 dotfiles 升上來的機器,`chezmoi apply` 會先刪掉舊 chezmoi 寫的 MCP 條目;手動加過的
條目要先處理,步驟見 [已部署機器上的舊條目](ai-agent-setup.md#已部署機器上的舊條目)。

別人的 skills 用 `npx skills@latest add <帳號>/<repo>`;目前文件記錄的來源可按需要重跑:

```bash
npx skills@latest add mattpocock/skills
npx skills@latest add Leonxlnx/taste-skill
npx skills@latest add vercel-labs/skills
npx skills@latest add JuliusBrussee/caveman -g -y -s caveman -a '*'
```

自己的 skill 依
[skill 操作說明](ai-agent-setup.md#2-skill) clone 後拉 symlink。Claude plugin 在 Claude
裡輸入 `/plugin` 安裝與更新;`chrome-devtools-mcp` 不要啟用,repo 的 `modify_` 會把它
關掉;其他 plugin 依該 marketplace 與官方 marketplace 的提示逐一安裝。MCP、skills、plugin 的範圍與限制見 [ai-agent-setup.md](ai-agent-setup.md) 的
[MCP](ai-agent-setup.md#3-mcp)、[skill](ai-agent-setup.md#2-skill)、[plugin](ai-agent-setup.md#4-plugin)。

### 9. 各 repo 的 codegraph setup

codegraph index 是每個 repo 自己的狀態,不會隨 dotfiles 一起搬。先把需要工作的 repo
放回 `~/code`,再對每個 repo 執行:

```bash
codegraph-setup-repo ~/code/<repo>
```

若已在 `~/.config/codegraph/repos` 建好清單,可執行 `codegraph-setup-repo` 一次處理
清單。這支指令會建索引,並在 repo 使用 husky 搶走 `core.hooksPath` 時補
`post-checkout`／`post-merge` 轉接;已經有索引的 repo 會跳過。新 worktree 的索引由
chezmoi 部署的共用 hook 複製與同步,但新 repo 本身仍要跑一次 setup。

清單檔是機器本地檔案,不進公開 repo;需要時自行建立:

```bash
mkdir -p ~/.config/codegraph
cat > ~/.config/codegraph/repos <<'EOF'
/home/<你>/code/<前端>
/home/<你>/code/<主後端>
EOF
```

沒有清單也能對單一 repo 傳入路徑;新機器第一次不要只靠掃描,因為尚未有任何
`.codegraph/`。若是不想在某個 repo 放 hook 轉接,不要跑 setup,在 worktree 需要時手動:

```bash
cd <新 worktree>
cp -r <主 checkout>/.codegraph .codegraph && codegraph sync -q
```

不要用 `.git/config` 覆蓋共用 `core.hooksPath`:套件安裝可能把 husky 設定寫回去,而且
會讓 husky 自己的 hook 停止運作。完整的 worktree 同步與 hook 判斷仍見
[ai-agent-setup.md 的 codegraph 細節](ai-agent-setup.md#codegraph-的索引是每個專案自己的事)。

不要把 repo 名稱清單、index、hook 轉接或 SSH private key 提交到公開 repo。完整的
索引與 hook 內容都不進版控。

## 恢復邊界

| 類別 | 內容 |
|---|---|
| **chezmoi 自動恢復** | 規則、OpenCode core config、agent preset、`modify_` 設定、`chrome-mcp`、Git 全域 hooks、`codegraph-setup-repo`。 |
| **需登入或人工選擇** | chezmoi 的 4 個憑證與 2 個 Git 身分欄位、Claude OAuth、SSH private key、MCP(skillshare)、skills、Claude plugin。 |
| **各 repo 需重跑** | `codegraph-setup-repo ~/code/<repo>`、該 repo 的 index 與必要 hook 轉接。 |

SSH private key 永遠不進 repo。Claude OAuth 永遠不搬移、不進 repo。Herdr 只有 live pane
需求才安裝,不屬於 OmO 的必要背景 agent 設定。Docker 與 swap 不是必要設定：Docker 可能
移除衝突套件並修改系統，swap 預設建立 2G `/swapfile` 並寫入 `/etc/fstab`，請先確認主機
資源與用途。

## 設定驗證

依序做基本驗證:

```bash
chezmoi verify
opencode
npx --yes oh-my-opencode-slim@latest doctor
```

在 `opencode` 互動介面輸入 `ping all agents`,必要時再做 `@claude-code` smoke test。
`doctor` 是需要時可補跑的 OmO 診斷。`chezmoi verify` 若報出與本次重建無關的 drift,
先依該檔案所屬 repo 的情況處理,不要為了讓驗證變綠就覆蓋未知的本機修改。

其他現況查詢:

```bash
claude auth status
skillshare mcp list
npx skills@latest list -g
```

上述檢查只確認工具狀態,不會把憑證寫回文件或 repo。
