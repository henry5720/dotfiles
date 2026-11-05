# 看 agent 的瀏覽器、借你的網路或瀏覽器

agent 跑在已配置主機（例如 company-ec2，沒有螢幕）上，要用瀏覽器時預設自己開 headless 瀏覽器，**你什麼都不用做**。
只有下面三種情況它會請你在個人電腦開一條 ssh 轉發。這份講每種情況 app 起在哪個 port、要什麼驗證、你要做什麼、用完收掉什麼。
轉發指令怎麼打、怎麼讀、轉發本身連不上怎麼查，見 [remote-access〈ssh 轉發怎麼讀〉](remote-access.md#ssh-轉發怎麼讀)。

agent 那邊怎麼做寫在 agent-config 的 skill（`verify-in-browser`、`personal-pc-tunnel`），這份只寫你這邊的事。
為什麼這樣分見 [ADR 0001](adr/0001-browser-tools-drive-vs-debug.md)。

## 什麼時候要你出手

```
情況                                瀏覽器在哪          你在個人電腦開的轉發
─────────────────────────────────────────────────────────────────────────────────
操作、驗收、查原因                  已配置主機          不用
你要看畫面、接手、替它登入          已配置主機          本地轉發 9377（agent 給 port）
網站擋機房 IP                        已配置主機          反向 SOCKS 1080
一定要你本人的瀏覽器                個人電腦的 Chrome   本地轉發 9555
（passkey、硬體金鑰、裝置 SSO）
```

前兩種瀏覽器都在已配置主機上；擋 IP 時瀏覽器也不搬，只是網路流量改從你那台出去。只有最後一種才用你自己的 Chrome。
三條轉發的指令與別名在 [remote-access 的別名表](remote-access.md#ssh-轉發怎麼讀)。

## port、綁定與驗證

三個服務都起在**已配置主機**上，都只綁 `127.0.0.1`：

| 服務 | port | 誰起的 | 驗證 |
|---|---|---|---|
| `playwright-cli show`（看畫面、接手） | 9377，被佔時 agent 換一個並告訴你 | agent | **沒有**。連得到就能操作 |
| 反向 SOCKS proxy（借你的網路） | 1080 | 你開的 ssh 轉發 | **沒有**。連得到就能用你的網路出去 |
| `personal-chrome-attach` 的 relay（接你的 Chrome） | 9555（固定；relay 本身的 port 每次隨機，由它轉到 9555） | agent | extension 的 token（選用，見下面） |

## 對連線的要求

- **預設只走 tailnet 內，經 ssh 轉發連**（見 [remote-access〈tailnet 內〉](remote-access.md#tailnet-內)）。三個服務都沒有驗證或只靠 token，
  所以只綁 `127.0.0.1`，不改聽 `0.0.0.0`。唯一的例外是下面「tailnet 外的人要看畫面」。
- **一個 port 同時只能一條轉發**：你另一台電腦或另一個視窗還開著，新的那條就搶不到。
- **例外：tailnet 外的人要看畫面**：照 [remote-access〈tailnet 外〉](remote-access.md#tailnet-外) 把 9377 開出去。
  `show` 沒有驗證，公開網址開著的期間，誰拿到網址都能操作那個瀏覽器；Funnel 的網址是固定的
  `<機器>.<tailnet>.ts.net:<port>`，猜得到。所以只在對方要看的那段時間開，看完立刻收。
  這條**未實測**（`show` 會不會因為 `Host` 不是 `127.0.0.1` 而拒絕，還沒試過）。

## 看畫面、接手、替 agent 登入

1. agent 會說它開了 `show`，並給你一個 port（預設 9377）。
2. 個人電腦開一條本地轉發，把那個 port 拉到你這台（指令見 [remote-access〈ssh 轉發怎麼讀〉](remote-access.md#ssh-轉發怎麼讀) 的第一個例子）。
3. 瀏覽器開 `http://127.0.0.1:9377`，點 session 放大。點進畫面就能用滑鼠、鍵盤操作，按 Escape 交還給 agent。
4. 要替它登入：在這個畫面上登入就好，agent 接著用同一個 session，就會帶著登入狀態。
5. agent 說好了就按 Ctrl-C 關掉 ssh。

## 網站擋機房 IP

agent 說某個網站擋了機房 IP（驗證碼一直跳、影片不能播）時：

1. 個人電腦開反向 SOCKS 那條轉發（別名與完整指令見 [remote-access 的別名表](remote-access.md#ssh-轉發怎麼讀)）。
2. agent 會給你看它那邊的對外 IP，確認是你這台的。你的網路有 IPv6 時常會是 IPv6 位址，這是正常的。
3. agent 說用完了就按 Ctrl-C。開著的時候，agent 帶 proxy 的流量都走你的網路，所以只在被擋時開。

## 一定要你本人的瀏覽器

1. **第一次**：日常 Chrome 裝 [Playwright Extension](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm)。
2. 個人電腦開 9555 那條本地轉發（別名與完整指令見 [remote-access 的別名表](remote-access.md#ssh-轉發怎麼讀)）。
3. 在 agent 說的時間內（預設 5 分鐘）開一個**新分頁**（agent 會直接改這個分頁），網址列開 `http://127.0.0.1:9555/connect`，
   按「複製」，再把網址貼進同一個分頁的網址列、按 Enter。`/connect` 這個網址每次都一樣，可以加書籤。
   - 有設 token：貼完就接上了。
   - 沒設 token：貼完還要在 extension 畫面選這個分頁、按允許。這時 agent 也會直接給你網址，貼它給的也可以。
4. agent 說 detach 了就按 Ctrl-C。Chrome 和分頁都會留著。

agent 只看得到你貼網址的那個分頁，其他分頁讀不到。token 怎麼設見 agent-config 的
[personal-pc-tunnel](https://github.com/henry5720/agent-config/blob/main/docs/skills/personal-pc-tunnel.md)。

## 收掉什麼

| 情況 | 你這邊 | agent 那邊 |
|---|---|---|
| 看畫面、接手 | Ctrl-C 關掉 ssh | 收掉 `show`，9377 沒有程式在聽 |
| 借你的網路 | Ctrl-C 關掉 ssh，1080 跟著消失 | 不再帶 proxy |
| 接你的 Chrome | Ctrl-C 關掉 ssh；Chrome 和分頁留著 | detach，`personal-chrome-attach` 結束、9555 沒有程式在聽（沒人連進來時 5 分鐘後自己收） |
| 開到 tailnet 外過 | 照 [remote-access〈共通規則〉](remote-access.md#共通規則) 收掉公開網址 | 同左 |

## 連不上時

轉發本身的問題（`Address already in use`、ssh 斷線、`channel … open failed`）見
[remote-access〈ssh 轉發連不上〉](remote-access.md#ssh-轉發連不上)。app 這邊的：

| 現象 | 原因 | 怎麼處理 |
|---|---|---|
| `remote port forwarding failed`（借網路時） | 已配置主機上的 1080 被佔著，通常是你另一台電腦還開著 | 關掉另一台的 ssh；或請 agent 在它那邊用 `ss -ltnp \| grep 1080` 查 |
| 開得到但是空白、一直轉圈 | 已配置主機那邊的 `show` 或 `personal-chrome-attach` 還沒起來，或已經結束 | ssh 視窗會印 `channel … open failed`。請 agent 重新開，它會再給你 port 或網址 |
| agent 說逾時、要重來 | `personal-chrome-attach` 預設等 5 分鐘，沒人連進來就自己收掉 | 請 agent 重跑，重新開 `/connect` 複製（網址每次不同，舊的不能用） |
