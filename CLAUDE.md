# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

個人 dotfiles,以 Ubuntu + 純 zsh(無 Oh My Zsh)為主,日常用在 WSL2,也用在雲端主機與平板
(原生 Termux、Termux 裡的 proot Ubuntu)。家目錄設定檔、套件、選裝工具都由
[chezmoi](https://www.chezmoi.io) 部署,另含新機器的 bootstrap、手動腳本與 Windows 側的 WSL 設定。

`home/` 要在一般 Linux 和原生 Termux 都能用 —— WSL 專屬的東西(`/mnt/c`、Windows 程式)不在
WSL 時必須安靜略過,不能報錯;要 apt 的東西(套件腳本、選裝工具選單)在非 Debian 系 Linux 也一樣。
樣板裡判斷 WSL、Debian 系用 `home/.chezmoitemplates/` 的 `is-wsl`、`is-debian`,不要各寫一份。chezmoi 自己執行的 sh 腳本(`run_`、`modify_`)一律是 `.tmpl`,
shebang 寫 `#!{{ lookPath "sh" }}`,否則 Termux 上找不到 `/bin/sh`。`script/ubuntu/` 只保證 Ubuntu,需要分 WSL／非 WSL 時用
`grep -qi microsoft /proc/version` 判斷。

文件、註解、commit message 一律用**繁體中文**。

## 這個 repo 被切成兩半

`.chezmoiroot` 的內容是 `home`,所以:

- **`home/` 是 chezmoi 的地盤** —— 檔名前綴有語意(見下),會部署到家目錄
- **其餘 chezmoi 完全看不到** —— `script/`(bootstrap、手動腳本、測試)、`docs/`、`wsl/`(Windows 主機側)、
  `ai-agent/`(手動貼用的 persona),以及這個 CLAUDE.md

改 `home/` 底下 = 改會部署到家目錄的設定;改其他地方 = 只是 repo 內容,不影響任何機器。

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
手邊的例外(下面「文件放哪」說不要抄 chezmoi 的通用知識)—— 前綴弄錯是靜默改掉權限,
成本太高,不值得為了原則去翻文件。

## 秘密

**這個 repo 是公開的。** 秘密不進 git,一律走 chezmoi 的 `promptStringOnce`,值存在
`~/.config/chezmoi/chezmoi.toml`(repo 外),在 `.tmpl` 裡以 `{{ .someKey }}` 帶入。

新增一個秘密 = 在 `home/.chezmoi.toml.tmpl` 加一行,再從用到它的 `.tmpl` 引用。簽名是:

```
promptStringOnce map path prompt [default]
```

第三個參數是**提示文字**,第四個才是選用的預設值。少給提示文字會直接錯
(`wrong number of args ... want at least 3`),而且是在 `chezmoi init` 時才炸 —— 平常
`chezmoi apply` 不會重新渲染 config 樣板,所以這種錯很容易漏到新機器上才發現。

## 怎麼驗證

```bash
chezmoi diff                                    # 輸出空的 = 家目錄與 repo 一致
chezmoi verify                                  # 同上,只看 exit code
chezmoi --no-tty execute-template --init \
  < home/.chezmoi.toml.tmpl                     # config 樣板能不能渲染
bash -n script/*.sh script/ubuntu/*.sh script/termux/*.sh  # 腳本語法(shellcheck 未安裝)
python3 -m unittest discover -s script/tests   # modify_ 與 ai-profile 的單元測試
bash script/tests/e2e.sh ubuntu                # 容器 e2e:全新 ubuntu:24.04 跑 bootstrap 到 init --apply
bash script/tests/e2e.sh termux                # 同上,termux/termux-docker:x86_64
```

容器 e2e 是改 `home/` 的 `run_` 腳本、套件清單、選單、externals、bootstrap 時唯一能從零驗證的
方法,兩種容器都要過。需要 docker、能連外(含 22 port,bootstrap 那關真的連 GitHub);
測的是工作目錄(含未 commit 的修改),不碰本機家目錄。檢查清單與環境變數(`E2E_TAG`、
`E2E_KEEP`)寫在腳本開頭。要驗證從零安裝就跑 e2e,**不要拿自己的家目錄 `chezmoi init` 來試**。

改完 `home/` 底下的檔案要 `chezmoi apply` 才生效。**不要直接改家目錄那份**:不會回到 repo,
下次 apply 還會被蓋掉。真的動了家目錄那份就 `chezmoi re-add` 收回來。

## 文件放哪

- **README.md** 只放專案層:這是什麼、怎麼裝、哪個檔部署到哪、依賴、fork 前要改什麼
- **`docs/<主題>.md`** 放細節,README 用連結指過去,不要在 README 展開
- chezmoi 本身的通用用法**不要抄進 repo**,連官方文件
- **設定檔自己的註解就是它的文件**。例如 `home/private_dot_ssh/private_config` 已經逐段解釋了
  每個 Host,不要再開一份 docs 複製一遍 —— 兩份一定會漂移
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

## 安裝分工

chezmoi 管家目錄**和套件**:

- 要 apply 時執行的 `run_` 腳本一律放 `home/.chezmoiscripts/` 第一層,**不要再分子資料夾**:
  chezmoi 照完整路徑的字母序跑腳本,分了資料夾,下面靠檔名排的順序就亂掉。
  `.chezmoiignore` 排除腳本時要寫 `.chezmoiscripts/<檔名>`。
- 基底套件:`home/.chezmoidata/packages.yaml` 依平台列,`run_onchange_before_install-packages`
  只裝缺的。名字一定要帶 `before_`,才會在 externals(要外部 git)與 `modify_`(要 jq、python3)之前跑。
- 選裝工具(只有 Debian 系 Linux):`home/.chezmoi.toml.tmpl` 的 `promptMultichoiceOnce` 選單,存成
  `.tools`。走 apt 的放 `packages.yaml` 的 `toolPackages`;其他每個工具一支
  `run_onchange_after_install-<工具>.sh.tmpl`,整段包在 `{{ if has "<工具>" .tools }}`,已經裝了就跳過。
  例外是 codegraph:叫 `run_onchange_after_npm-install-codegraph`。chezmoi 依檔名字母順序跑腳本,
  它要 npm,檔名要排在 `install-nvm` 之後,第一次 apply 同時勾兩個才裝得起來。
  加新工具 = 選單加一項 + 對應的腳本或 `toolPackages`;舊機器要 `chezmoi edit-config` 把它加進 `tools` 才會裝。
- p10k、zsh 插件、Termux 字型:`home/.chezmoiexternal.toml.tmpl`。預設 shell:`run_once_after_set-default-shell`。

`script/` 只放 chezmoi 之前或之外的事:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/henry5720/dotfiles/main/script/bootstrap.sh)
                                        # 新機器:系統更新 → git/ssh/curl → SSH key → 裝 chezmoi → init --apply
bash script/ubuntu/install-docker.sh    # Docker Engine;高風險,會移除衝突套件並修改系統
bash script/ubuntu/setup-swap.sh        # swapfile;預設 2G,會寫 /etc/fstab
bash script/termux/install-desktop.sh   # 平板 xfce 桌面套件(原生 Termux)
bash script/termux/setup-proot-ubuntu.sh # 在 proot Ubuntu 建一般使用者(原生 Termux)
```

Docker、swap、平板桌面刻意不交給 chezmoi:它們會改系統設定或移除套件,不該在 `chezmoi apply`
時默默發生。Docker 在 WSL 會保留腳本的人工確認。

## Agent skills

### Issue tracker

Issues and specs live in this repository's GitHub Issues; use the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default labels: `needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, and `wontfix`.
See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. Read root `GLOSSARY.md` and relevant
`docs/adr/` files when they exist.
See `docs/agents/domain.md`.
