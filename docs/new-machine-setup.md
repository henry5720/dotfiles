# 新機器設定 Runbook

## 適用範圍

Ubuntu（WSL2、雲端主機、平板上的 proot Ubuntu）與原生 Termux。目的是把一台全新的機器帶到
這個 repo 描述的 shell、chezmoi 與 AI-agent 工作環境。

```text
機器本身的前置 →（可選）更新系統、放 SSH key → chezmoi 官方安裝指令（init --apply）→ 需要才跑的手動腳本 → AI 工具收尾（Ubuntu）
```

`chezmoi init --apply` 之後的套件、zsh、選裝工具全由 chezmoi 處理；這份只寫 chezmoi 之外要人做的事。
Windows 端的 `.wslconfig`、SSH private key、各服務帳號登入、秘密不會由文件代替你決定，
需要人工確認的地方會停下來。

## 交給 coding agent

第 1、2 步要人做（裝 app、放 key、填憑證、選工具）。第 4 步之後可以把以下 prompt 貼給
**已經能正常工作的 coding agent**：

```text
請依照 ~/.local/share/chezmoi/docs/new-machine-setup.md 第 4 步之後的順序,協助我完成這台
機器的 AI 工具設定。你只能執行文件中已列出的可自動化步驟,每完成一步就執行該步的
驗證並回報結果,再進下一步。

遇到 sudo 密碼或權限、任何秘密/API key/password、Claude OAuth、SSH key、需要瀏覽器
登入、或 optional choice 時,請先暫停並詢問我,不要猜測或代替我選擇。不要讀取、列印、
儲存、複製或提交任何憑證;不要把 Claude OAuth 或 SSH private key 寫進 repo。
不要執行 tools 或 chezmoi init --prompt(會跳出選單要人勾)。
要改選裝工具就請我自己打 tools。

完成後只回報每一步的結果與尚未處理的人工項目。
```

## 1. 前置（機器本身）

### WSL2

- Windows 裝好 WSL2 Ubuntu，進到一般使用者的 shell，帳號能 `sudo`。
- 終端機字型裝在 Windows 那側，見 [wsl/command.md](../wsl/command.md#終端機字型hack-nerd-font)。
- `.wslconfig` 參考 [`wsl/.wslconfig`](../wsl/.wslconfig)，手動放到 Windows 使用者目錄。

### 雲端主機

能 SSH 進去、帳號能 `sudo` 就好。字型裝在你連線那端的終端機。

### 平板：原生 Termux 與 proot Ubuntu

1. 從 [F-Droid](https://f-droid.org/packages/com.termux/) 裝 Termux。Termux 的外掛要跟本體
   同一個來源的簽章，不要混用 Play 商店版。不要裝 Termux:Styling：它換字型會蓋掉 chezmoi
   放的 `~/.termux/font.ttf`。
2. 要桌面才需要：從 [termux-x11 的 nightly release](https://github.com/termux/termux-x11/releases/tag/nightly)
   裝 Termux:X11 app（`termux-x11-universal-debug.apk`，它不在 F-Droid）。
3. 在原生 Termux 跑第 2 步 Termux 那行。要用手機儲存空間時另外跑 `termux-setup-storage`（會跳 Android 權限對話框）。
4. 要桌面：`bash ~/.local/share/chezmoi/script/termux/install-desktop.sh`，結尾會提示在
   xfce 終端機手動選 `Hack Nerd Font`。啟動桌面用同目錄的 `startxfce_native.sh`。
5. 要 proot Ubuntu（開發環境放這裡）：

   ```bash
   bash ~/.local/share/chezmoi/script/termux/setup-proot-ubuntu.sh   # 使用者名稱預設 henry
   proot-distro login ubuntu --user henry
   ```

   腳本會建一般使用者、裝 sudo 與 curl、設密碼，可以重跑。登入後把它當成一台 Ubuntu，跑第 2 步
   Ubuntu 那行。

## 2. 裝 chezmoi 與 dotfiles

### 2.1（可選）更新系統

跳過也裝得起來。以 Ubuntu 為例（其他系統換成自己的套件管理器）：

```bash
sudo apt update && sudo apt upgrade -y
```

Termux 不用另外做：第 2.3 節那行本來就先 `pkg upgrade`。之後的 `chezmoi apply` 在 Ubuntu 只裝缺的
套件、不升級；在 Termux 有缺的套件要裝時會先 `pkg upgrade`（Termux 不支援部分升級），不缺就不動。

### 2.2（可選）放 SSH key

clone、`chezmoi update` 走 HTTPS，不用 key；要 **push**（dotfiles、agent-config）或從這台
**連其他機器**（ssh config 裡的 Tailscale 主機、平板）才需要。可以裝完再放。

所有機器共用同一把 key，檔名一定要是 `~/.ssh/henry5720`：ssh config 對 GitHub 和所有
Tailscale 主機都寫死這個 IdentityFile。在舊機器 `cat ~/.ssh/henry5720` 複製內容，然後在新機器：

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat > ~/.ssh/henry5720            # 貼上整段（含 BEGIN/END 兩行），換行後 Ctrl-D
chmod 600 ~/.ssh/henry5720
ssh-keygen -y -f ~/.ssh/henry5720 > ~/.ssh/henry5720.pub   # 能產生就代表 key 格式對
```

放好後跑一次 `chezmoi apply`（還沒裝 chezmoi 就等 2.3 一起做）：

- `~/.ssh/config` 由 chezmoi 部署，GitHub 與各主機開始用這把 key。
- **原生 Termux**：公鑰會被加進 `~/.ssh/authorized_keys`（已經有就跳過），ssh config 的
  `phone`／`pad` 才連得進來。
- 這把 key 要在 GitHub 的 [SSH keys](https://github.com/settings/keys) 裡，`ssh -T git@github.com`
  會回 `successfully authenticated` 就對了。

push 自動走 SSH：chezmoi 部署的 `~/.gitconfig` 有 `url."git@github.com:".pushInsteadOf`，
HTTPS clone 下來的 repo push 時改寫成 `git@github.com:`，remote 不用改。以前用 SSH clone 的機器
remote 本來就是 `git@`，照常運作。

### 2.3 一行指令裝好

chezmoi 官方的[新機器一行指令](https://www.chezmoi.io/user-guide/daily-operations/#install-chezmoi-and-your-dotfiles-on-a-new-machine-with-a-single-command)：

| 機器 | 指令 |
|---|---|
| Ubuntu（WSL、雲端主機、proot Ubuntu） | `sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply henry5720` |
| 原生 Termux | `pkg upgrade && pkg install chezmoi && chezmoi init --apply henry5720` |

- Ubuntu 那行在家目錄跑：`/lb` 把 chezmoi 裝到**目前目錄**的 `.local/bin`（不帶 `/lb` 會裝到 `./bin`）。
- 不帶 `--ssh`：dotfiles 是公開 repo，chezmoi 用 `https://github.com/henry5720/dotfiles.git` clone，
  不用 key。`--ssh` 一定要 key。
- Termux 先 `pkg upgrade`：Termux 不支援部分升級，套件版本對不上會裝失敗。`get.chezmoi.io`
  在 Android 只支援 arm64，所以 Termux 用 `pkg`。
- 重跑沒事：source 已經在 `~/.local/share/chezmoi` 就不會再 clone。

`chezmoi init` 會問：

- 憑證：`code-server 密碼`、`codex-lb API key`、`Context7 API key`、`WakaTime API key`（後兩者可留空）。
- Git 身分：`git user.name`（預設 `henry`）與 `git user.email`。
- **選裝工具選單（只有 Ubuntu）**：空白鍵勾選、Enter 確定，**預設都不勾**。

憑證只在終端機的 chezmoi prompt 輸入，不要交給 coding agent，不要貼到文件或 repo。值存在
`~/.config/chezmoi/chezmoi.toml`，不是 git 內容。

選單上每一項後面都有一句說明，清單和說明在
[`home/.chezmoitemplates/tool-menu`](../home/.chezmoitemplates/tool-menu)。WSL 和非 amd64 的機器不列
`headless-chrome`、`playwright-cli`。

apply 完重開終端機（或 `exec zsh`）就是 zsh + p10k。原生 Termux 到這裡就結束了。

### 2.4 之後想加減工具

```bash
tools   # 重出選單，預設帶現在的勾選；Enter 之後直接 apply
```

- 只會跳出選單：憑證和 Git 身分已經存過就不再問。要改它們用 `chezmoi edit-config` 改
  `[data]` 那一行再 `chezmoi apply`。
- **取消勾選不會解除安裝**，只是之後不再管它。要移除用那個工具自己的方式，例如
  `sudo apt remove btop`、`npm uninstall -g <套件>`。
- 選單以後加了新工具，舊機器不會自己問，打 `tools` 勾它才會裝。
- 已經裝過的工具不會重裝；chezmoi 也不負責更新選裝工具。

## 3. 需要才跑的手動腳本

這些會改系統，所以不交給 chezmoi：

```bash
bash ~/.local/share/chezmoi/script/ubuntu/install-docker.sh   # Docker Engine；會移除衝突套件
bash ~/.local/share/chezmoi/script/ubuntu/setup-swap.sh 2G    # swapfile，寫入 /etc/fstab
```

WSL 通常優先用 Docker Desktop + WSL integration，腳本在 WSL 會先要你確認。

## 4. AI 工具收尾（Ubuntu）

### 4.1 headless Chrome（選了 `headless-chrome` 才有）

裝的是 Google 官方的 `.deb`，外加中文和 emoji 字型（沒裝的話截圖會是方框）。怎麼開、跟桌機的
`chrome-mcp` 怎麼輪流使用 9222，見 agent-config 的 chrome-mcp skill。

### 4.2 安裝／同步 oh-my-opencode-slim

chezmoi 已經管理 OpenCode core config 與 oh-my-opencode-slim agent preset。執行 OmO
installer 時，它偵測到已部署的 config 會保留 config，這裡是用 installer 安裝／同步
bundled skills（要先有 `npx`，也就是勾了 `nvm`）：

```bash
npx --yes oh-my-opencode-slim@latest install --no-tui --skills=yes --background-subagents=no --companion=no
```

OmO 的 `@claude-code` ACP adapter 由 config 以 `npx` 按需啟動，不需要
`npm i -g @agentclientprotocol/claude-agent-acp`。有勾 `herdr` 而且想要 live pane 才執行：

```bash
herdr integration install opencode
```

### 4.3 登入 Claude Code

```bash
claude auth status
```

只有顯示尚未登入時才執行 `claude auth login`，並由人類完成 OAuth。Claude OAuth 登入
狀態不能搬到另一台機器，也不能放進 repo。個人入口要另外登入並填妥 personal model，見
[AI profile routing](ai-profile-routing.md)，未完成前不要視為可用。

### 4.4 驗證 OpenCode 與 Claude Code ACP

啟動 `opencode`，在互動介面輸入 `ping all agents`；需要單獨確認 Claude 時，再用
`@claude-code` 做一個短 smoke test。這個驗證只確認 agent 路徑，不代表所有 optional MCP
都已安裝。

### 4.5 MCP、skills 與 Claude plugin

MCP 不歸 chezmoi 管。server 清單在 agent-config 的 `mcp.yaml`（`skillshare mcp list` 看得到），
由 skillshare 寫進 Claude Code、Codex、OpenCode 三邊。選單的 `agent-config` 在 apply 時
裝 skillshare、從 agent-config init 並 sync MCP；已經 init 過的機器會跳過。之後要更新：

```bash
skillshare pull              # 拉 agent-config 最新的 skills
skillshare sync mcp -g       # pull 不會同步 MCP,這行不能省
```

從舊版 dotfiles 升上來的機器，`chezmoi apply` 會先刪掉舊 chezmoi 寫的 MCP 條目；手動加過的
條目要先處理，步驟見 agent-config 的[〈從舊版 dotfiles 升上來的機器〉](https://github.com/henry5720/agent-config/blob/main/docs/mcp.md#從舊版-dotfiles-升上來的機器)。

skills 怎麼新增或更新見 [agent-config 的 README](https://github.com/henry5720/agent-config#日常操作)。Claude plugin 在 Claude
裡輸入 `/plugin` 安裝與更新；`chrome-devtools-mcp` 不要啟用，repo 的 `modify_` 會把它
關掉；其他 plugin 依該 marketplace 與官方 marketplace 的提示逐一安裝。範圍與限制：[skill](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md)、[MCP](https://github.com/henry5720/agent-config/blob/main/docs/mcp.md)（在 agent-config）、
[plugin](ai-agent-setup.md#4-plugin)。

claude-hud 不在官方 marketplace，要先加它自己的：

```bash
claude plugin marketplace add jarrodwatts/claude-hud
claude plugin install claude-hud@claude-hud
```

裝完在 Claude 裡跑 `/claude-hud:setup` 寫 `statusLine`。它會把 node 的**絕對路徑**寫進去
（nvm 就是 `~/.nvm/versions/node/<版本>/bin/node`），之後 nvm 換版本、刪掉舊版，HUD 就會消失，
重跑 `/claude-hud:setup` 即可。顯示偏好 `~/.claude/plugins/claude-hud/config.json` 由 chezmoi
放好，用 `/claude-hud:configure` 改過之後要 `chezmoi re-add` 收回來。

### 4.6 各 repo 的 codegraph setup

codegraph index 是每個 repo 自己的狀態，不會隨 dotfiles 一起搬。先把需要工作的 repo
放回 `~/code`，再對每個 repo 執行：

```bash
codegraph-setup-repo ~/code/<repo>
```

若已在 `~/.config/codegraph/repos` 建好清單，可執行 `codegraph-setup-repo` 一次處理
清單。這支指令會建索引，並在 repo 使用 husky 搶走 `core.hooksPath` 時補
`post-checkout`／`post-merge` 轉接；已經有索引的 repo 會跳過。新 worktree 的索引由
chezmoi 部署的共用 hook 複製與同步，但新 repo 本身仍要跑一次 setup。

清單檔是機器本地檔案，不進公開 repo；需要時自行建立：

```bash
mkdir -p ~/.config/codegraph
cat > ~/.config/codegraph/repos <<'EOF'
/home/<你>/code/<前端>
/home/<你>/code/<主後端>
EOF
```

沒有清單也能對單一 repo 傳入路徑；新機器第一次不要只靠掃描，因為尚未有任何
`.codegraph/`。若是不想在某個 repo 放 hook 轉接，不要跑 setup，在 worktree 需要時手動：

```bash
cd <新 worktree>
cp -r <主 checkout>/.codegraph .codegraph && codegraph sync -q
```

不要用 `.git/config` 覆蓋共用 `core.hooksPath`：套件安裝可能把 husky 設定寫回去，而且
會讓 husky 自己的 hook 停止運作。完整的 worktree 同步與 hook 判斷見
[ai-agent-setup.md 的 codegraph 細節](ai-agent-setup.md#codegraph-的索引是每個專案自己的事)。

## 恢復邊界

| 類別 | 內容 |
|---|---|
| **chezmoi 自動恢復** | 基底套件、勾選的選裝工具、zsh／p10k／插件、預設 shell、規則、OpenCode core config、agent preset、`modify_` 設定、`chrome-mcp` 的 symlink、Git 全域 hooks、`codegraph-setup-repo`、Termux 字型。 |
| **需登入或人工選擇** | 平板上的 app（Termux、Termux:X11）、Windows 字型、SSH private key、chezmoi 的 4 個憑證與 2 個 Git 身分欄位、選裝工具選單、Claude OAuth、`gh auth login`、Claude plugin、AI 解析的 model。 |
| **手動腳本** | Docker、swap、平板桌面、proot Ubuntu 的使用者。 |
| **各 repo 需重跑** | `codegraph-setup-repo ~/code/<repo>`、該 repo 的 index 與必要 hook 轉接。 |

SSH private key 永遠不進 repo。Claude OAuth 永遠不搬移、不進 repo。

## 設定驗證

```bash
chezmoi verify
opencode
npx --yes oh-my-opencode-slim@latest doctor
```

`opencode` 裡的互動驗證同 4.4。`doctor` 是需要時可補跑的 OmO 診斷。`chezmoi verify` 若報出
與本次重建無關的 drift，先依該檔案所屬 repo 的情況處理，不要為了讓驗證變綠就覆蓋未知的本機修改。

其他現況查詢：

```bash
claude auth status
skillshare mcp list
skillshare list -v
```

上述檢查只確認工具狀態，不會把憑證寫回文件或 repo。
