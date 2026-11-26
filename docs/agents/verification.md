# 驗證:Windows 實機清單與照 spec 做

從 [`AGENTS.md`](../../AGENTS.md)〈怎麼驗證〉連過來,只在改到 Windows 會部署的檔案、或照 spec 做事時讀。

## Windows 實機清單

Windows 沒有容器可以跑 e2e。改到 Windows 會部署的檔案(白名單上的 target、`.chezmoiignore` 的 Windows 段、
config 樣板的 windows 分支)時:

1. 跑 `python3 -m unittest script/tests/test_windows.py`(`AGENTS.md`〈怎麼驗證〉的 discover 也會跑到),它在 Linux 上驗
   Windows 的選單、預設組合、部署哪些檔與腳本、渲染出什麼(腳本只渲染、不執行)
2. 改到 `home/` 的 PR 會自動跑 `.github/workflows/windows.yml`:在 Windows runner 上照 Runbook 從零
   `init --apply`(精簡、完整各一次),再跑下表「CI」欄標 ✅ 的項目,用 `gh pr checks` 看結果。
   ◐ 是 CI 只驗了一部分,剩下的那半還要實機
3. PR 的 `## 驗證` 段逐項列出下表 CI 沒標 ✅ 的實機項目,全部勾完才 merge。能在 Windows 上下指令就自己跑

runner 測不到、一定要實機的情況(說明在 workflow 開頭):runner 的家目錄是全新的(沒有使用者自己的設定檔、
手寫的 `$PROFILE`、「文件」沒被 OneDrive 接管)、UAC 關著、Developer Mode 開著、pwsh 7、Git 與企業版 MSI 的 Chrome 預裝、
是 Windows Server 不是 Windows 11、沒有 WSL2 的 VM、沒有桌面可以看。

| # | 時機 | 在 Windows 上做 | 預期 | CI |
|---|---|---|---|---|
| 1 | 每次 | `chezmoi apply` 後 `chezmoi diff` | 沒有輸出 | ✅ |
| 2 | 每次 | `[Environment]::GetFolderPath('MyDocuments') -eq "$HOME\Documents"` | `True` | ✅ |
| 3 | 每次 | 開 `pwsh`、`powershell`;再跑 `pwsh -c 'echo hi'` | 開 shell 印 fastfetch、提示列是 starship、沒有紅字、有 `z`;`pwsh -c` 只印 `hi` | ◐ 只驗 `-c` 只印 `hi`、找得到 starship |
| 4 | 每次 | `Get-ExecutionPolicy -List` | 第一個不是 `Undefined` 的是 `RemoteSigned`、`Unrestricted` 或 `Bypass` | |
| 5 | 每次 | 開 Windows Terminal;設定 UI 存一次後 `chezmoi diff` | 新分頁是 pwsh 7、starship 圖示不是方框;diff 沒有輸出 | |
| 6 | 改到 `.wslconfig` | `wsl --shutdown` 後在 WSL 跑 `nproc`、`free -g`、`wslinfo --networking-mode` | 跟 `.wslconfig` 一致 | |
| 7 | 改到 config 樣板、選裝工具表的 `rules`、選單 | `chezmoi init --prompt`(或 `tools`) | 出用途與選單,Windows 裝不了的標原因;git 身分不問;結束後 `chezmoi diff` 沒有輸出 | ◐ 只驗不互動的 init |
| 8 | 改到 `.ps1` 腳本、`packages.yaml`、選裝工具表的 Windows 裝法、`mise-tools` | `chezmoi apply` 後 `mise ls`、`winget list --id <id> --exact` | 腳本沒有紅字、不會停在一半;勾的 CLI 在 `mise ls`、勾的 app 在 `winget list`;勾了裝不了的工具時最後列出略過與原因 | ✅ |
| 9 | 改到 headless-chrome、playwright-cli 的 Windows 裝法 | 勾兩項後 apply;新開 `pwsh` 跑 `playwright-cli -s=t open https://example.com`、`playwright-cli -s=t snapshot`、`playwright-cli -s=t close` | 已經有 Chrome 的機器 winget 跳過;snapshot 讀得到 `Example Domain` | ◐ 只驗已經有企業版 MSI 的 Chrome 時 winget 跳過、`playwright-cli --version` 跑得起來 |
| 10 | 改到 coding agent 的安裝腳本 | 勾了那個 agent `chezmoi apply`,開新的 `pwsh` 與 `powershell` 跑 `claude --version`(以及那張新增的指令,例如 `codex --version`) | 兩個 shell 都印出版本 | ✅ |
| 11 | 改到 coding agent 的安裝腳本 | 再 `chezmoi apply` 一次,然後 `chezmoi diff` | 第二次沒有重新下載(腳本沒跑,或印「已安裝,跳過」);diff 沒有輸出 | ✅ |
| 12 | 改到 agent 的設定檔 | 啟動 agent 一次、讓它寫過自己的設定檔,再 `chezmoi diff` | 沒有輸出 | |
| 13 | 改到 agent-config | `skillshare status`;在 agent 裡打 `/` 與看 MCP 清單 | targets 已同步、指令檔到位;看得到 skill 與 MCP | ◐ 只驗 `skillshare status` |
| 14 | 改到 `register-herdr-server.ps1` | 勾 herdr 後 apply,登出再登入;`Get-CimInstance Win32_Process \| ? Name -like herdr*` 看 `server` 那行的 `SessionId`;桌面 terminal 跑 `herdr status`;別台 `herdr --machine <這台> workspace list` | 工作排程有 `herdr-server`;server 只有一個、`SessionId` ≥ 1;沒有多出視窗;`herdr status` 與 `--machine` 都連得上 | |

互動登入、實際開一個 agent session 要人做,agent 不代做。

`.gitattributes`(#204)加進來之前就 clone 的 Windows 機器,source 還是 CRLF。**這一次不要直接 `chezmoi update`**:
它是 pull 加 apply,pull 只重寫有變的檔,沒變的那些(`skillshare-pinned`、`codex-commit-attribution.md`…)還帶 `\r`,
apply 就會把 `\r` 寫進 skillshare 的 `config.yaml`、Codex 的 `developer_instructions`。先確認 `chezmoi git -- status` 是乾淨的,再:

```powershell
chezmoi git -- pull
chezmoi git -- rm --cached -r -q .
chezmoi git -- reset --hard
chezmoi apply
```

source 從 CRLF 變 LF,所有 `run_onchange_*.ps1` 的內容雜湊都會變,這次 apply 會各重跑一次(都是「已安裝就跳過」);
部署出去的一般檔(mise 設定、starship、PowerShell profile…)也改寫成 LF 一次。已經照順序做錯、`\r` 寫進去了的話,
補做重新 checkout 再 `chezmoi apply` 一次就恢復。

在 Windows 上測還沒 merge 的分支:`chezmoi init --branch <分支> henry5720`(已經裝過就
`chezmoi git -- checkout <分支>` 再 `chezmoi update`)。merge 後 `chezmoi git -- checkout main` 再
`chezmoi update` 換回來,不然那台會一直拉舊分支。

## 照 spec 做(`/implement-spec`)

照 spec 做(`/implement-spec`)時,每張 ticket 只跑單元測試(含 `test_render_snapshot.py` 的渲染快照,快照有變的格子逐格說明原因);
容器 e2e 三個目標、macOS workflow、Windows 實機清單,以及在這台跑 `chezmoi --source <integration worktree>/home diff`
(只看、不 apply:已經裝好的機器換到這個分支會被改到什麼),在 integration 分支所有 ticket 併完後各跑一次,全過才把 PR 標成 ready。
