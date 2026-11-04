# 看 agent 的瀏覽器、借你的網路或瀏覽器

agent 跑在已配置主機（例如 company-ec2，沒有螢幕）上，要用瀏覽器時預設自己開 headless 瀏覽器，**你什麼都不用做**。
只有下面三種情況它會請你在個人電腦開一條 ssh 轉發。這份講每種情況你要打什麼指令、那些指令在做什麼、連不上時怎麼查。

agent 那邊怎麼做寫在 agent-config 的 skill（`verify-in-browser`、`personal-pc-tunnel`），這份只寫你這邊的事。
為什麼這樣分見 [ADR 0001](adr/0001-browser-tools-drive-vs-debug.md)。

## 什麼時候要你出手

```
情況                                瀏覽器在哪          你在個人電腦開
─────────────────────────────────────────────────────────────────────────────────
操作、驗收、查原因                  已配置主機          不用
你要看畫面、接手、替它登入          已配置主機          ssh -N -L <port>（agent 給 port）
網站擋機房 IP                        已配置主機          ssh -N company-ec2-socks
一定要你本人的瀏覽器                個人電腦的 Chrome   ssh -N company-ec2-attach
（passkey、硬體金鑰、裝置 SSO）
```

前兩種瀏覽器都在已配置主機上；擋 IP 時瀏覽器也不搬，只是網路流量改從你那台出去。只有最後一種才用你自己的 Chrome。

## ssh 轉發怎麼讀

三個旗標就夠用：

| 旗標 | 意思 |
|---|---|
| `-N` | 只開通道、不開 shell。視窗會停住不動是正常的，**開著別關**；用完按 Ctrl-C。 |
| `-L` | 本地轉發：**你這台**的 port 接到已配置主機上的 port。用來在你的瀏覽器看已配置主機上的東西。 |
| `-R` | 遠端轉發：**已配置主機**的 port 接回你這台。用來讓已配置主機借你這台的網路。 |

```
-L 127.0.0.1:9377:127.0.0.1:9377
   └─ 你這台聽哪裡 ─┘└─ 到了已配置主機後連哪裡 ─┘

   個人電腦                               已配置主機
   瀏覽器 → 127.0.0.1:9377 ══ssh══▶ 127.0.0.1:9377（agent 的畫面）

-R 127.0.0.1:1080        （只寫一個 port、不寫目的地 = 反向 SOCKS proxy）

   個人電腦                               已配置主機
   你的網路 → 網站 ◀══ssh══ 127.0.0.1:1080 ← headless 瀏覽器帶 proxy
```

- **一定寫 `127.0.0.1`**：只讓同一台的程式連得到。這些服務都沒有驗證，聽 `0.0.0.0` 等於開給整個網路。
- **一個 port 同時只能一條**：同一個 port 在兩個視窗（或兩台電腦）各開一條，第二條會失敗。
  `company-ec2-attach`、`company-ec2-socks` 設了 `ExitOnForwardFailure`，搶不到就直接結束、印出錯誤，不會默默連上卻沒有轉發。
- **為什麼一般的 `ssh company-ec2` 不帶任何轉發**：每條連線都帶的話，你開第二個視窗就搶不到 port。
  所以要轉發時另開一個別名，用完就關。

`company-ec2-attach`、`company-ec2-socks` 是 dotfiles 部署的 `~/.ssh/config` 裡的別名。沒有這份設定的機器（例如 Windows 的 PowerShell）就打完整指令，下面每節都有寫。
Windows 內建的 OpenSSH 用法一樣。

## 看畫面、接手、替 agent 登入

1. agent 會說它開了 `show`，並給你一個 port（預設 9377）。
2. 個人電腦開：

   ```bash
   ssh -N -L 127.0.0.1:9377:127.0.0.1:9377 company-ec2
   ```

3. 瀏覽器開 `http://127.0.0.1:9377`，點 session 放大。點進畫面就能用滑鼠、鍵盤操作，按 Escape 交還給 agent。
4. 要替它登入：在這個畫面上登入就好，agent 接著用同一個 session，就會帶著登入狀態。
5. agent 說好了就按 Ctrl-C 關掉 ssh。

## 網站擋機房 IP

agent 說某個網站擋了機房 IP（驗證碼一直跳、影片不能播）時：

1. 個人電腦開：

   ```bash
   ssh -N company-ec2-socks
   # 沒有別名時：ssh -N -o ExitOnForwardFailure=yes -R 127.0.0.1:1080 company-ec2
   ```

2. agent 會給你看它那邊的對外 IP，確認是你這台的。你的網路有 IPv6 時常會是 IPv6 位址，這是正常的。
3. agent 說用完了就按 Ctrl-C。開著的時候，agent 帶 proxy 的流量都走你的網路，所以只在被擋時開。

## 一定要你本人的瀏覽器

1. **第一次**：日常 Chrome 裝 [Playwright Extension](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm)。
2. 個人電腦開：

   ```bash
   ssh -N company-ec2-attach
   # 沒有別名時：ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:9555:127.0.0.1:9555 company-ec2
   ```

3. 在 agent 說的時間內（預設 5 分鐘）開一個**新分頁**（agent 會直接改這個分頁），網址列開 `http://127.0.0.1:9555/connect`，
   按「複製」，再把網址貼進同一個分頁的網址列、按 Enter。`/connect` 這個網址每次都一樣，可以加書籤。
   - 有設 token：貼完就接上了。
   - 沒設 token：貼完還要在 extension 畫面選這個分頁、按允許。這時 agent 也會直接給你網址，貼它給的也可以。
4. agent 說 detach 了就按 Ctrl-C。Chrome 和分頁都會留著。

agent 只看得到你貼網址的那個分頁，其他分頁讀不到。token 怎麼設見 agent-config 的
[personal-pc-tunnel](https://github.com/henry5720/agent-config/blob/main/docs/skills/personal-pc-tunnel.md)。

## 連不上時

| 現象 | 原因 | 怎麼查、怎麼處理 |
|---|---|---|
| ssh 一開就結束，訊息有 `Address already in use` | 你這台的這個 port 被別的程式或另一個 ssh 視窗佔著 | Linux：`ss -ltnp \| grep 9555`；Windows：`netstat -ano \| findstr 9555`。把舊的 ssh 視窗關掉 |
| ssh 一開就結束，訊息有 `remote port forwarding failed` | 已配置主機上的 1080 被佔著，通常是你另一台電腦還開著 | 關掉另一台的 ssh；或請 agent 在它那邊用 `ss -ltnp \| grep 1080` 查 |
| 瀏覽器開 `127.0.0.1:<port>` 連不上 | ssh 沒開或已經斷線 | 確認 ssh 視窗還停著；斷了就重開 |
| 開得到但是空白、一直轉圈 | 已配置主機那邊的 `show` 或 `personal-chrome-attach` 還沒起來，或已經結束 | ssh 視窗會印 `channel … open failed`。請 agent 重新開，它會再給你 port 或網址 |
| agent 說逾時、要重來 | `personal-chrome-attach` 預設等 5 分鐘，沒人連進來就自己收掉 | 請 agent 重跑，重新開 `/connect` 複製（網址每次不同，舊的不能用） |
