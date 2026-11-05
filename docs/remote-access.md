# 開給別人連：remote-access

一台機器上有個 web server 在聽某個 port，要讓別人（或自己的另一台裝置）連進來。
這份是「把一個 port 開給別人連」的唯一說明；各 app 的文件只寫 app 自己的事（port、驗證、
對連線的要求、用完收什麼），怎麼開出去都連到這裡。

要開的東西都是 **web server**，自己用 CLI 前景起、只綁 127.0.0.1；「開給誰」是另外一層，就是這份。

## 判準

先問連的人在不在你的 tailnet，再問開出去的那台要不要加進你的 tailnet：

```
連的人在 tailnet 內？
├─ 是 → 直接連 tailnet IP：ssh -L／ssh -R／tailscale serve，不開公網   → tailnet 內
└─ 否 → 要給他一個公開網址
        開出去的那台要加進你的 tailnet？
        ├─ 要（或已經在）→ Tailscale Funnel                          → tailnet 外
        └─ 不要（別人的機器、臨時借用）→ Cloudflare quick tunnel     → tailnet 外
```

- **連的人在 tailnet 內就不開公網。** 公開網址誰拿到都能連，能不開就不開。
- **tailnet 外只看「那台要不要加進你的 tailnet」**，網址固不固定、能開幾個 port 這些是次要差異，
  見[比較表](#比較表)。那台已經在你的 tailnet 時預設用 Funnel：網址固定、沒有「只給測試」的限制。
  不是你的機器、不想拿你的帳號把它加進來，就用 quick tunnel。
- **ssh 一律走 tailnet。** 不另外架 Cloudflare Access SSH，也不把 22 開到公網。
- 不在這份範圍：有公開 IP 的 VPS 維持現狀（直接連它的公開 IP）；Cloudflare named tunnel、自己的網域不用。

## tailnet 內

連的人（通常是自己的另一台裝置）已經在 tailnet，直接連 tailnet IP 或 MagicDNS 名稱，不經公網。

| 做法 | 什麼時候用 | 例子 |
|---|---|---|
| `ssh -L <本機 port>:localhost:<遠端 port> <機器>` | 把那台的 port 拉到你這台的 localhost；瀏覽器開 `http://localhost:<port>`，不用憑證 | 連 code-server、看 agent 的瀏覽器 |
| `ssh -R <遠端 port>:localhost:<本機 port> <機器>` | 反過來，把你這台的 port 借給那台用 | 借你的網路或 Chrome 給 agent |
| `tailscale serve --https=443 <port>` | 給 tailnet 內的裝置一個帶真憑證的 `https://<機器>.<tailnet>.ts.net` | code-server 長駐、手機開 |

各 app 用哪一種、要注意什麼，看 app 自己的文件：

- [code-server 遠端存取](code-server-remote.md)：憑證怎麼選（A–E 方案）
- [看 agent 的瀏覽器](browser-via-ec2.md)：port、token、`-L`／`-R` 怎麼讀

`tailscale serve` 只開給 tailnet，跟 Funnel 不同，可以用 `--bg` 長駐（code-server 就是這樣）。

## tailnet 外

對方不在你的 tailnet，可能連 ssh key 都沒有，只有瀏覽器。要給他一個**公開網址**，
誰拿到都能連，所以擋陌生人的只剩 app 自己的驗證：

| server | 誰擋陌生人 | 能開到公網嗎 |
|---|---|---|
| dev server | app 自己的登入 | 可以，對方看到的就是你的網站 |
| ttyd | **它自己沒有密碼**，`share-shell` 每次產一組 | 可以，用 `share-shell` |
| code-server | 自己的固定密碼 | **不要**：它能開 terminal，等於整台機器，只靠一組固定密碼 |

### Tailscale Funnel

開出去的那台要**跑得到登入你 tailnet 的 tailscale**：Linux、WSL、Windows 都算。
Windows 原生的 tailscale 開 Funnel **未實測**。

```bash
sudo tailscale funnel --https=10000 <port>     # 不加 --bg，Ctrl+C 就撤
```

開不起來時查這三項（[Tailscale Funnel 官方文件](https://tailscale.com/docs/features/tailscale-funnel)）：

- **只能用 443、8443、10000**（"Funnel can only listen on ports 443, 8443, and 10000"）。
  company-ec2 的 443 給 code-server 的 tailnet serve 用了，所以用 10000。
- **tailnet 要開 MagicDNS 和 HTTPS 憑證。**
- **tailnet policy 要有 `funnel` node attribute**，決定誰能開 Funnel。第一次開會給一個 admin console 連結開權限。

另外兩件事：

- **company-ec2 上要 sudo**（沒有 sudo 回 `Access denied`）。`tailscale set --operator=$USER`
  能免 sudo，但那是永久放寬，沒設。
- 官方標 Funnel 為 beta，流量有不能調的頻寬上限。

### Cloudflare quick tunnel

開出去的那台不加進你的 tailnet，只要有 `cloudflared`，不用 Cloudflare 帳號：

```bash
cloudflared tunnel --url http://localhost:<port>    # 印出 https://<隨機>.trycloudflare.com
```

限制（[Cloudflare Quick Tunnels 官方文件](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)）：

- **只給測試和開發用**（"Quick Tunnels are for testing and development"）。
- **不支援 SSE**（Server-Sent Events）。用 SSE 的 app（例如 MCP streamable HTTP）可能會壞。
- **每條最多 200 個並行請求**，超過的回 `429`。
- **網址每次都變**：每開一次就是新的 hostname，要重新傳給對方。

`cloudflared` 不在 chezmoi 的套件清單裡：用得到 quick tunnel 的機器本來就不歸 chezmoi 管。

### shell：`share-shell`

在 Funnel 上開一個網頁版 shell：

```bash
share-shell                                   # 開 login zsh
share-shell herdr session attach default      # 最後面接什麼，網頁就開什麼（tail -f 也行）
```

```
  https://company-ec2.tail9b4b9b.ts.net:10000
  帳號 guest  密碼 <每次隨機>
  (Ctrl+C 關閉，關了就失效)
```

整段複製給對方。用完 Ctrl+C，或直接關掉那個終端機。

```
對方的瀏覽器 ──公網──► funnel :10000 ──► ttyd 127.0.0.1:7681
```

`share-shell` 同時起這兩個，Ctrl+C 一起關。

script 在 [`home/dot_local/bin/executable_share-shell`](../home/dot_local/bin/executable_share-shell)。
它比 dev server 多做的只有一件：**幫 ttyd 產密碼**。

- **密碼每次隨機。** 這是公網上能打字的 shell（`-W`），擋在前面的只有這組密碼。固定密碼等於
  每個拿過的人永遠有效，貼在聊天室也收不回來。反正網址也要傳給對方，順便帶上密碼不多一步。
- **從 herdr 的 pane 裡跑也能 attach herdr。** ttyd 會繼承 `HERDR_ENV`，網頁裡再
  `herdr session attach` 會被當成巢狀擋掉（nested herdr is disabled）；script 起 ttyd 前先拿掉它。
- **要不要 sudo 自己判斷**：看 `tailscale debug prefs` 的 `OperatorUser`，是你就不加。

2026-10-02 在 company-ec2 實測收尾：

| 怎麼結束的 | funnel | ttyd |
|---|---|---|
| Ctrl+C（SIGINT） | 撤掉 | 被 trap 收掉 |
| 整個 process group 被 SIGKILL（例如 herdr 關 pane） | 撤掉，公網連過去 connection refused | 跟著死 |

### dev server：兩行，不用 script

兩個終端機，都不加 `--bg`，Ctrl+C 就收：

```bash
VITE_ALLOWED_HOSTS=<機器>.<tailnet>.ts.net pnpm dev      # 不設的話 Vite 回 Blocked request
sudo tailscale funnel --https=10000 <dev server 的 port>
```

- **port 看 dev server 啟動時印的那行。** teamsync-frontend 是 3000（`vite.config.js` 的
  `server.port`），而且 `strictPort: false`，3000 被佔了會往後跳。
- **`VITE_ALLOWED_HOSTS` 是 teamsync-frontend 的 `vite.config.js` 自己讀的**（逗號分隔），
  不是 Vite 內建的環境變數，別的專案不一定有。

### code-server：不開給訪客

code-server 本身就能開 terminal，給出去等於給整台機器；它的密碼又是固定的，給過就收不回。
真的要讓人看你的畫面，用 `share-shell` 開 shell 就好。自己從別台連 code-server 走
[tailnet 內](#tailnet-內)。

## 比較表

tailnet 外的兩種做法：

| | Tailscale Funnel | Cloudflare quick tunnel |
|---|---|---|
| 網址 | 固定 `<機器>.<tailnet>.ts.net` | 每次變（`<隨機>.trycloudflare.com`） |
| 對外 port | 443／8443／10000 | 一律 443 |
| 能開幾個 | 每台 3 個 port | 每個 `cloudflared` process 一個網址 |
| SSE | 支援（官方文件沒列限制） | 不支援 |
| 並行請求 | 官方文件沒寫上限 | 200，超過回 `429` |
| 官方定位 | beta | 只給測試、開發 |
| 開的那台要有 | 登入你 tailnet 的 tailscale | `cloudflared` |

出處：[Tailscale Funnel](https://tailscale.com/docs/features/tailscale-funnel)、
[Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)。

## 共通規則

開了公開網址（Funnel 或 quick tunnel）都照這套：

```
開：sudo tailscale funnel --https=10000 <port>  ─► 印網址 ─► 停著（對方在用）
    cloudflared tunnel --url http://localhost:<port>
關：Ctrl+C／關終端機 ───────────────────────────► 撤掉，不留痕跡
```

- **前景跑。** 開在一個終端機裡停著，對方用完就 Ctrl+C 或關掉終端機。
- **Funnel 不加 `--bg`。** 不加就是前景模式：不寫進 `tailscale serve status` 的持久設定，
  行程結束就撤掉，也不會動到同一台已經在跑的其他 serve（company-ec2 的 code-server）。
  以前用 `--bg` 開，要記得手動 `off`；2026-10-02 發現 company-ec2 的公網 shell 開了 21 小時沒關。
- **用完收掉。** 收完確認沒有程式還在聽那個 port，`tailscale funnel status` 裡沒有這個 port、
  `cloudflared` 也結束了。
