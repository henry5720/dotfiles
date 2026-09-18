# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

個人 dotfiles,目標平台是 WSL2 上的 Ubuntu 24.04(純 zsh,無 Oh My Zsh)。家目錄設定檔由
[chezmoi](https://www.chezmoi.io) 部署,另含 Termux(Android)桌面腳本與 Windows 側的 WSL 設定。

文件、註解、commit message 一律用**繁體中文**。

## 這個 repo 被切成兩半

`.chezmoiroot` 的內容是 `home`,所以:

- **`home/` 是 chezmoi 的地盤** —— 檔名前綴有語意(見下),會部署到家目錄
- **其餘 chezmoi 完全看不到** —— `script/`(安裝腳本)、`docs/`、`wsl/`(Windows 主機側)、
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
`home/dot_config/tmux/` 底下已經有兩支漏加的,見 `docs/tmux-workflow.md` 的「已知的孤兒」。

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

## 怎麼驗證(沒有測試框架,這些就是)

```bash
chezmoi diff                                    # 輸出空的 = 家目錄與 repo 一致
chezmoi verify                                  # 同上,只看 exit code
chezmoi --no-tty execute-template --init \
  < home/.chezmoi.toml.tmpl                     # config 樣板能不能渲染
bash -n script/ubuntu/*.sh script/termux/*.sh   # 腳本語法(shellcheck 未安裝)
```

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
- **流程腳本**(`script/ubuntu/*.sh`)—— 從上到下跑一次、步驟有先後,用純 `# 1.` `# 2.` 編號。
  橫幅會讓步驟看起來像可以各自獨立看的模組,但這裡順序就是全部

判準不是長度,是「跳著讀」還是「一路讀到底」。

## 安裝腳本(chezmoi 不管套件安裝,兩條線獨立)

```bash
bash script/ubuntu/setup.sh           # 選擇基底／一般工具／AI，或高風險 Docker／主機資源 swap
bash script/ubuntu/install-base.sh    # 強制:zsh/git/curl/vim + zsh 插件 + chezmoi + 預設 shell
bash script/ubuntu/install-tools.sh   # 可選:fastfetch / btop / nvm / code-server / tailscale / wakatime / herdr
bash script/ubuntu/install-tools-ai.sh # Claude Code / Codex / OpenCode / 文件影音 / AI 解析
bash script/ubuntu/install-docker.sh  # Docker Engine；高風險，會移除衝突套件並修改系統
bash script/ubuntu/setup-swap.sh      # swapfile；預設 2G，會使用主機磁碟與記憶體資源
```

`setup.sh` 的 Docker 與 swap 選項預設不執行，直接 Enter 仍會結束；Docker 在 WSL 會保留
腳本的人工確認。`install-tools.sh` 的 Herdr 是一般工具選項；WakaTime 缺少 `unzip` 時會先
用 apt 安裝。

## Agent skills

### Issue tracker

Issues and specs live in this repository's GitHub Issues; use the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default labels: `needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, and `wontfix`.
See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. Read root `CONTEXT.md` and relevant
`docs/adr/` files when they exist.
See `docs/agents/domain.md`.
