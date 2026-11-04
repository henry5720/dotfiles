# 操作已配置主機

**已配置主機**是裝好 herdr、coding agent 這些工具、你要用它的那台；**自己電腦**是你坐在前面的那台。
兩台可以是同一台。工具都是 terminal 指令，坐在前面或從別台連過去，用法一樣。

```
自己電腦 ──入口──> 已配置主機
                   └── herdr（關掉視窗、斷線都還在跑）
                       └── pane 裡跑 claude／codex／opencode、btop…
```

已配置主機就是你面前這台的話，跳過〈入口〉和〈傳檔案〉，直接開 terminal 從〈herdr〉開始。
各工具的常用指令與官網見[工具一覽](tools.md)。

## 入口

| 入口 | 自己電腦要有什麼 | 誰開 | 適合 |
|---|---|---|---|
| terminal `ssh` | ssh key、在 tailnet 裡 | 自己 | **預設**：跑 herdr、agent |
| VS Code Remote-SSH | VS Code、同上 | 自己 | **預設**：看檔、改檔、拖拉傳檔 |
| 瀏覽器開 code-server | 瀏覽器、ssh tunnel | 自己先在已配置主機開 | 沒裝 VS Code 的裝置（平板）；見 [code-server 遠端存取](code-server-remote.md) |
| 瀏覽器開 share-shell | 只要瀏覽器 | 已配置主機上的人開給你，關掉就失效 | 沒有 key、不在 tailnet 的臨時訪客；見[開給訪客看](share-with-guest.md) |

### 第一次連：找管理員要兩樣

1. **加進 tailnet**：已配置主機只開在 tailscale 私人網路裡。加入後在自己電腦跑 `tailscale status`，
   找到那台的名稱或 `100.` 開頭的 IP，下面寫成 `<已配置主機>`。
2. **把你的 ssh 公鑰加到那台**：已配置主機不收密碼登入。

```bash
ssh-keygen -t ed25519           # 自己電腦產一把 key（已經有就跳過），一路 Enter
cat ~/.ssh/id_ed25519.pub       # 這一行給管理員；沒有 .pub 的那個是私鑰，不要給任何人
```

Windows 在 PowerShell 照打。

### terminal

```bash
ssh <帳號>@<已配置主機>
```

### VS Code Remote-SSH

```
VS Code 裝擴充套件「Remote - SSH」
  → F1 → Remote-SSH: Connect to Host... → 輸入 <帳號>@<已配置主機>
  → 左下角出現 SSH: <已配置主機> 就是連上了
  → Open Folder 開要用的資料夾；Terminal → New Terminal 開的就是已配置主機的 terminal
```

細節見 [VS Code 官方文件](https://code.visualstudio.com/docs/remote/ssh)。

## herdr

在已配置主機開 herdr，之後所有東西都在裡面跑。斷線了重新連進來、打同一行就接回原本的畫面。

```bash
herdr --session <你的名字>     # 開自己那一套；已經開過就接回去
herdr session list            # 這台有哪些 session（別人的也看得到）
```

```
session          一整套畫面，每個人用自己的名字開一套
└── workspace    一個工作區，通常一個專案一個
    └── tab      分頁
        └── pane     分頁裡切出來的一格 terminal（可以左右、上下切）
            └── agent    在 pane 裡跑的 coding agent，herdr 認得它在忙還是在等你
```

快捷鍵與其他操作見 [herdr 官方](https://github.com/herdrdev/herdr)。

## coding agent

已配置主機裝了哪個就用哪個：`claude`、`codex`、`opencode`。以下用 Claude Code 舉例。

| | 一般模式 | 背景模式 |
|---|---|---|
| 怎麼開 | pane 裡打 `claude` | `claude --bg "<任務>"`，之後 `claude agents` 看、`claude attach <id>` 接上 |
| 跑在哪 | 那一格 pane 裡，關掉 pane 就停 | 背景，關掉畫面照樣做 |
| 適合 | 邊看邊對話 | 丟一件事給它，晚點回來看 |

### 同一個對話在兩個地方打開

已配置主機常常有好幾個人、好幾個入口在用，同一個對話很容易被兩邊同時打開。2026-11-04 實測：

```
背景模式：兩邊 claude attach 同一個對話
  A 的 pane ─┐
             ├─> 同一個 Claude ─> 同一個畫面
  B 的 pane ─┘   最後接上的那邊決定畫面大小，另一邊跟著變；捲動也一起動

一般模式：兩邊 claude --resume 同一個對話 ID
  A 的 pane ─> Claude 1 ─┐  畫面各自獨立，一邊問的另一邊看不到
  B 的 pane ─> Claude 2 ─┘  但兩邊寫進同一份對話紀錄，之後再打開會混在一起
```

- **同一個對話，同一時間只開在一個地方。** 要換地方看，先把另一邊退出。
- **兩個人要同時做事，各開一個新對話。**
- **只想看別人的 agent 做到哪**，讀它的輸出就好，不會動到對方畫面：

```bash
herdr agent list                                                   # 找到對方的 pane_id
herdr agent read <pane_id> --source recent-unwrapped --lines 80    # 讀最近 80 行
```

## 傳檔案

```
              VS Code：檔案從桌面拖進左邊檔案總管 ──>
自己電腦                                              已配置主機
              <── VS Code：檔案總管右鍵 → Download...
              <──> terminal：scp（在自己電腦跑）
```

```bash
scp ./報表.xlsx <帳號>@<已配置主機>:~/          # 自己電腦 → 已配置主機的家目錄
scp <帳號>@<已配置主機>:~/結果.csv ./           # 已配置主機 → 自己電腦目前資料夾
scp -r ./資料夾 <帳號>@<已配置主機>:~/          # 整個資料夾加 -r
```

Windows 的 PowerShell 內建 `scp`。

## 看已配置主機忙不忙

```bash
btop      # 工作管理員：CPU、記憶體、哪個程式最吃資源；按 q 離開
```

變慢時先開 `btop`，看是不是有東西吃滿 CPU 或記憶體，截圖給管理員。
