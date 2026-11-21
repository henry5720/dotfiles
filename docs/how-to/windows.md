# Windows 主機

原生 Windows 由 Windows 原生 chezmoi 管，跟 Linux 用同一個 repo。可以是 WSL 的外層，也可以沒有 WSL、
Windows 本身就是開發機。怎麼裝見[新機器設定](../new-machine-setup.md#windows-主機)。

## 部署什麼

`chezmoi init` 跟其他 OS 一樣問用途、出選裝工具選單（見[用途與憑證](machine-use.md)）；勾到要憑證的工具才問憑證，
git 身分不問（Windows 不部署 `.gitconfig`）。部署的檔案只有 `home/.chezmoiignore` Windows 段白名單上的：

| repo 裡的檔案 | 部署到 | 用途 |
|---|---|---|
| `home/dot_wslconfig` | `%USERPROFILE%\.wslconfig` | WSL2 的記憶體、CPU、網路模式 |
| `home/private_dot_ssh/private_config.tmpl` | `%USERPROFILE%\.ssh\config` | ssh 的 Host，跟 Linux 共用；key 自己放到 `%USERPROFILE%\.ssh` |
| `home/dot_config/starship.toml` | `%USERPROFILE%\.config\starship.toml` | starship 提示列，跟 Linux 共用 |
| `home/dot_config/mise/conf.d/dotfiles.toml.tmpl` | `%USERPROFILE%\.config\mise\conf.d\dotfiles.toml` | 交給 mise 裝的 CLI 清單（zoxide 加上勾了的） |
| `home/dot_local/bin/tools.ps1.tmpl` | `%USERPROFILE%\.local\bin\tools.ps1` | `tools` 指令：重選用途與選裝工具，勾完直接裝 |
| `home/Documents/PowerShell/Profile.ps1.tmpl` | `Documents\PowerShell\Profile.ps1` | pwsh 7 的 all-hosts profile |
| `home/Documents/WindowsPowerShell/Profile.ps1.tmpl` | `Documents\WindowsPowerShell\Profile.ps1` | Windows PowerShell 5.1 的 all-hosts profile |
| `home/dot_config/opencode/modify_private_opencode.json.tmpl`、`oh-my-opencode-slim.json` | `%USERPROFILE%\.config\opencode\` | 勾了 opencode 才部署，跟 Linux 同一份設定（provider、model、plugin、oh-my-opencode-slim 的 preset）；`opencode.json` 的 `mcp` 照現有檔案留著。`routes\personal` 不部署（`opencode-personal` 只有 Linux） |
| `home/dot_claude/modify_settings.json.tmpl`（勾了 claude 才部署） | `%USERPROFILE%\.claude\settings.json` | 跟 Linux 同一份釘的值：官方 chrome-devtools plugin 關掉、`attribution.commit`；hook、statusLine、其他 plugin 開關等 Claude 與其他工具寫的設定原樣保留，兩個值都對時一個 byte 都不動 |
| `home/dot_codex/modify_private_config.toml.tmpl`（勾了 codex 才部署） | `%USERPROFILE%\.codex\config.toml` | 跟 Linux 同一份釘的值：model、provider、權限三個 key、`developer_instructions` 裡的 commit 指引；Codex 自己寫的（信任專案、hook、提示計數器）與 skillshare 寫的 `[mcp_servers.*]` 原樣保留。`personal.config.toml`、`codex-gcp.config.toml` 不部署（`codex-personal`、`codex-gcp` 只有 Linux） |
| `home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/modify_settings.json` | `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`（Store 版 Windows Terminal） | 只改兩個值：預設設定檔是 pwsh 7、預設字型是 Hack Nerd Font；其餘照 Terminal 自己寫的保留，兩個值都對時一個 byte 都不動 |
| `home/private_dot_wakatime.cfg.tmpl`（勾了 wakatime、填了 API key 才部署） | `%USERPROFILE%\.wakatime.cfg` | WakaTime 的 API key，跟 Linux 同一份；兩個 plugin 都讀這裡 |
| `home/AppData/Roaming/skillshare/modify_config.yaml`（勾了 agent-config 才部署） | `%AppData%\skillshare\config.yaml` | skillshare 的設定：只釘 `targets`、`extras` 兩段（照勾的 client 產生，跟 Linux 同一份樣板，路徑換成 Windows 的），其餘照 skillshare 寫的保留 |

apply 時跑的腳本只有 `home/.chezmoiscripts/` 裡的 `.ps1`（sh 腳本不會到 Windows）：

```text
before  install-packages-windows.ps1   winget 裝 mise、pwsh 7、Windows Terminal，勾了 tailscale 也裝（已經裝了就跳過）
（部署上面的檔案）
after   install-agent-config.ps1       勾了 agent-config 才跑：官方 install.ps1 裝 skillshare，從 agent-config init、sync（已經有 %AppData%\skillshare\.git 就跳過）
after   install-mise.ps1               mise install：裝 dotfiles.toml 清單上的 CLI
after   install-official.ps1           勾了 claude、codex 才跑：照選裝工具表下載官方 install.ps1 再執行（已經有 .local\bin\claude.exe、%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe 就跳過）
after   install-wakatime.ps1           勾了 wakatime 才跑：wakatime-cli 放到 .wakatime\（已經有就跳過），再為勾了的 claude、codex 裝 WakaTime plugin（已裝就跳過）
after   sync-skillshare.ps1            勾了 agent-config 才跑：config.yaml 釘的兩段變了（例如多勾一個 client）就 skillshare sync --all
after   zz-env-skipped.ps1             勾了 Windows 裝不了的工具時，列出略過了哪些、為什麼
```

腳本一律用 Windows PowerShell 5.1 跑、只對那個 process 繞過執行原則（`.chezmoi.toml.tmpl` 的 `[interpreters.ps1]`）：
第一次 init 時 pwsh 7 多半還沒裝，Windows client 的 5.1 預設執行原則又是 `Restricted`。裝失敗（winget、mise）只印一行、
apply 照樣跑完，照印出的指令自己補。

兩份 `Profile.ps1` 內容一樣，做的事見[裝了什麼、怎麼用](#裝了什麼怎麼用)。
chezmoi 不碰 `$PROFILE`（`Microsoft.PowerShell_profile.ps1`），機器專屬的設定（例如 API key）寫在那裡，不進 repo。
PowerShell 只從 `[Environment]::GetFolderPath('MyDocuments')` 讀 profile，Documents 在 OneDrive 裡時讀不到
chezmoi 部署的這兩份，見[Documents 移出 OneDrive](#documents-移出-onedrive)。

Terminal 的 `settings.json` 兩個值有一個不對時，那次 apply 會經過 `toPrettyJson` 整份重寫：Terminal 原本的
`//` 註解會消失、key 照字母重排。之後兩個值都對就不再動它。所以第一次 `chezmoi diff` 看到整檔重排是預期的，不是壞掉。

## 裝了什麼、怎麼用

CLI 用 mise 裝、app 用 winget 裝（跟 Linux 寫在同一張選裝工具表 `home/.chezmoidata/tool-table.yaml`），
官方有會自己更新的 installer 的（coding agent）走官方 installer（[ADR 0005](../adr/0005-install-method-by-tool-kind.md)）：

| 工具 | 怎麼裝 | 什麼時候裝 | 常用 |
|---|---|---|---|
| chezmoi | winget（Runbook 手動） | 裝機時 | `chezmoi update` 拿 repo 最新的設定；`chezmoi diff` 沒有輸出就是跟 repo 一致 |
| pwsh（PowerShell 7） | winget | 每台 | 主力 shell，Windows Terminal 預設開它；`powershell`（5.1）讀同一份 profile，用起來一樣 |
| Windows Terminal | winget（Win11 內建就跳過） | 每台 | |
| mise | winget | 每台 | `mise ls` 看裝了什麼；`mise install` 補裝失敗的 |
| zoxide | mise | 每台 | 跳常去的目錄：`z <目錄名片段>`。等於 Linux 上 zsh 外掛的跳目錄，Windows 的 shell 一定是 PowerShell，不用勾 |
| starship、fastfetch、eza、fzf、bat、ripgrep、vim | mise | 精簡、完整 | starship 是提示列（跟 Linux 同一份設定）；fastfetch 在互動開的 shell 印系統資訊，`pwsh -c`、ssh 執行指令不印 |
| gh、cloudflared、ttyd、ffmpeg | mise | 完整或自己勾 | |
| node | mise（Node LTS） | 完整或自己勾 | 給只要 Node 的機器；Linux 也用 mise |
| herdr | mise | 完整或自己勾 | 終端機多工，不搭 coding agent 也能用：`herdr` 開、`ctrl+b q` 離開、再打 `herdr` 接回去 |
| bottom | mise | 完整或自己勾 | 資源監控：`btm` 開、`q` 離開。btop 在 Windows 裝不了（release 只有 Linux 版），改用它 |
| snapclient | mise（官方 release 的 zip）＋ winget（VC++ runtime） | 完整或自己勾 | 收聽朗讀串流：`snapclient --host <tailnet IP>`；VC++ runtime 會跳 UAC。見 [voice-out](remote-access/voice-out.md#windows) |
| tailscale | winget | 完整或自己勾 | 官方 app，裝完自己開 app 登入；會跳 UAC |
| headless-chrome | winget（`Google.Chrome.EXE`，已經有 Chrome 就跳過） | 完整或自己勾 | 就是一般的 Chrome：`chrome.exe` 本身能 `--headless`，playwright-cli 預設找它；Linux 上才是另一支 `.deb` |
| playwright-cli | mise（npm backend 的 `@playwright/cli`，會一併列 Node LTS） | 完整或自己勾 | agent 操作瀏覽器：`playwright-cli -s=<session> open <網址>`，見[瀏覽器](remote-access/browser.md#headlessagent-自己的瀏覽器)；錄影要先自己跑一次 `playwright-cli install-browser ffmpeg` |
| opencode | mise（npm backend 的 `opencode-ai`，會一併列 Node LTS） | 完整或自己勾 | OpenCode 沒有 Windows 的 `install.ps1`，官方文件列了 npm 與 mise；`opencode-ai` 是 OpenCode 1，跟 Linux 那份同一個大版本。它的 postinstall 才會放上真的 `opencode.exe`，清單用 `allow_builds` 放行（mise 預設不跑）；在放行之前裝過的，`opencode --version` 會說 postinstall 沒跑，`mise install -f npm:opencode-ai` 重裝一次。更新跑 `mise upgrade`（`opencode upgrade` 認不出 mise 裝的）。設定見上面的部署表；commit 指引、MCP 要勾 agent-config |
| codegraph | mise（registry 的 `codegraph`，aqua backend 裝官方 release 的 zip，自帶 Node，不列 Node LTS） | 完整或自己勾 | 在 repo 裡 `codegraph init` 建索引，`codegraph status` 看狀態；MCP 由 agent-config 同步，不用跑 `codegraph install`。更新跑 `mise upgrade`，不要用 `codegraph upgrade`（它把 mise 的目錄當成自己的 bundle）。`codegraph-setup-repo` 和自動同步索引的 git hook 是 sh，Windows 沒有，索引要自己 `codegraph sync`。見 [codegraph〈Windows 主機〉](../tools/codegraph.md#windows-主機) |
| agent-config | 官方 [`install.ps1`](https://skillshare.runkids.cc/docs/troubleshooting/windows#how-do-i-install-on-windows) 裝 skillshare ＋ winget 裝 `Git.Git`（init 要 git，已經有就跳過、會跳 UAC） | 完整或自己勾 | 見下面〈agent-config（skillshare）〉 |
| windows-mcp | mise（pipx backend 的 `windows-mcp`，用 uv 裝，會一併列 uv；要的 Python 由 uv 下載） | 完整或自己勾 | 讓 agent 操作這台的桌面。不直接打指令，WSL 的 agent 經 agent-config 的 MCP 設定叫用；見下面〈windows-mcp〉 |
| claude | 官方 [`install.ps1`](https://code.claude.com/docs/en/setup#install-on-native-windows) | 完整或自己勾 | 裝到 `%USERPROFILE%\.local\bin\claude.exe`，之後自己在背景更新（`claude update` 馬上更新）；第一次打 `claude` 照瀏覽器登入。照頁數讀 PDF 要的 `pdftoppm` 由 mise 裝（`poppler`）。設定檔見上面的部署表，跟 WSL 那份各自獨立 |
| codex | 官方 [`install.ps1`](https://learn.chatgpt.com/docs/codex/cli)（Windows 分頁） | 完整或自己勾 | 裝到 `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe`（本體在 `%USERPROFILE%\.codex\packages\standalone`），installer 自己把它加進使用者 PATH；更新打 `codex update`，開 `codex` 時有新版也會問要不要更新（兩者都是重跑官方 install.ps1）；第一次打 `codex` 照瀏覽器登入。設定檔見上面的部署表，跟 WSL 那份各自獨立 |
| wakatime | 官方 release 的 zip 放到 `%USERPROFILE%\.wakatime\`（不走 mise）＋ 勾了的 agent 用官方的兩行指令裝 plugin（會一併列 Node LTS；marketplace 要 git，winget 裝 `Git.Git`，已經有就跳過、會跳 UAC） | 完整或自己勾 | 跟 Linux 一樣，見 [WakaTime](../tools/wakatime.md)。plugin 只認 `.wakatime\wakatime-cli-windows-<arch>.exe`，之後由 plugin 自己更新；`wakatime-cli.exe` 是複製一份（Linux 是 symlink）。plugin 的 hook 用 PATH 上的 `node`（mise 的 shims，PowerShell profile 加進 PATH），從不讀 profile 的地方開 agent 可能找不到 node、送不出紀錄 |

zsh、btop、code-server、earlyoom、
snapserver 在 Windows 標裝不了（原因寫在選單上，`home/.chezmoidata/tool-table.yaml`），要用就到 WSL 裝：
工具本身沒有 Windows 版，或不適用 Windows（zsh：Windows 的 shell 是 PowerShell）。
勾了也不會中斷 apply，最後列出略過了哪些。

要加減工具打 `tools`（PowerShell 版，做的事跟 Linux 一樣：重問用途、重出選單、勾完直接 apply）；取消勾選時 mise 裝的會移除，其他（winget、官方 installer）不解除安裝，
移除用 `mise uninstall <工具>` 或 `winget uninstall --id <id>`；官方 installer 裝的照它官方文件的 Uninstall 段
（claude 是[這裡](https://code.claude.com/docs/en/setup#uninstall-claude-code)）；codex 的官方文件沒寫 Windows 怎麼移除，
照 installer 放的位置刪 `%LOCALAPPDATA%\Programs\OpenAI\Codex`、`%USERPROFILE%\.codex\packages\standalone`，再從使用者 PATH 拿掉
`%LOCALAPPDATA%\Programs\OpenAI\Codex\bin`。
以前用 mise 或 winget 試裝過 claude 的，裝好官方那份後把舊的移掉（`mise uninstall claude` 並從 mise 設定拿掉、
`winget uninstall Anthropic.ClaudeCode`），一台只留一份。profile 把 mise 的 shims 排在 `.local\bin` 前面，mise 那份沒移掉的話，打 `claude` 會先找到它
（2026-11-20 henry-desktop 實測 PATH 順序）；winget 那份則看 PATH 排序，CMD 這類不讀 profile 的地方也可能找到舊的，而且舊的不會自己更新。

以前用 mise 試裝過 codex 的（例如 henry-laptop 的 0.170.0），一定要移掉：profile 把 mise 的 shims 排在 PATH 最前面，
官方那份在使用者 PATH，打 `codex` 會先找到 mise 那份，而它不會自己更新、`codex update` 也認不出安裝方式。
`mise ls` 找出那一項的名字（例如 `codex`、`npm:@openai/codex`），`mise unuse -g <那一項>` 從設定拿掉並移除，
再開新的 shell 確認 `(Get-Command codex).Source` 是 `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe`。

### windows-mcp

PyPI 上的 `windows-mcp` 由 mise 的 pipx backend 裝（#343）。mise 有 uv 就用 `uv tool install`，清單裡有 uv 時先裝 uv
（[mise 的 pypi backend 文件](https://mise.jdx.dev/dev-tools/backends/pypi.html)），所以勾它會一併列 uv；
套件要 Python 3.14 以上，uv 找不到就自己下載（[uv 的 Python 文件](https://docs.astral.sh/uv/concepts/python-versions/)）。
更新跑 `mise up`。怎麼開給別台的 agent 用（起 server、交 key、收掉）見 agent-config 的
[windows-mcp skill](https://github.com/henry5720/agent-config/blob/main/docs/skills/windows-mcp.md)。

mise 把它裝在自己的目錄，跟 `uv tool install` 的不是同一份。以前照 agent-config 的 windows-mcp skill 手動
`uv tool install windows-mcp` 過的機器，勾了之後會有兩份：

| | 手動 `uv tool install` | mise |
|---|---|---|
| 執行檔 | `%USERPROFILE%\.local\bin\windows-mcp.exe`（uv 的[執行檔目錄](https://docs.astral.sh/uv/reference/storage/#executable-directory)，複製過去的） | shim `%LOCALAPPDATA%\mise\shims\windows-mcp.exe` |
| 本體 | `%APPDATA%\uv\data\tools\windows-mcp` | `%LOCALAPPDATA%\mise\installs\pipx-windows-mcp\<版本>\bin\windows-mcp.exe`（2026-11-20 henry-desktop 實測，0.8.9） |

載入 profile 的 PowerShell 把 mise 的 shims 排在 `.local\bin` 前面，打 `windows-mcp` 拿到的是 mise 那份；
不載入 profile 的（`pwsh -NoProfile`、別的程式只帶系統與使用者 PATH 起的行程）沒有 shims，會先找到舊的那份，
而它不會跟著 `mise up` 更新（2026-11-20 henry-desktop 實測）。所以舊的要刪：

```powershell
uv tool uninstall windows-mcp
(Get-Command windows-mcp).Source   # 新開的 PowerShell 裡跑,要印出 mise 的 shims 那份
```

當初照 skill 用 winget 裝的 uv（`astral-sh.uv`）也還在，跟 mise 的 uv 兩份並存；只用 mise 那份就 `winget uninstall --id astral-sh.uv`。

### agent-config（skillshare）

做的事跟 Linux 一樣（[agent-config](https://github.com/henry5720/agent-config)、[ADR 0003](../adr/0003-agent-instructions-linked-by-skillshare-extras.md)）：skillshare 把 agent-config 的
skills 同步到勾了的 client、MCP 寫進各 client、指令檔（`CLAUDE.md`、`AGENTS.md`、commit 指引）放到各 client 讀的位置。
跟 Linux 不同的地方：

| | Linux | Windows |
|---|---|---|
| skillshare 本體 | `~/.local/bin/skillshare` | `%LOCALAPPDATA%\Programs\skillshare\skillshare.exe`（installer 加進使用者 PATH，新開的 shell 才找得到） |
| 設定與 agent-config 的 clone | `~/.config/skillshare` | `%AppData%\skillshare`（skillshare 在 Windows 的位置；Windows 上不要放 `~\.config\skillshare`，skillshare 會把它整個搬過去） |
| skills | 連結 | 目錄用 junction，不用 Developer Mode |
| 指令檔 | 連結 | 有開 Developer Mode 是連結；沒開時 skillshare 自動改成複製，`skillshare status` 顯示 `copy` |

指令檔是複製的時候，agent-config 的內容改了不會馬上到：`skillshare pull` 之後一定要 `skillshare sync --all`
（Linux 也是這兩步，只是連結看不出差別）。之後開了 Developer Mode，再 `sync --all` 一次就換成連結。

多勾一個 client 後 apply，`sync-skillshare.ps1` 會重新 sync，新的 client 拿到 skills 與指令檔。
`skillshare upgrade` 升級 skillshare 本身。哪些 skill 在 Windows 跑不了、卡在哪，見[Windows 上的 skill](windows-skills.md)。

### PowerShell

PowerShell 內建的 PSReadLine 給的，不用設：

| 功能 | 怎麼用 |
|---|---|
| 語法高亮 | 打字時指令、參數、字串各有顏色 |
| 補全 | `Tab` 出選單、方向鍵選（這項是 profile 改的，預設是一個一個換） |
| 灰字建議（只有 pwsh 7） | 打字時從歷史紀錄冒出灰字，`→` 接受 |
| 歷史紀錄 | 跨視窗保存；`↑` 翻、`Ctrl+R` 搜尋 |

profile 把 mise 的 shims（`%LOCALAPPDATA%\mise\shims`）和 `$HOME\.local\bin` 加進 PATH 最前面：mise 裝的工具和 `tools`
直接打名字就能跑，以前 winget 裝的同名舊版不會先被找到（不再需要就 `winget uninstall` 掉）。

## Documents 移出 OneDrive

PowerShell 從 `[Environment]::GetFolderPath('MyDocuments')` 讀 profile，chezmoi 卻固定部署到 `$HOME\Documents`。
Documents 被 OneDrive 備份時這兩個路徑不同：apply 照樣成功、也不報錯，但 PowerShell 根本不讀 chezmoi 部署的 profile。

照 Microsoft [about_Profiles](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles)
的建議，在 OneDrive 設定 →「同步與備份」→「管理備份」→ 關掉「文件」。關掉後原本的檔案留在 OneDrive，
要的自己搬回 `$HOME\Documents`。確認：

```powershell
[Environment]::GetFolderPath('MyDocuments')   # 要是 C:\Users\<你>\Documents，不是 ...\OneDrive\...
```

只刪掉 OneDrive 裡的檔案、或解除安裝 OneDrive，Documents 的位置都不會變（henry-desktop 實測），一定要在「管理備份」關掉。
OneDrive 也沒辦法只排除 `PowerShell` 一個資料夾：「選擇資料夾」是決定雲端哪些資料夾下載到這台，取消勾選等於刪掉本機那份。

## 從舊的手寫 profile 遷移

chezmoi 只部署 all-hosts 的 `Profile.ps1`；`$PROFILE` 比它晚載入，裡面若有 oh-my-posh（例如 henry-desktop 那份）
會蓋掉 starship。先看內容，機器專屬的設定（例如 API key）留下，其他刪掉；整份都不要就刪檔：

```powershell
notepad $PROFILE            # 看內容、只留機器專屬的設定
Remove-Item $PROFILE        # 整份都不要時
```

pwsh 和 `powershell`（5.1）的 `$PROFILE` 是不同檔案，兩邊都要看。

## WSL 網路：mirrored 與 NAT portproxy

### mirrored 模式（目前預設）

優先使用 `networkingMode=mirrored`；Windows 與 WSL 共用 localhost，不要同時套用下方 NAT
portproxy。設定來源：[`home/dot_wslconfig`](../../home/dot_wslconfig)。

### NAT fallback：查詢實際 WSL IPv4 後再轉發

只有把 `.wslconfig` 改回 NAT 時才用。不要直接取 `hostname -I` 第一個值；多介面時請看
`ip -4 addr`，確認可達的 WSL IPv4 後人工填入 `<WSL_NAT_IP>`。
NAT 下 WSL 服務也必須監聽可達的 NAT 介面地址，不能只綁 `127.0.0.1`；改成對外監聽時注意暴露風險。

```bash
ip -4 addr
```

在**系統管理員 PowerShell** 執行；`127.0.0.1` 只讓 Windows 本機聽，若要讓 LAN 存取才
明確改成指定的 Windows listen address，並另行確認防火牆：

```powershell
netsh interface portproxy show all
$wslIp = "<WSL_NAT_IP>"
netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=3000 connectaddress=$wslIp connectport=3000
```

先確認同一 listen address/port 沒有既有規則；要更換時先依下方指令刪除舊規則，再新增。

#### 先檢查既有 rule

```powershell
netsh interface portproxy show all
```

#### 刪除單條（listenaddress/port 要和既有 rule 完全一致）

```powershell
netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=3000
```

#### 清空全部（確認 show all 後才做）

```powershell
netsh interface portproxy reset
```
