# 新機器設定 Runbook

## 適用範圍

Linux、macOS、原生 Termux 與 Windows 主機（原生 Windows，WSL 的外層或沒有 WSL 的開發機）。Linux 以 Ubuntu 等 Debian 系最完整，其他發行版也裝得起來（走 apt 的工具改用
mise）；實體機、雲端主機、WSL2、平板上的 proot Ubuntu 都是同一套步驟，有沒有 root 都行。
目的是把一台全新的機器帶到這個 repo 描述的 shell、chezmoi 與 AI-agent 工作環境。

| 機器 | 怎麼判斷 | chezmoi 會做什麼 |
|---|---|---|
| Debian 系 Linux（Ubuntu 等；實體機、雲端主機、WSL2、proot 都算） | `/etc/os-release` 的 ID 或 ID_LIKE 有 `debian` | 基底套件、用途（完整／精簡／自訂）與選裝工具選單（zsh 等都在選單裡）；eza、fzf 這類單一執行檔的 CLI 工具用 [mise](https://mise.jdx.dev/) 裝到家目錄，其他走 apt；headless Chrome、playwright-cli 只有 amd64、非 WSL 裝得了，其他標「裝不了」、預設不勾、勾了略過（WSL 看 kernel 版本含 `microsoft`；agent 要用瀏覽器時到已配置主機做，見[瀏覽器](remote-access/browser.md)） |
| 非 Debian 系 Linux（Fedora 等） | `/etc/os-release` 的 ID、ID_LIKE 沒有 `debian` | 同上，但走 apt 的選裝工具改用 [mise](https://mise.jdx.dev/) 裝到家目錄；headless Chrome、playwright-cli 標裝不了 |
| macOS | `chezmoi.os` 是 `darwin` | 用途與選裝工具選單（headless Chrome、playwright-cli 標裝不了），套件用 `brew bundle` 裝（tailscale 是官方 app 的 cask）；Homebrew 要先自己裝 |
| 原生 Termux | `chezmoi.os` 是 `android` | 基底套件、用途與選裝工具選單（跟 Linux 同一套，也有 `tools` 指令），選裝工具走 `pkg`；tailscale、btop、code-server、headless Chrome、playwright-cli、coding agent、agent-config、codegraph 標裝不了（開發環境放 proot Ubuntu）；終端機字型、`authorized_keys` |
| Windows 主機 | `chezmoi.os` 是 `windows` | 用途與選裝工具選單（跟 Linux 同一套，也有 PowerShell 版的 `tools`），CLI 用 mise、app（pwsh 7、Windows Terminal、tailscale）用 winget 裝；zsh、btop、coding agent 這類只有 sh 安裝腳本的標裝不了；只部署白名單上的檔案（`.wslconfig`、starship 設定、PowerShell profile、Windows Terminal 的預設設定檔與字型、mise 清單），只跑 `.ps1` 腳本；見[Windows 主機](install/windows.md) |

機器種類、有沒有 root 都自動判斷，不用回答。不能 `sudo` 的帳號要 root 的步驟印出手動方式後略過，見[沒有 root 的機器](install/no-root-machine.md)。

```text
機器本身的前置 →（可選）更新系統、放 SSH key → chezmoi 官方安裝指令（init --apply）→ 需要才跑的手動腳本 → AI 工具收尾（Ubuntu）
```

`chezmoi init --apply` 之後的套件、zsh、選裝工具全由 chezmoi 處理；這份只寫 chezmoi 之外要人做的事。
SSH private key、各服務帳號登入、秘密不會由文件代替你決定，
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

### Linux（Ubuntu 等）

拿到一個一般使用者的 shell 就好：本機、SSH 進雲端主機、WSL2 都一樣。帳號不一定要能 `sudo`
（見[沒有 root 的機器](install/no-root-machine.md)）。字型裝在你看畫面的那個終端機，不是這台（見[終端機字型](install/fonts.md)）。

WSL2 另外做兩件事（都在 Windows 那側）：

- 終端機字型裝在 Windows，見[終端機字型](install/fonts.md#windows-terminal)。
- `.wslconfig` 由 Windows 主機上的 chezmoi 部署：在 Windows 照下面「[Windows 主機](#windows-主機)」那節 `chezmoi init --apply`。

平板上的 proot Ubuntu 先照下面「平板」那節進到 proot，之後跟一般 Linux 一樣。

### macOS

1. 照 [Homebrew 官網](https://brew.sh/)的指令裝 Homebrew（要管理員密碼，會順便裝 Xcode Command Line Tools，
   git、python3 由它提供），裝完照它印的 **Next steps** 把 `brew shellenv` 加進 `~/.zprofile`，開新的終端機。
   chezmoi 不裝 Homebrew：它要互動輸入密碼。套件之後由 chezmoi 用 `brew bundle` 裝。
2. 要連自己的機器就在選單勾 tailscale（完整會勾），chezmoi 用 brew cask `tailscale-app` 裝官方 app，裝完自己開 app 登入。
   已經從官網或 App Store 裝過的不用勾：勾了 brew 會因為 `/Applications/Tailscale.app` 已經在而裝不起來，
   apply 印一行「略過 tailscale-app」照樣跑完、其他套件照裝；要改由 brew 管就先刪掉那份 app 再 `chezmoi apply`。
3. 預設 shell 本來就是 zsh，chezmoi 不改。終端機字型自己裝 Nerd Font，見[終端機字型](install/fonts.md#macos)。

### Windows 主機

Windows 跟它裡面的 WSL 是兩台機器，各自 clone、各自 `chezmoi init`；沒有 WSL、Windows 本身就是開發機也照這節。
這節一路做到裝好，不用再看第 2 步。

1. 在 PowerShell 用 winget 裝 chezmoi：

   ```powershell
   winget install twpayne.chezmoi
   ```

   其他的（mise、pwsh 7、Windows Terminal，以及選單勾的 CLI 與 tailscale）由 chezmoi apply 裝。
   winget 裝的 pwsh 是 MSIX 版，入口是 `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`，沒有
   `C:\Program Files\PowerShell\7`。git 這類其他 GUI app 照舊從官網裝。
2. 把 Documents 移出 OneDrive 備份，不然 PowerShell 讀不到 chezmoi 部署的 profile：見[Documents 移出 OneDrive](install/windows.md#documents-移出-onedrive)。
3. Hack Nerd Font 照[終端機字型](install/fonts.md#windows-terminal)手動右鍵「安裝」。
4. 讓 profile 與 `tools` 跑得動：Windows client 的 Windows PowerShell 5.1 預設執行原則是 `Restricted`，
   本機的 `.ps1` 都不能跑（chezmoi 的安裝腳本自己繞過，不受影響）：

   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```

5. 開新的 PowerShell（winget 剛改的 PATH 才生效），跑：

   ```powershell
   chezmoi init --apply henry5720
   ```

   跟 Linux 一樣問用途、出選單（[用途與憑證](install/machine-use.md)），Enter 是精簡；git 身分不問。
   要跳 UAC 的（pwsh 7、tailscale）會跳出來要你按「是」。
   部署了什麼、裝完怎麼用，見[Windows 主機](install/windows.md)；之後要加減工具打 `tools`。
6. 開一次 Windows Terminal 再關掉，再跑一次 `chezmoi apply`：pwsh 7 是上一步才裝的，Terminal 開過才會
   產生它的設定檔；上一步的 apply 找不到就只設字型，這次才把預設分頁改成 pwsh 7。
   沒做這步，新分頁會是 `powershell`（5.1）—— 它也讀同一份 profile、一樣有 starship，看提示列分不出來，
   看分頁標題（「PowerShell」是 7，「Windows PowerShell」是 5.1）。
7. 這台本來有手寫的 `$PROFILE`（例如 henry-desktop 用 oh-my-posh 那份）就清掉，不然會蓋掉 starship：見[從舊的手寫 profile 遷移](install/windows.md#從舊的手寫-profile-遷移)。
   以前照 Runbook 用 winget 裝的 starship、fastfetch、zoxide 可以 `winget uninstall` 掉，改由 mise 管
   （留著也行：profile 先找 mise 那份）。

### 平板：原生 Termux 與 proot Ubuntu

1. 從 [F-Droid](https://f-droid.org/packages/com.termux/) 裝 Termux。Termux 的外掛要跟本體
   同一個來源的簽章，不要混用 Play 商店版。不要裝 Termux:Styling：它換字型會蓋掉 chezmoi
   放的 `~/.termux/font.ttf`。
2. 要桌面才需要：從 [termux-x11 的 nightly release](https://github.com/termux/termux-x11/releases/tag/nightly)
   裝 Termux:X11 app（`termux-x11-universal-debug.apk`，它不在 F-Droid）。
3. 在原生 Termux 跑第 2 步 Termux 那行。要用手機儲存空間時另外跑 `termux-setup-storage`（會跳 Android 權限對話框）。
4. 裝 [Tailscale 的 Android app](https://tailscale.com/download/android) 並登入：Termux 裡裝不了 tailscale
   （選單上標裝不了），整台平板由這個 app 上 tailnet。
5. 要讓別台用 ssh config 的 `pad`／`phone` 連進來：放好 SSH key（第 2.2 節）後在 Termux 跑 `sshd`
   （聽 8022 port）。sshd 不會自己開機啟動，Termux 被關掉後要再跑一次。
6. 要桌面：`bash ~/.local/share/chezmoi/script/termux/install-desktop.sh`，結尾會提示在
   xfce 終端機手動選 `Hack Nerd Font`。啟動桌面用同目錄的 `startxfce_native.sh`。
7. 要 proot Ubuntu（開發環境放這裡）：

   ```bash
   bash ~/.local/share/chezmoi/script/termux/setup-proot-ubuntu.sh   # 使用者名稱預設 henry
   proot-distro login ubuntu --user henry
   ```

   腳本會建一般使用者、裝 sudo 與 curl、設密碼，可以重跑。登入後把它當成一台 Ubuntu，跑第 2 步
   Linux 那行。

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
| Linux（Ubuntu 等；實體機、雲端主機、WSL2、proot 都一樣） | `sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply henry5720` |
| 原生 Termux | `pkg upgrade && pkg install chezmoi && chezmoi init --apply henry5720` |
| macOS（先做完第 1 步的 Homebrew） | `brew install chezmoi && chezmoi init --apply henry5720` |

- Linux 那行在家目錄跑：`/lb` 把 chezmoi 裝到**目前目錄**的 `.local/bin`（不帶 `/lb` 會裝到 `./bin`）。
- 不帶 `--ssh`：dotfiles 是公開 repo，chezmoi 用 `https://github.com/henry5720/dotfiles.git` clone，
  不用 key。`--ssh` 一定要 key。
- Termux 先 `pkg upgrade`：Termux 不支援部分升級，套件版本對不上會裝失敗。`get.chezmoi.io`
  在 Android 只支援 arm64，所以 Termux 用 `pkg`。
- 重跑沒事：source 已經在 `~/.local/share/chezmoi` 就不會再 clone。

`chezmoi init` 會問：

- **用途（只有 Linux 與 macOS）**：完整、精簡或自訂，決定下一題預設勾哪些。按一個字母 `f`／`m`／`c`（按下就送出，不用 Enter），直接 Enter 是精簡；config 存 `full`／`minimal`／`custom`。選錯用途時在下一題的選單按 Ctrl+C，整個 init 不存檔，重來一次（Esc 會照目前勾選送出，不是取消）。
- **選裝工具選單（只有 Linux 與 macOS）**：空白鍵勾選、Enter 確定，已照用途勾好，可以再調。基底只有 git、curl、jq、python3，
  zsh、starship 提示列也是選裝工具，要在這裡勾。
- 憑證：只問勾了的工具用得到的，精簡一個都不問。
- Git 身分：`git user.name`（預設 `henry`）與 `git user.email`，每台都問。

各用途預設勾哪些、勾哪個工具會問哪個憑證、config 怎麼存用途，見[用途與憑證](install/machine-use.md)。

要一行裝完、不回答用途和選單（例如別人給的機器），把用途和 email 帶在指令上：

```bash
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply --promptDefaults \
  --promptChoice "用途：按一個字母（full 完整／minimal 精簡：只要 shell 體驗／custom 自訂）=m" \
  --promptString "git user.email=<email>" henry5720
```

`--promptDefaults` 讓沒帶的問題都用預設值；用途的提示文字要一字不差。精簡用不到憑證，所以只剩 git email 要給。
之後勾了用得到憑證的工具，`tools` 會在那時問。

憑證只在終端機的 chezmoi prompt 輸入，不要交給 coding agent，不要貼到文件或 repo。值存在
`~/.config/chezmoi/chezmoi.toml`，不是 git 內容。

選單上每一項後面都有一句說明，清單和說明在
[`home/.chezmoitemplates/tool-menu`](../home/.chezmoitemplates/tool-menu)。這台不建議或裝不了的，說明後面標原因、
預設不勾；裝不了的勾了會略過，apply 最後列出原因（見[用途與憑證〈環境〉](install/machine-use.md#環境不建議裝不了)）。
WSL、非 amd64 的機器裝不了 `headless-chrome`、`playwright-cli`；macOS 裝不了 `headless-chrome`、`playwright-cli`。
WSL、proot Ubuntu 的 `tailscale` 標不建議：網路借外層那份 Tailscale，一台實體機只裝一份、裝在最外層。
macOS 有勾的工具能用 brew 裝的都交給 `brew bundle`（清單在 `home/.chezmoidata/packages.yaml` 的 darwin 欄），
herdr、Claude Code、Codex、OpenCode、skillshare、wakatime-cli 照原本的官方 installer。
原生 Termux 有勾的工具走 `pkg`（清單在同一份檔案的 termux 欄，Node 是 `nodejs-lts`），coding agent 這類裝不了的到 proot Ubuntu 裝。

勾了 zsh 和 starship 的話，apply 完重開終端機（或 `exec zsh`）就是 zsh + starship 提示列。原生 Termux 到這裡就結束了。

### 沒有 root 的機器

不能 `sudo` 的帳號也是同一行裝好，要 root 的步驟記進略過彙整。會自動處理什麼、tailscale 登入、連 company-ec2 的專用 key、字型，見[沒有 root 的機器](install/no-root-machine.md)。

### 2.4 裝完之後

裝了什麼、怎麼用見[工具一覽](tools.md)；從別台連進來、開 coding agent 見[操作已配置主機](configured-host.md)。
加減選裝工具、改 key、移除工具，見[改設定與更新](after-install.md)。

## 3. 需要才跑的手動腳本

這些會改系統，所以不交給 chezmoi：

```bash
bash ~/.local/share/chezmoi/script/ubuntu/install-docker.sh   # Docker Engine；會移除衝突套件
bash ~/.local/share/chezmoi/script/ubuntu/setup-swap.sh 2G    # swapfile，寫入 /etc/fstab
```

WSL 通常優先用 Docker Desktop + WSL integration，腳本在 WSL 會先要你確認。

## 4. AI 工具收尾（Ubuntu）

### 4.1 headless Chrome（選了 `headless-chrome` 才有）

裝的是 Google 官方的 `.deb`，外加中文和 emoji 字型（沒裝的話截圖會是方框）。agent 查原因時用
查原因時開在 9222 給 chrome-devtools MCP，指令見[瀏覽器](remote-access/browser.md#headlessagent-自己的瀏覽器)。

### 4.2 安裝／同步 oh-my-opencode-slim

chezmoi 已經管理 OpenCode core config 與 oh-my-opencode-slim agent preset。執行 OmO
installer 時，它偵測到已部署的 config 會保留 config，這裡是用 installer 安裝／同步
bundled skills（要先有 `npx`：勾了 `opencode` 會一併裝 nvm）：

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
[AI profile routing](ai-agent/ai-profile-routing.md)，未完成前不要視為可用。

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
關掉；其他 plugin 依該 marketplace 與官方 marketplace 的提示逐一安裝（WakaTime 的 plugin 由 apply 裝，見 [WakaTime](ai-agent/wakatime.md)）。範圍與限制：[skill](https://github.com/henry5720/agent-config/blob/main/docs/skills/README.md)、[MCP](https://github.com/henry5720/agent-config/blob/main/docs/mcp.md)（在 agent-config）、
[plugin](ai-agent/ai-agent-setup.md#plugin)。

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
[codegraph](ai-agent/codegraph.md#共用-git-hook-怎麼接上)。

### 4.7 WakaTime（勾了 `wakatime` 才有）

第一次開 Codex 要同意 WakaTime 的 hook；裝了什麼、怎麼確認見 [WakaTime](ai-agent/wakatime.md)。

## 恢復邊界

| 類別 | 內容 |
|---|---|
| **chezmoi 自動恢復** | 基底套件、勾選的選裝工具（含 zsh／插件與預設 shell、starship 提示列）、規則、OpenCode core config、agent preset、`modify_` 設定、`personal-chrome-attach` 的 symlink、Git 全域 hooks、`codegraph-setup-repo`、Termux 字型。 |
| **需登入或人工選擇** | 平板上的 app（Termux、Termux:X11）、Windows 字型、SSH private key、chezmoi 的憑證（勾了用得到的工具才問）與 2 個 Git 身分欄位、選裝工具選單、Claude OAuth、`gh auth login`、Claude plugin、Codex WakaTime hook 的首次同意。 |
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
