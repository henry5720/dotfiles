# code-server 遠端存取:五種做法

從別台裝置（pad、phone、筆電）連自己的 code-server，卡點永遠是同一個：**憑證**。
這份列出所有可行做法和各自代價，phone 和 desktop 各自選一個就好。

---

## 先把它裝起來

`script/ubuntu/install-tools.sh` 的選單裡選 `code-server`,會用官方腳本裝 binary。
設定檔不用自己弄,由 chezmoi 從 `home/dot_config/private_code-server/private_config.yaml.tmpl`
部署(權限與密碼見[密碼放哪](#密碼放哪))。

```bash
code-server     # 要用的時候再開,丟 tmux 裡
```

預設只綁 `127.0.0.1:8080`、`cert: false` —— **假設 TLS 由外層處理**,也就是下面五種做法的前提。

---

## 先搞懂卡在哪

瀏覽器只把兩種來源當成 **secure context**：`https://`（憑證有效）和 `localhost`。
不是 secure context 的話，code-server 這些功能會壞：

- webview（markdown preview、大部分擴充套件的 UI）
- 剪貼簿 API
- service worker——這個最硬，**憑證有錯誤時 Chrome 直接拒絕註冊**，按「繼續前往」也沒用

所以 `http://100.119.136.27:8080` 這種 tailscale IP 直連，是「連得到但不好用」。
tailscale 負責的是**連得到**，secure context 要另外生出來。

---

## 方案總表

| | 做法 | 誰負責 TLS | 要改 code-server 設定 | 主要代價 |
|---|---|---|---|---|
| **A** | SSH tunnel（`ssh -L`） | 不需要，走 localhost | 否 | 每次要先開 tunnel，斷線就掛 |
| **B** | `tailscale serve` | tailscale（真憑證） | 否 | 需要該台有 tailscale CLI |
| **C** | `tailscale cert` + code-server 吃憑證 | code-server（真憑證） | 是 | 憑證要自己續期 |
| **D** | code-server 自簽憑證 | code-server（自簽） | 是 | service worker 會壞 |
| **E** | mkcert 自簽 + 手機裝 CA | code-server（自簽但被信任） | 是 | 每台 client 都要裝 CA |

B、C 的憑證都是 tailscale 幫你跟 Let's Encrypt 要的**真憑證**，網域是
`<機器名>.<你的 tailnet>.ts.net`。前提是 admin console 要開 MagicDNS 和 HTTPS Certificates
（Settings → DNS）。

---

## phone(Termux)可以用哪些

**能用：A、D、E。B、C 實質上不行。**

原因：Android 的 Tailscale app 只有 GUI，沒有 CLI，`tailscale serve` 和 `tailscale cert`
都碰不到。要有 CLI 就得在 Termux 自己裝 tailscale + tailscaled，而且非 root 沒有 TUN 權限，
得跑 `--tun=userspace-networking`——它會變成 tailnet 裡的**第二個節點**（跟 app 那個不同 IP、
不同名字），加上 Android 會殺背景 process，還要 `termux-wake-lock` 和 Termux:Boot 才活得久。

### A|SSH tunnel（建議）

`.ssh/config` 的 `Host phone` 已經備好了。流程是 **phone 跑服務，pad 或 desktop
發起 SSH，再由發起端的瀏覽器開 localhost**：

```text
phone code-server ← SSH tunnel ← 發起端瀏覽器 localhost:8080
```

```bash
# phone (Termux):code-server 綁 127.0.0.1,不對外開
code-server --bind-addr 127.0.0.1:8080

# pad 或 desktop：
ssh phone
# 同一台發起端的瀏覽器開 http://localhost:8080
```

前提是 phone 能跑 code-server，且發起端能以 `Host phone` 連到 phone；目前
`home/private_dot_ssh/private_config` 的 `LocalForward 8080 localhost:8080`
會把 phone 的 8080 映射到發起端。

`LocalForward` 左邊在**執行 ssh 的那台**開 port，右邊的 `localhost` 在 **phone 上**解析。
連線中要臨時加 port：換行後按 `~C`，輸入 `-L 5173:localhost:5173`。

---

## henry-desktop 可以用哪些

**全部都能用。B 最省事。**

作者這台 WSL 曾因 `.wslconfig` 設了 `networkingMode=mirrored`（`wsl/.wslconfig`），
eth0 上直接掛著 tailnet IP `100.119.136.27`，WSL 裡的服務綁 `127.0.0.1`，
Windows 側也看得到，中間不用接任何東西。

這個 IP、介面與 DNS 行為只是作者機器的觀察值，不保證你現在或其他主機相同；先用
`tailscale status`、`ip addr`、`tailscale serve status` 查自己的現況。

作者這台的 tailscale CLI 在 Windows；WSL 內曾是 `Logged out`。這不是通用前提，請先查
`tailscale status`，確認你要用的節點及登入狀態。

### B|tailscale serve（建議）

code-server 完全不用改設定，tailscale 在前面當反向代理並終結 TLS：

```powershell
# Windows PowerShell,設一次就常駐
tailscale serve --bg --https=443 8080
tailscale serve status      # 確認,順便看到完整網址
```

之後任何裝置的瀏覽器開 `https://henry-desktop.<你的 tailnet>.ts.net`（不用打 port）。

要撤掉：`tailscale serve --https=443 off`。

> ⚠️ **listener 不能跟後端同一個 port**（別寫成 `--https=8080 8080`）。
> mirrored networking 下 Windows 和 WSL **共用 port 空間**：Windows 的 tailscaled 一綁
> `100.119.136.27:8080`，WSL 這邊 `bind 127.0.0.1:8080` 就會拿到
> `[Errno 98] Address already in use`，code-server 根本起不來。
> listener 走 443、後端走 8080 就錯開了。

### C|tailscale cert + code-server 吃憑證

不想多一層 proxy、想讓 code-server 自己講 HTTPS 的話：

```text
Windows 產生/保存憑證 → WSL /mnt/c/... 路徑 → 修改 source template → chezmoi diff/apply
```

在 Windows 產生並保存到你選的目錄（以下只是 placeholder，不是固定路徑）：

```powershell
$certDir = "$env:USERPROFILE\certs"
New-Item -ItemType Directory -Force $certDir
Set-Location $certDir
tailscale cert henry-desktop.<你的 tailnet>.ts.net
```

再把產出的 `.crt` / `.key` 對應成 WSL 可讀的 `/mnt/c/Users/<WindowsUser>/certs/...`，修改
repo 裡的 `home/dot_config/private_code-server/private_config.yaml.tmpl`（內有示例路徑）中的
`cert` / `cert-key`，最後檢查並套用：

```bash
chezmoi diff
chezmoi apply
```

不要直接改部署後的 `~/.config/code-server/config.yaml`；憑證私鑰也不要放進 repo。

代價：憑證約 90 天到期，要自己排程重跑 `tailscale cert`，B 沒這問題。

### A|SSH tunnel

臨時用、不想動任何設定的時候：

```bash
ssh -L 8080:localhost:8080 henry-desktop
```

---

## 其他 Windows/WSL 主機：先查現況再套用

下面的節點名稱、IP、介面只是作者機器曾經觀察到的範例，**不可當成通用設定，也不代表目前仍相同**。
先在對應的 Windows/WSL 端查詢：

```powershell
tailscale status
tailscale serve status
```

```bash
ip addr
```

確認實際節點、tailnet IP 和介面後，再決定 serve 是設在 Windows 節點或 WSL 節點。

若確認要用 Windows 節點，serve 設在 Windows 那個節點：

```powershell
# Windows PowerShell,不需要系統管理員權限
tailscale serve --bg --https=443 8080
tailscale serve status
```

`tailscale serve status` 顯示的網址才是實際網址；tailnet 內瀏覽器直接開，不要套用作者的主機名。
code-server 設定一行都不用改,`bind-addr` 保持 `127.0.0.1:8080`、`cert: false`。

路徑是這樣接起來的:

```
瀏覽器 → tailscale serve status 顯示的 HTTPS 網址
       → Windows tailscaled(實際 tailnet IP:443,終結 TLS)
       → proxy http://127.0.0.1:8080
       → mirrored networking 跨進 WSL
       → code-server(綁 127.0.0.1:8080)
```

> ⚠️ **從 WSL 裡打那個網址會 timeout,那是正常的,不是設定壞了。**
> WSL 有自己的 tailscale 節點,從它去連同一台實體機器上的 Windows 節點是自我參照的路徑,
> 不會通。要在本機驗證就直接打 `curl -I http://127.0.0.1:8080`(回 302 就是活的),
> 或從 Windows 側跑 `curl.exe --noproxy '*' https://henry-laptop.<tailnet>.ts.net`。

> ⚠️ 用 PowerShell 的 `Invoke-WebRequest` 測會失敗,但那不是服務的問題 ——
> `.wslconfig` 有 `autoProxy=true`,Windows 的代理設定被同步過來,`Invoke-WebRequest`
> 會照系統代理走而連不到 localhost。測試一律加 `--noproxy '*'`(curl)或直接用 TCP 連線。

### WSL 那個節點要不要留

打算收掉、統一走 Windows 節點的話，先確認 `.ssh/config` 裡的 Host 還連得到 ——
作者過去觀測到它們透過 **WSL 自己的 tailscaled**（tailnet IP）連通；這不是普遍現況：

不要把本文件的主機名或 IP 當成你的現況；以 `ssh <host>` 和 `tailscale status` 查到的值為準。

作者過去的 `/etc/resolv.conf` 曾指向 `100.100.100.100`(MagicDNS)，也由 WSL tailscaled 提供；
作者曾實測把來源位址強制指到 `eth1`(Windows 節點那條)**連不通**，
所以「鏡射進來的介面有路由」不等於「traffic 走得通」。

不要在依賴這條連線的遠端 session 執行停止；先填好目標資料，並確保本機可恢復，再關掉前這樣試：

```bash
sudo systemctl stop tailscaled
target_ip='<查到的 tailnet IP>'
magic_dns_name='<查到的 MagicDNS 主機名>'
timeout 6 bash -c 'exec 3<>/dev/tcp/'"$target_ip"'/22 && echo OK'
getent hosts "$magic_dns_name"
```

`Connection refused` 也算通 —— 代表封包有到對方,只是那個 port 沒服務;`timeout` 才是不通。

通了就 `sudo systemctl disable --now tailscaled`。不通的話,要嘛保留 WSL 這個節點(它其實不礙事),
要嘛把那五個 Host 改走 Windows 的 ssh。

**code-server 這條線不受影響** —— serve 本來就設在 Windows 節點上。

---

## D、E:自簽憑證(兩台都適用,但都有坑)

### D|code-server 自己產自簽憑證

```yaml
# home/dot_config/private_code-server/private_config.yaml.tmpl,改完 chezmoi apply
cert: true
```

或 `code-server --cert`。憑證產在 `~/.local/share/code-server/self-signed.crt`。

**坑**：瀏覽器不信任自簽憑證，按「繼續前往」可以看到畫面，但 Chrome 會擋掉
service worker 註冊（`Failed to register a ServiceWorker`），部分擴充套件會壞。
`https://` 這個 scheme 本身讓 `isSecureContext` 為 true，所以剪貼簿等 API 大多還能用，
但這是「半殘」狀態，能選 B/C 就別選這個。

### E|mkcert 產憑證 + 手機裝 CA

把 D 的坑補起來：用 mkcert 建一個本機 CA，把 `rootCA.pem` 裝到每台要連的裝置上，
之後憑證就是「被信任的」，service worker 正常。

```bash
mkcert -install
mkcert henry-desktop.local 100.119.136.27
# 把產出的 pem 填進 private_config.yaml.tmpl 的 cert / cert-key,chezmoi apply
```

**坑**：每台 client 都要裝 CA。Android 裝的是 user CA——Chrome 瀏覽網頁認，
但 app 不認，而且系統會一直顯示「網路可能受監控」。Android 11 之後對 CA 的限制也越來越緊。

適用情境：完全離線、沒有 tailscale 的環境。有 tailscale 就直接用 B。

---

## 密碼放哪

tailscale 那層已經擋掉 tailnet 以外的人,code-server 的密碼是第二道。

設定檔由 chezmoi 從 `home/dot_config/private_code-server/private_config.yaml.tmpl` 產生
`~/.config/code-server/config.yaml`,權限由 `private_` 前綴保證(目錄 700 / 檔案 600)。
密碼**不填在 template 裡**——那份在 git 裡,而且這個 repo 是公開的。argon2 hash 一樣不能放,
它是可以離線爆的。

密碼改由 `chezmoi init` 互動詢問一次,存在 `~/.config/chezmoi/chezmoi.toml`(repo 外),
以 template 變數 `{{ .codeServerPassword }}` 帶入。事後要改密碼:

```bash
chezmoi edit-config   # 改 codeServerPassword
chezmoi apply
```

明碼就夠了。tailscale 已經把非 tailnet 的人全擋在外面,code-server 自己的預設也是明碼
(第一次啟動會產一組隨機的寫進 config.yaml)。唯一要守的是**別用你其他地方在用的密碼**,
明碼落在磁碟上,外洩就是直接可用。

想更保險再換 argon2 hash(`echo -n '你的密碼' | npx argon2-cli -e`),`hashed-password`
優先於 `password`,兩個留一個,一樣改在 template 裡再 `chezmoi apply`。兩個都空著的話
code-server 啟動會直接報錯(`main.js:152`),不會偷偷放行。

環境變數 `HASHED_PASSWORD` / `PASSWORD` 又會蓋過設定檔
(code-server 讀完會把它們從 `process.env` 刪掉,不傳給子 process),但**只有你手動在終端機
前景跑 `code-server` 時才有用**——systemd 起的 service 不經過 shell,讀不到任何 shell rc。

要手機隨時連得到就得常駐,所以走 systemd:

```bash
systemctl --user enable --now code-server
sudo loginctl enable-linger "$USER"   # 沒開終端機時也讓它活著
```

⚠️ WSL 的限制:Windows 重開機後 WSL 不會自己起來,systemd 服務也就不在,手機會連不到。

## 一句話結論

- **phone** → A（`ssh phone`，config 已備好）
- **henry-desktop** → B（`tailscale serve`，設一次就好）
- **henry-laptop** → B（同上,serve 設在 **Windows** 那個節點;WSL 裡打那個網址會 timeout 是正常的）

---

## 參考

- [code-server：TLS 設定](https://coder.com/docs/code-server/guide)（`--cert` / `--cert-key`、自簽憑證路徑）
- [code-server #6809：自簽憑證下 plugin 失效](https://github.com/coder/code-server/issues/6809)
- [code-server #7206：insecure context 的症狀](https://github.com/coder/code-server/discussions/7206)
- [Chromium：ServiceWorker 不接受自簽憑證](https://issues.chromium.org/issues/40423989)
- [mkcert](https://github.com/FiloSottile/mkcert)
