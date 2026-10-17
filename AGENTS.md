# AGENTS.md

`home/` 要在一般 Linux 和原生 Termux 都能用 —— WSL 專屬的東西(`/mnt/c`、Windows 程式)不在
WSL 時必須安靜略過,不能報錯;要 apt 的東西(套件腳本、選裝工具選單)在非 Debian 系 Linux 也一樣。
樣板裡判斷 WSL、Debian 系用 `home/.chezmoitemplates/` 的 `is-wsl`、`is-debian`,不要各寫一份。chezmoi 自己執行的 sh 腳本(`run_`、`modify_`)一律是 `.tmpl`,
shebang 寫 `#!{{ lookPath "sh" }}`,否則 Termux 上找不到 `/bin/sh`。`script/ubuntu/` 只保證 Ubuntu,需要分 WSL／非 WSL 時用
`grep -qi microsoft /proc/version` 判斷。

文件、註解、commit message 一律用**繁體中文**。

## 這個 repo 被切成兩半

`.chezmoiroot` 的內容是 `home`,所以:

- **`home/` 是 chezmoi 的地盤** —— 檔名前綴有語意(見下),會部署到家目錄
- **其餘 chezmoi 完全看不到** —— `script/`(手動腳本、測試、錄影)、`docs/`、`wsl/`(Windows 主機側),
  以及這個 AGENTS.md

改 `home/` 底下 = 改會部署到家目錄的設定;改其他地方 = 只是 repo 內容,不影響任何機器。

Docker、swap、平板桌面刻意放 `script/`、不交給 chezmoi:它們會改系統設定或移除套件,不該在
`chezmoi apply` 時默默發生。不要把它們搬進 `run_` 腳本。

要 apply 時執行的 `run_` 腳本一律放 `home/.chezmoiscripts/` 第一層,**不要再分子資料夾**:
chezmoi 照完整路徑的字母序跑腳本,分了資料夾,靠檔名排的順序就亂掉。

加選裝工具要動哪幾處,寫在 `home/.chezmoi.toml.tmpl` 選單上方的註解。

## 檔名前綴是語意,不是命名風格

`home/` 底下的檔名決定部署結果,**改名等於改行為**:

| 前綴 / 後綴 | 效果 |
|---|---|
| `dot_` | 部署成 `.` 開頭 |
| `private_` | 權限收成 600(目錄 700) |
| `executable_` | 部署後帶 +x |
| `symlink_` | 部署成 symlink,檔案內容就是連結目標 |
| `.tmpl` | 先跑 Go template 再部署 |
| `modify_` | 部署成腳本的 stdout,現有檔案從 stdin 進來(用於 app 自己會寫的檔) |

⚠️ **新增要執行的腳本一定要加 `executable_`**,否則部署成 644 不可執行,而且不會報錯。

完整規則見 [Target types](https://www.chezmoi.io/reference/target-types/)。這張表是刻意留在
手邊的例外(全域規則說工具的通用用法不抄、連官方)—— 前綴弄錯是靜默改掉權限,
成本太高,不值得為了原則去翻文件。

## 秘密

**這個 repo 是公開的。** 秘密不進 git,一律在 `chezmoi init` 時問,值存在
`~/.config/chezmoi/chezmoi.toml`(repo 外),在 `.tmpl` 裡以 `{{ .someKey }}` 帶入。

新增一個秘密 = 在 `home/.chezmoi.toml.tmpl` 開頭的清單加一項 `(list "key" "提示文字" "預設值")`
(沒有預設值給 `""`),`[data]` 加一行,再從用到它的 `.tmpl` 引用。已經存過的值不會再問,
`chezmoi init --prompt` 也不會 —— `--prompt` 只重問選單,`tools` 指令靠這個。

樣板寫錯是在 `chezmoi init` 時才炸 —— 平常 `chezmoi apply` 不會重新渲染 config 樣板,
所以這種錯很容易漏到新機器上才發現。改完一定跑下面的 `execute-template --init`。

## 怎麼驗證

```bash
chezmoi diff                                    # 輸出空的 = 家目錄與 repo 一致
chezmoi verify                                  # 同上,只看 exit code
chezmoi --no-tty execute-template --init \
  < home/.chezmoi.toml.tmpl                     # config 樣板能不能渲染
bash -n script/*/*.sh                           # 腳本語法(shellcheck 未安裝)
python3 -m unittest discover -s script/tests   # modify_ 與 ai-profile 的單元測試
bash script/tests/e2e.sh ubuntu                # 容器 e2e:全新 ubuntu:24.04 照 README 官方指令 init --apply
bash script/tests/e2e.sh termux                # 同上,termux/termux-docker:x86_64
```

容器 e2e 是改 `home/` 的 `run_` 腳本、套件清單、選單、externals、README 的安裝指令時唯一能從零驗證的
方法,兩種容器都要過。需要 docker、能連外(會用 HTTPS 連 GitHub,不用 SSH key);
測的是工作目錄(含未 commit 的修改),不碰本機家目錄。檢查清單與環境變數(`E2E_TAG`、
`E2E_KEEP`)寫在腳本開頭。要驗證從零安裝就跑 e2e,**不要拿自己的家目錄 `chezmoi init` 來試**。

改完 `home/` 底下的檔案要 `chezmoi apply` 才生效。**不要直接改家目錄那份**:不會回到 repo,
下次 apply 還會被蓋掉。真的動了家目錄那份就 `chezmoi re-add` 收回來。

## 文件放哪

README、`docs/`、工具用法、設定檔註解的通則在全域規則開頭;這裡只補這個 repo 的。

新內容照「讀者什麼時候打開」放(用詞見 `GLOSSARY.md` 的「文件」),人和 agent 讀同一份:

| 類別 | 什麼時候打開 | 放在 |
|---|---|---|
| README | 第一次看到這個 repo | `README.md`:是什麼、哪種機器部署什麼、安裝一行、裝完最常用的指令、文件索引 |
| Runbook | 裝一台新機器,從頭走到尾一次 | `docs/new-machine-setup.md` |
| 日常操作 | 裝完之後想改點什麼 | `docs/after-install.md` |
| 主題文件 | 用某個工具、遇到某個情境 | `docs/<主題>.md`,README 索引連過去 |
| 背景與決策 | 想知道為什麼這樣做 | `docs/adr/`、選型比較、`docs/research/` |

- 能畫成圖的用文字圖(箭頭、縮排樹)和表格,不用 mermaid:終端機和 agent 讀的是原始文字
- 只有 agent 要遵守的限制寫在這份 AGENTS.md,或 Runbook「交給 coding agent」那段 prompt,不另寫一份給 agent 的文件
- Runbook 裡某一步太長(例如整張對照表),拆成主題文件,Runbook 只留一行連結
- 搬檔案、改名或改標題(錨點會跟著變)時,連 agent-config 一起查:它的文件用
  `https://github.com/henry5720/dotfiles/blob/main/...` 連進來,這邊一改就斷。
  `grep -rn "henry5720/dotfiles/blob" ~/.config/skillshare --include='*.md'`,斷的到 agent-config 開 PR 修

- README 的專案層包含:哪個檔部署到哪、依賴、fork 前要改什麼
- 改安裝流程、`run_` 腳本、template、externals 之前,先查 chezmoi 官方文件([chezmoi.io](https://www.chezmoi.io/)
  或 context7)有沒有現成做法,有就照官方做;偏離官方時,在那個檔案的註解或 issue 寫下理由。
  這個 repo 曾經自己寫一支安裝腳本重做官方一行指令就有的事(#168)
- `docs/superpowers/` 是歷史紀錄(當初的 spec / plan),**不是現況**,別當根據

## 註解樣式

看檔案是哪一種,兩種不要互相看齊:

- **設定檔**(`home/dot_zshrc`、`home/private_dot_ssh/private_config`、
  `private_config.yaml.tmpl`)—— 一堆彼此無關的設定並排、會跳著找,
  用 `# ===` 橫幅 + 編號當目錄
- **流程腳本**(`script/` 底下的 `.sh`、`home/.chezmoiscripts/run_*`)—— 從上到下跑一次、步驟有先後,用純 `# 1.` `# 2.` 編號。
  橫幅會讓步驟看起來像可以各自獨立看的模組,但這裡順序就是全部
- **例外:測試**(`script/tests/`)—— 雖然放在 `script/`,但是一堆檢查並排、要找某一項時是跳著讀,
  用 `# ===` 橫幅

判準不是長度,是「跳著讀」還是「一路讀到底」。

## Agent skills

### Issue tracker

issue 和 spec 放在這個 repo 的 GitHub Issues,用 `gh` CLI。
照 issue 做事(`/implement`、`/implement-spec`)時,認領、卡住、結案照 `docs/agents/issue-tracker.md` 的「照 ticket 做事」。

### Triage labels

用預設 label:`needs-triage`、`needs-info`、`ready-for-agent`、
`ready-for-human`、`wontfix`。
細節見 `docs/agents/triage-labels.md`。

### Domain docs

這是 single-context repository。有根目錄 `GLOSSARY.md` 和相關的 `docs/adr/` 就先讀。
細節見 `docs/agents/domain.md`。
