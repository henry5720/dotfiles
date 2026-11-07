# 開給別人連：remote-access

一台機器上有個服務在聽某個 port，要讓別人、agent 或自己的另一台裝置連進來。
這份只講**連線**；每個服務自己的事（port、驗證、人看什麼、agent 接什麼、用完收什麼）寫在服務卡：

- [瀏覽器](browser.md)：agent 自己的 headless、你的獨立 profile（9222）、插件（裝在獨立或日常 profile，tailnet 外也接得上）
- [網頁 shell：share-shell](share-shell.md)
- [code-server](code-server.md)
- [朗讀串流：voice-out](voice-out.md)：agent 的回覆唸到 tailnet 內的個人電腦

## 概念

```
操作者   人（要畫面）／agent（要協定：CDP、MCP、ssh）
  │
連線     同一台    → 直接連 127.0.0.1
  │      tailnet 內 → ssh -L／-R、tailscale serve
  │      tailnet 外 → Funnel、quick tunnel（公開網址）
  │
服務     瀏覽器、shell、code-server、dev server…（各自有 port、有沒有驗證）
```

agent 跑在另一台時，它的 `localhost` 不是你的；用哪一條只看連的那一方在哪。

- ssh 轉發：[A Practical Guide to SSH Tunnels](https://newsletter.iximiuz.com/posts/a-practical-guide-to-ssh-tunnels-local-and-remote-port-forwarding)
- serve／Funnel：[Tailscale Funnel](https://tailscale.com/docs/features/tailscale-funnel)
- quick tunnel：[Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)

服務自己用 CLI 前景起、只綁 127.0.0.1；「開給誰」是這份。

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

各服務用哪一種、要注意什麼，看它的服務卡（[瀏覽器](browser.md)、[code-server](code-server.md)）。

`tailscale serve` 只開給 tailnet，跟 Funnel 不同，可以用 `--bg` 長駐（code-server 就是這樣）。

### ssh 轉發怎麼讀

三個旗標就夠用：

| 旗標 | 意思 |
|---|---|
| `-N` | 只開通道、不開 shell。視窗會停住不動是正常的，**開著別關**；用完按 Ctrl-C。 |
| `-L` | 本地轉發：**你這台**的 port 接到那台的 port。用來在你的瀏覽器看那台上的東西。 |
| `-R` | 遠端轉發：**那台**的 port 接回你這台。用來讓那台借你這台的網路或 Chrome。 |

```
ssh -N -L 127.0.0.1:9377:127.0.0.1:9377 company-ec2
          └─ 你這台聽哪裡 ─┘└─ 到了那台後連哪裡 ─┘

   個人電腦                               company-ec2
   瀏覽器 → 127.0.0.1:9377 ══ssh══▶ 127.0.0.1:9377（agent 的畫面）

ssh -N -R 127.0.0.1:1080 company-ec2    （只寫一個 port、不寫目的地 = 反向 SOCKS proxy）

   個人電腦                               company-ec2
   你的網路 → 網站 ◀══ssh══ 127.0.0.1:1080 ← headless 瀏覽器帶 proxy
```

- **一定寫 `127.0.0.1`**：只讓同一台的程式連得到。被轉發的服務多半沒有驗證，聽 `0.0.0.0` 等於開給整個網路。
- **一個 port 同時只能一條**：同一個 port 在兩個視窗（或兩台電腦）各開一條，第二條會失敗。
  加 `-o ExitOnForwardFailure=yes` 時搶不到就直接結束、印出錯誤，不會默默連上卻沒有轉發。
- **ssh config 的 Host 不寫轉發**：每條連線都帶的話，你開第二個視窗就搶不到 port。
  要轉發時另打一條帶 `-L`／`-R` 的 ssh，用完就關。例外是 `ssh phone`（Termux 的 code-server，見 [code-server](code-server.md)）。
- Windows 內建的 OpenSSH 用法一樣，指令照打。

要轉發時打的完整指令（`company-ec2` 換成你要連的 Host）：

```bash
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:<port>:127.0.0.1:<port> company-ec2   # 把那台的 port 拉到你這台
ssh -N -o ExitOnForwardFailure=yes -R 127.0.0.1:<port>:127.0.0.1:<port> company-ec2   # 把你這台的 port 借給那台
ssh -N -o ExitOnForwardFailure=yes -R 127.0.0.1:1080 company-ec2                      # 反向 SOCKS：那台借你的網路
```

怎麼確認通了：ssh 停住不動、沒有印錯誤；在要連的那一端 `curl -sI http://127.0.0.1:<port>` 有回應。
各服務用哪個 port 見服務卡。

`LocalForward` 左邊在**執行 ssh 的那台**開 port，右邊的 `localhost` 在**那台**上解析。
連線中要臨時加 port：換行後按 `~C`，輸入 `-L 5173:localhost:5173`。

### ssh 轉發連不上

| 現象 | 原因 | 怎麼查、怎麼處理 |
|---|---|---|
| ssh 一開就結束，訊息有 `Address already in use` | 你這台的這個 port 被別的程式或另一個 ssh 視窗佔著 | Linux：`ss -ltnp \| grep <port>`；Windows：`netstat -ano \| findstr <port>`。把舊的 ssh 視窗關掉 |
| ssh 一開就結束，訊息有 `remote port forwarding failed` | 那台上的 port 被佔著，通常是你另一台電腦還開著 | 關掉另一台的 ssh；或在那台用 `ss -ltnp \| grep <port>` 查 |
| 瀏覽器開 `127.0.0.1:<port>` 連不上 | ssh 沒開或已經斷線 | 確認 ssh 視窗還停著；斷了就重開 |
| 開得到但是空白、一直轉圈，ssh 視窗印 `channel … open failed` | 那台的 port 上沒有程式在聽 | 回 app 的文件，確認 server 起了、port 對 |

### tailscale serve

給 tailnet 內的裝置一個帶真憑證的網址，app 不用改設定，tailscale 在前面當反向代理並終結 TLS：

```bash
tailscale serve --bg --https=443 <port>     # 設一次就常駐
tailscale serve status                      # 確認，順便看到完整網址
tailscale serve --https=443 off             # 撤掉
```

之後 tailnet 裡任何裝置的瀏覽器開 `tailscale serve status` 印的網址（`https://<機器>.<tailnet>.ts.net`，不用打 port）。
前提是 admin console 開了 MagicDNS 和 HTTPS Certificates（Settings → DNS）。
Android 的 Tailscale app 沒有 CLI，手機上開不了 serve。

> ⚠️ **listener 不能跟後端同一個 port**（別寫成 `--https=8080 8080`）。
> WSL 用 `networkingMode=mirrored` 時 Windows 和 WSL **共用 port 空間**：Windows 的 tailscaled 一綁
> `<tailnet IP>:8080`，WSL 這邊 `bind 127.0.0.1:8080` 就會拿到
> `[Errno 98] Address already in use`，app 根本起不來。listener 走 443、後端走 app 的 port 就錯開了。

#### Windows／WSL：serve 設在哪個節點

WSL 可能有自己的 tailscale 節點，Windows 也有一個。下面的節點名稱、IP、介面只是作者機器曾經觀察到的範例，
**不可當成通用設定**。先在 Windows 和 WSL 各查一次：

```powershell
tailscale status
tailscale serve status
```

```bash
ip addr
```

作者的 henry-desktop、henry-laptop 都把 serve 設在 **Windows** 節點（Windows PowerShell 跑上面的 serve 指令，不用系統管理員權限），
app 在 WSL 裡綁 `127.0.0.1`，靠 mirrored networking 跨進 WSL：

```
tailnet 裡的瀏覽器 ──https :443──► Windows tailscaled（終結 TLS）
                                    └─proxy 127.0.0.1:<port>，mirrored 跨進 WSL──► WSL 裡的 app
```

> ⚠️ **從 WSL 裡打那個網址會 timeout，那是正常的，不是設定壞了。**
> WSL 有自己的 tailscale 節點，從它去連同一台實體機器上的 Windows 節點是自我參照的路徑，
> 不會通。要在本機驗證就直接打 `curl -I http://127.0.0.1:<port>`，
> 或從 Windows 側跑 `curl.exe --noproxy '*' https://<機器>.<tailnet>.ts.net`。

> ⚠️ 用 PowerShell 的 `Invoke-WebRequest` 測會失敗，但那不是服務的問題 ——
> `.wslconfig` 有 `autoProxy=true`，Windows 的代理設定被同步過來，`Invoke-WebRequest`
> 會照系統代理走而連不到 localhost。測試一律加 `--noproxy '*'`（curl）或直接用 TCP 連線。

#### WSL 那個節點要不要留

打算收掉、統一走 Windows 節點的話，先確認 `.ssh/config` 裡的 Host 還連得到 ——
作者過去觀測到它們透過 **WSL 自己的 tailscaled**（tailnet IP）連通，這不是普遍現況，以 `ssh <host>` 和 `tailscale status` 查到的為準。

作者過去的 `/etc/resolv.conf` 曾指向 `100.100.100.100`（MagicDNS），也由 WSL tailscaled 提供；
作者曾實測把來源位址強制指到 `eth1`（Windows 節點那條）**連不通**，
所以「鏡射進來的介面有路由」不等於「traffic 走得通」。

不要在依賴這條連線的遠端 session 執行停止；先填好目標資料，並確保本機可恢復，再關掉前這樣試：

```bash
sudo systemctl stop tailscaled
target_ip='<查到的 tailnet IP>'
magic_dns_name='<查到的 MagicDNS 主機名>'
timeout 6 bash -c 'exec 3<>/dev/tcp/'"$target_ip"'/22 && echo OK'
getent hosts "$magic_dns_name"
```

`Connection refused` 也算通 —— 代表封包有到對方，只是那個 port 沒服務；`timeout` 才是不通。

通了就 `sudo systemctl disable --now tailscaled`。不通的話，要嘛保留 WSL 這個節點（它其實不礙事），
要嘛把那些 Host 改走 Windows 的 ssh。serve 設在 Windows 節點上的 app 不受影響。

## tailnet 外

對方不在你的 tailnet，可能連 ssh key 都沒有，只有瀏覽器。要給他一個**公開網址**，
誰拿到都能連，所以擋陌生人的只剩 app 自己的驗證：

| server | 誰擋陌生人 | 能開到公網嗎 |
|---|---|---|
| dev server | app 自己的登入 | 可以，對方看到的就是你的網站 |
| ttyd | **它自己沒有密碼**，`share-shell` 每次產一組 | 可以，用 [share-shell](share-shell.md) |
| code-server | 自己的固定密碼 | **不要**：它能開 terminal，等於整台機器，只靠一組固定密碼 |
| 瀏覽器（CDP 9222、`show` 9377） | **沒有** | **不要**：拿到網址等於拿到那支 Chrome 的所有登入；CDP 還會擋外來的 `Host`。只走 ssh，見[瀏覽器〈能怎麼連〉](browser.md#能怎麼連) |
| 瀏覽器插件 9555 | connect 網址裡的隨機路徑，加上人在插件畫面按允許 | 可以，只用一次性 tcp tunnel：`personal-chrome-attach --tunnel` 開，connect 網址就是鑰匙，用完就收掉。見[瀏覽器〈tailnet 外〉](browser.md#tailnet-外一次性-tunnel) |

### Tailscale Funnel

開出去的那台要**跑得到登入你 tailnet 的 tailscale**：Linux、WSL、Windows 都算。
Windows 原生的 tailscale 開 Funnel 已實測（2026-11-05，henry-laptop）：公網不帶 key 回 401、帶 key 回 200。

```bash
sudo tailscale funnel --https=10000 <port>     # 不加 --bg，在這台的終端機 Ctrl+C 就撤
```

**對外 port 選哪個**：Funnel 只能聽 443、8443、10000，三個都能用，挑沒被佔的；同一個 port 同時只能開一條。
只看 `tailscale funnel status` 不夠：前景開著的 Funnel 在那裡只印 `# Funnel on:` 接 `No serve config`，
看不出有一條在開。還要看那台有沒有 `tailscale funnel` 行程在跑那個 port
（Linux `pgrep -af 'tailscale funnel'` 看得到參數，Windows `Get-Process tailscale` 有行程就當作被佔）。

這份的例子都用 10000，因為 company-ec2 的 443 給 code-server 的
tailnet serve 用了（`share-shell` 也固定開 10000）。agent 照 `expose-port` skill 開時預設 8443：
443 常被 serve 佔，8443 又剛好跟這份手動開的 10000 錯開，同一台可以同時開。

開不起來時查這三項（[Tailscale Funnel 官方文件](https://tailscale.com/docs/features/tailscale-funnel)）：

- **只能用 443、8443、10000**（"Funnel can only listen on ports 443, 8443, and 10000"），挑法見上面。
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
  2026-11-05 實測：單次請求的 SSE 回應（MCP 的 initialize、tools/list）收得到，長時間開著的 stream 未測。
- **每條最多 200 個並行請求**，超過的回 `429`。
- **網址每次都變**：每開一次就是新的 hostname，要重新傳給對方。

chezmoi 管的機器在工具選單勾 `cloudflared` 就會裝（見 [工具一覽](../tools.md#入口與連線)）；不歸 chezmoi 管的機器（例如別人的 Windows）自己裝，Windows 用 `winget install --id Cloudflare.cloudflared -e`，裝完當下的 PowerShell 找不到它，用完整路徑 `C:\Program Files (x86)\cloudflared\cloudflared.exe`。

### shell：`share-shell`

在 Funnel 上開一個帶隨機密碼的網頁 shell，見 [share-shell](share-shell.md)。

### dev server：兩行，不用 script

兩個終端機，都不加 `--bg`，Ctrl+C 就收：

```bash
VITE_ALLOWED_HOSTS=<機器>.<tailnet>.ts.net pnpm dev      # 不設的話 Vite 回 Blocked request
sudo tailscale funnel --https=10000 <dev server 的 port>   # 10000 被佔就換 8443，見〈對外 port 選哪個〉
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
| SSE | 支援（官方文件沒列限制） | 官方說不支援；實測單次請求的 SSE 回應收得到，長時間 stream 未測 |
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
關：在那台自己的終端機 Ctrl+C ──────────────────► 撤掉
    從 ssh／WSL 叫起來的 ─► 停掉那台的行程 ────────► 撤掉
```

- **前景跑。** 開在一個終端機裡停著，對方用完在那台自己的終端機按 Ctrl+C。
  從 ssh 或 WSL 叫起 Windows 的 `tailscale`／`cloudflared` 時，斷掉呼叫端**不等於**行程結束：
  2026-11-05 在 henry-laptop 實測，斷 ssh 後 `tailscale.exe`、`cloudflared.exe` 還在跑、公網還通，
  要在 Windows 上 `Get-Process tailscale,cloudflared | Stop-Process` 才收掉。
- **Funnel 不加 `--bg`。** 不加就是前景模式：不寫進 `tailscale serve status` 的持久設定，
  行程結束就撤掉，也不會動到同一台已經在跑的其他 serve（company-ec2 的 code-server）。
  以前用 `--bg` 開，要記得手動 `off`；2026-10-02 發現 company-ec2 的公網 shell 開了 21 小時沒關。
- **用完收掉。** 兩項都成立才算收乾淨：
  1. 那台的 `tailscale funnel`／`cloudflared` 行程數是 0（Linux `pgrep -af 'tailscale funnel|cloudflared'`，
     Windows `Get-Process tailscale,cloudflared`）。不能用 `tailscale funnel status` 判斷，理由見〈對外 port 選哪個〉。
  2. 從公網打那個網址連不上：`000`（連線失敗）、`530`（quick tunnel 已收）或 DNS 查不到。
