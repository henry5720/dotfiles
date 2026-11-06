# code-server 遠端存取:五種做法

從別台裝置（pad、phone、筆電）連自己的 code-server，卡點永遠是同一個：**憑證**。
這份列出所有可行做法和各自代價，phone 和 desktop 各自選一個就好。

這份只寫 code-server 自己的事：port 與綁定、密碼、對連線的要求（secure context）、用完收掉什麼。
連線指令（ssh 轉發、`serve`）見 [remote-access〈tailnet 內〉](README.md#tailnet-內)。

> 這份是**自己**從別台裝置連 code-server。code-server 不開給訪客，見
> [remote-access〈tailnet 外〉](README.md#tailnet-外)。

---

## 先把它裝起來

chezmoi 選裝工具選單勾 `code-server`(之後要改選擇見[改設定與更新](../after-install.md)),apply 時會用官方腳本裝 binary。
設定檔不用自己弄,由 chezmoi 從 `home/dot_config/private_code-server/private_config.yaml.tmpl`
部署(權限與密碼見[密碼放哪](#密碼放哪))。

```bash
code-server     # 臨時用:前景跑,關掉終端機就停;要常駐見下面〈密碼放哪〉那節的 systemd
```

## port、綁定與驗證

| 項目 | 值 |
|---|---|
| port 與綁定 | `127.0.0.1:8080`,不對外開 |
| TLS | `cert: false` —— **假設 TLS 由外層處理**,也就是下面五種做法的前提;C、D、E 才改 |
| 驗證 | 固定密碼,見[密碼放哪](#密碼放哪) |

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
| **A** | [SSH tunnel](README.md#ssh-轉發怎麼讀)（本地轉發 8080） | 不需要，走 localhost | 否 | 每次要先開 tunnel，斷線就掛 |
| **B** | [tailscale serve](README.md#tailscale-serve)（443 → 8080） | tailscale（真憑證） | 否 | 需要該台有 tailscale CLI |
| **C** | `tailscale cert` + code-server 吃憑證 | code-server（真憑證） | 是 | 憑證要自己續期 |
| **D** | code-server 自簽憑證 | code-server（自簽） | 是 | service worker 會壞 |
| **E** | mkcert 自簽 + 手機裝 CA | code-server（自簽但被信任） | 是 | 每台 client 都要裝 CA |

B、C 的憑證都是 tailscale 幫你跟 Let's Encrypt 要的**真憑證**，網域是
`<機器名>.<你的 tailnet>.ts.net`。前提是 admin console 要開 MagicDNS 和 HTTPS Certificates
（Settings → DNS）。

---

## phone(Termux)可以用哪些

**能用：A、D、E。B、C 實質上不行。**

原因：Android 的 Tailscale app 只有 GUI，沒有 CLI，B 的 [serve](README.md#tailscale-serve) 和 C 的 `tailscale cert`
都碰不到。要有 CLI 就得在 Termux 自己裝 tailscale + tailscaled，而且非 root 沒有 TUN 權限，
得跑 `--tun=userspace-networking`——它會變成 tailnet 裡的**第二個節點**（跟 app 那個不同 IP、
不同名字），加上 Android 會殺背景 process，還要 `termux-wake-lock` 和 Termux:Boot 才活得久。

code-server 本身也**不是裝在原生 Termux**：原生 Termux 的選單一樣列 `code-server`，但標
（裝不了：termux-packages 沒有，到 proot Ubuntu 裝），勾了也只會在 apply 最後列為略過
（原因寫在 `home/.chezmoitemplates/tool-env`）。要在 phone 跑，先照
[新機器設定〈平板：原生 Termux 與 proot Ubuntu〉](../new-machine-setup.md#平板原生-termux-與-proot-ubuntu)
裝好 proot Ubuntu，在裡面勾 `code-server`。proot 跟 Termux 共用網路，proot 裡綁的
`127.0.0.1:8080`，從 Termux 的 sshd（`Host phone`，port 8022）轉出去一樣連得到。

### A|SSH tunnel（建議）

流程是 **phone 的 proot Ubuntu 跑服務，pad 或 desktop SSH 進 phone 的 Termux，再由發起端的瀏覽器開 localhost**：

```text
phone（proot Ubuntu）code-server ← SSH tunnel（Termux sshd）← 發起端瀏覽器 localhost:8080
```

```bash
# phone:先從 Termux 進 proot Ubuntu,code-server 綁 127.0.0.1,不對外開
proot-distro login ubuntu --user henry
code-server --bind-addr 127.0.0.1:8080
```

發起端用 `Host phone` 連進 phone 的 Termux，8080 就轉到發起端，瀏覽器開 `http://localhost:8080`。
`Host phone` 已經帶好這條轉發，指令與 `LocalForward` 怎麼讀見 [remote-access 的別名表](README.md#ssh-轉發怎麼讀)。

---

## henry-desktop 可以用哪些

**全部都能用。B 最省事。**

作者這台 WSL 曾因 `.wslconfig` 設了 `networkingMode=mirrored`（[`home/dot_wslconfig`](../../home/dot_wslconfig)），
eth0 上直接掛著 tailnet IP `100.119.136.27`，WSL 裡的服務綁 `127.0.0.1`，
Windows 側也看得到，中間不用接任何東西。

這個 IP、介面與 DNS 行為只是作者機器的觀察值，不保證你現在或其他主機相同；先用
`tailscale status`、`ip addr` 查自己的現況（serve 的現況怎麼查見 [remote-access](README.md#tailscale-serve)）。

作者這台的 tailscale CLI 在 Windows；WSL 內曾是 `Logged out`。這不是通用前提，請先查
`tailscale status`，確認你要用的節點及登入狀態。

### B|讓 tailscale 終結 TLS（建議）

code-server 完全不用改設定，tailscale 在前面當反向代理並終結 TLS。照
[remote-access〈tailscale serve〉](README.md#tailscale-serve) 把 443 接到 8080，之後任何裝置的瀏覽器開
`https://henry-desktop.<你的 tailnet>.ts.net`（不用打 port）。code-server 這邊要注意的：

- **listener 走 443，不能也用 8080**：mirrored networking 下 Windows 和 WSL 共用 port 空間，
  serve 佔了 8080，WSL 的 code-server 就起不來。
- **serve 設在 Windows 節點**，code-server 在 WSL 裡維持 `127.0.0.1:8080`、`cert: false`。
  怎麼判斷設在哪個節點、從 WSL 打那個網址會 timeout 是正常的，見 remote-access 同一節。
- 本機確認 code-server 活著：`curl -I http://127.0.0.1:8080`，回 302 就是活的。

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

臨時用、不想動任何設定的時候，照 [remote-access〈ssh 轉發怎麼讀〉](README.md#ssh-轉發怎麼讀) 把 henry-desktop 的 8080 拉到你這台的 localhost:8080。

henry-laptop 跟 henry-desktop 一樣走 B，serve 設在 Windows 那個節點；其他 Windows/WSL 主機先照
[remote-access〈tailscale serve〉](README.md#tailscale-serve) 查現況再套用，不要套用作者的主機名與 IP。

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

## 收掉什麼

| 怎麼跑的 | 收掉 |
|---|---|
| 前景跑 `code-server` | Ctrl-C;確認 `ss -ltnp \| grep 8080` 沒有輸出 |
| systemd 常駐 | `systemctl --user disable --now code-server` |
| 走 A | 關掉那條 ssh |
| 走 B | 撤掉 serve,指令見 [remote-access〈tailscale serve〉](README.md#tailscale-serve) |
| 走 C、D、E | 憑證檔不在 repo 裡,不用了就刪;`cert` / `cert-key` 改回來再 `chezmoi apply` |

## 一句話結論

- **phone** → A（[`Host phone`](README.md#ssh-轉發怎麼讀)，config 已備好）
- **henry-desktop** → B（[tailscale serve](README.md#tailscale-serve)，設一次就好）
- **henry-laptop** → B（同上,serve 設在 **Windows** 那個節點;WSL 裡打那個網址會 timeout 是正常的）

---

## 參考

- [code-server：TLS 設定](https://coder.com/docs/code-server/guide)（`--cert` / `--cert-key`、自簽憑證路徑）
- [code-server #6809：自簽憑證下 plugin 失效](https://github.com/coder/code-server/issues/6809)
- [code-server #7206：insecure context 的症狀](https://github.com/coder/code-server/discussions/7206)
- [Chromium：ServiceWorker 不接受自簽憑證](https://issues.chromium.org/issues/40423989)
- [mkcert](https://github.com/FiloSottile/mkcert)
