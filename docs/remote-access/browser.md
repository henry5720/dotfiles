# 瀏覽器

服務卡：agent 要用瀏覽器、你要看 agent 的瀏覽器、或讓 agent 控你的瀏覽器。人和 agent 都照這份打指令。
這份只講**服務**（怎麼開、怎麼確認、怎麼收）；怎麼連過去是[連線](README.md)那份的事，
每段的「連線」那行告訴你要哪個 port、往哪個方向，完整 ssh 指令在 [ssh 轉發怎麼讀](README.md#ssh-轉發怎麼讀)，
常用的幾條也整行列在[速查](../configured-host.md#速查)。
為什麼工具這樣分見 [ADR 0001](../adr/0001-browser-tools-drive-vs-debug.md)。

## 先挑哪支 Chrome

| Chrome | 在哪一台 | 什麼時候用 | agent 怎麼接 | 人怎麼看 | 分頁 |
|---|---|---|---|---|---|
| [headless](#headlessagent-自己的瀏覽器) | 已配置主機 | 預設：agent 自己操作、驗收、查原因 | `playwright-cli open`；查原因時開在 9222 給 chrome-devtools-mcp | `playwright-cli show`（9377） | 多個 |
| [獨立 profile](#獨立-profile讓-agent-控你看得到的-chrome) | 個人電腦（任一台都行） | 你坐在前面，要 agent 在你看得到的 Chrome 做事 | CDP 9222：`playwright-cli attach --cdp`、chrome-devtools-mcp | 就是你眼前的視窗 | 多個 |
| [日常 profile](#日常-profile一定要你平常的-chrome) | 個人電腦 | 一定要日常 profile 裡的東西：passkey、硬體金鑰、裝置 SSO | 插件 relay 9555：`personal-chrome-attach` | 就是你眼前的視窗 | 一個 |

- **獨立 profile 和日常 profile 是兩支 Chrome。** Chrome 136 起，日常 profile 不能開 debug port，
  一定要另一個 `--user-data-dir`（[Chrome 官方說明](https://developer.chrome.com/blog/remote-debugging-port)）。
  日常 profile 只能靠插件從裡面交出一個分頁。
- **9222 是通用的 CDP 入口**：`playwright-cli attach --cdp` 操作、chrome-devtools-mcp 查原因，接的是同一個 port。
  chrome-devtools-mcp 的設定寫死 `127.0.0.1:9222`，所以當下佔著 9222 的那支 Chrome 就是它查的那支。

## port 與驗證

| port | 是什麼 | 誰定的 | 驗證 |
|---|---|---|---|
| 9222 | Chrome 的 CDP（headless 或獨立 profile） | 慣例（Chrome 沒有預設，要自己給 `--remote-debugging-port`）；我們固定用它，因為 `mcp.yaml` 寫死 | **沒有**：連得到就能操作整支 Chrome，包括它的登入 |
| 9377 | `playwright-cli show`（看 agent 的畫面、接手） | 我們選的（`show --port` 沒有預設，`0` 是隨機） | **沒有**：連得到就能操作 |
| 9555 | 插件的 relay | 我們選的（relay 本身每次隨機，`personal-chrome-attach` 轉到這裡，ssh 指令才能固定） | 插件的 token（選用） |
| 1080 | 反向 SOCKS（借你的網路） | SOCKS 的慣例 port | **沒有** |

除了 9222，其他都能換：連線兩邊的 port 和服務起的 port 一起改就好。
同一台的同一個 port 同時只能一個：個人電腦把 9222 轉到已配置主機時，那台就不能再開 headless 的 9222，反過來也一樣。

## 能怎麼連

服務開好之後，連線方式照[連線](README.md#判準)挑；瀏覽器能挑的只有前兩種：

| 連線 | 9222／9377／1080 | 9555（插件） |
|---|---|---|
| 同一台：直接連 `127.0.0.1` | ✓ | ✓ |
| tailnet 內：[ssh -L／-R](README.md#ssh-轉發怎麼讀) | ✓ | ✓ |
| tailnet 內：`tailscale serve` | ✗ tailnet 裡每台裝置都連得到，等於把 Chrome 交給整個 tailnet | ✗ 同左 |
| tailnet 外：Funnel、quick tunnel | ✗ 見下 | ✗ 同左 |

公開網址不行的原因：

- **這幾個 port 都沒有驗證。** 拿到網址的人等於坐在那支 Chrome 前面，裡面所有網站的登入、cookie 都能讀能用。
  [expose-port](README.md#tailnet-外) 只開「app 自己有驗證」的服務，瀏覽器不符合。
- **CDP 直接接不上。** Chrome 只接受 `Host` 是 IP 或 `localhost` 的請求，Funnel、quick tunnel 轉進來的 `Host` 是公開網址，
  會回 `500 Host header is specified and is not an IP address or localhost.`（2026-11-06 在 company-ec2 實測 Chrome 154）。

要讓 tailnet 外的人看你的瀏覽器畫面，用會議軟體分享螢幕。

## headless：agent 自己的瀏覽器

**操作、驗收**（不佔 9222）：

```bash
# 開一個有名字的 session（-s），之後同一個名字的指令都操作這支瀏覽器
playwright-cli -s=<session> open <網址>
# 用完收掉，瀏覽器跟著關
playwright-cli -s=<session> close
```

**查原因**（chrome-devtools-mcp 要 9222 上有 Chrome）：

```bash
# 先看 9222 有沒有 Chrome 在聽；有回應就直接用那支，不要再開
curl -s --max-time 3 127.0.0.1:9222/json/version

# 開一支沒有畫面的 Chrome：
#   --remote-debugging-address/port  CDP 只聽本機的 9222
#   --user-data-dir                  獨立的資料夾，登入留在這裡
#   --no-first-run ...               跳過第一次啟動的歡迎頁、預設瀏覽器詢問
#   最後的 &                         丟到背景，log 寫到 /tmp
google-chrome --headless --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 \
  --user-data-dir="$HOME/.local/state/chrome-mcp-profile" --no-first-run --no-default-browser-check \
  --window-size=1280,800 >/tmp/chrome-headless.log 2>&1 &
```

- 怎麼確認：`curl -s 127.0.0.1:9222/json/version` 回的 `User-Agent` 有 `HeadlessChrome`。Claude Code 再 `/mcp` 重連。
- 收：`kill %1`（或那個 PID）；`curl` 連不上 9222 就是收乾淨了。查完一定收：留著會擋住別人要用的 9222。
- 坑：
  - 回的 `User-Agent` 不是 `HeadlessChrome`、而且 `/json/version` 有 `"File-Path-Style": "windows"`：那是使用者轉過來的獨立 profile，chrome-devtools-mcp 直接接它就好，不用開 headless。
  - 沒有 `google-chrome`：dotfiles 的選裝工具勾 `headless-chrome`（WSL 沒有這一項）。
  - 不用加 `--no-sandbox`：官方 `.deb` 帶 apparmor 設定，Ubuntu 24.04 開得起來。stderr 的 dbus 錯誤是沒有桌面的正常雜訊。

**你要看畫面、接手、替它登入**：

```bash
# 已配置主機：開一個網頁版的控制台，列出所有 session 的即時畫面，聽 9377
playwright-cli -s=<session> show --port 9377
```

- 連線：已配置主機的 9377 → 個人電腦的 9377（`-L`，[怎麼打](README.md#ssh-轉發怎麼讀)）。
- 個人電腦的瀏覽器開 `http://127.0.0.1:9377`，點 session 放大，點進畫面就能操作，按 Escape 交還。
  在這裡登入，agent 接著用同一個 session 就帶著登入。
- 收：關掉 ssh、收掉 `show`。

**網站擋機房 IP**（瀏覽器不搬，流量改從你的個人電腦出去）：

```bash
# 已配置主機：開瀏覽器時叫它走 1080 這個 SOCKS proxy（也就是你的個人電腦）
PLAYWRIGHT_MCP_PROXY_SERVER=socks5://127.0.0.1:1080 playwright-cli -s=<session> open <網址>
```

- 連線：個人電腦借網路給已配置主機的 1080（`-R` 只寫一個 port = 反向 SOCKS，[怎麼打](README.md#ssh-轉發怎麼讀)）。要先開好連線再開瀏覽器。
- 怎麼確認：在這個 session 開 `https://api64.ipify.org`，印出的是你個人電腦的對外 IP（你有 IPv6 時常是 IPv6）。
- 坑：proxy 只在瀏覽器啟動時讀，session 已經開著要先 `close`。只在被擋時開：開著時 agent 走 proxy 的流量都經過你的網路。

## 獨立 profile：讓 agent 控你看得到的 Chrome

你坐在個人電腦前，要 agent 在你看得到的瀏覽器做事。登入留在這個 profile，下次還在。

**個人電腦開 Chrome**：Windows 直接在桌面開 PowerShell 打（不是 WSL，也不是 ssh 進去的 session）。

```powershell
# 開一支專給 agent 用的 Chrome（會跳出新視窗，第一次是空的 profile）：
#   --remote-debugging-port=9222   讓 agent 從 9222 接進來操作
#   --user-data-dir=...chrome-agent 獨立的資料夾，不碰你平常那支 Chrome；登入會留在這裡
#   --no-first-run ...             跳過歡迎頁、預設瀏覽器詢問
& "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 `
  --user-data-dir="$env:LOCALAPPDATA\chrome-agent" --no-first-run --no-default-browser-check
```

```bash
# 個人電腦是 Linux／macOS：參數一樣，chrome 換成 google-chrome 或 Chrome.app 的路徑
google-chrome --remote-debugging-port=9222 --user-data-dir="$HOME/.local/state/chrome-agent" --no-first-run &
```

不想每次打：Chrome 捷徑的「目標」後面加 `--remote-debugging-port=9222 --user-data-dir="%LOCALAPPDATA%\chrome-agent"`，之後雙擊就開。

**連線**：個人電腦的 9222 → 已配置主機的 9222（`-R`，[怎麼打](README.md#ssh-轉發怎麼讀)）。只能走 ssh，見[能怎麼連](#能怎麼連)。

**已配置主機（agent）接上**：

```bash
# 確認接到的是你的 Chrome：有 webSocketDebuggerUrl，而且 User-Agent 不是 HeadlessChrome
curl -s --max-time 3 127.0.0.1:9222/json/version
# 接上那支 Chrome，之後用 -s=<session> 操作它
playwright-cli -s=<session> attach --cdp=http://127.0.0.1:9222
# 開新分頁做事，別 goto 蓋掉你正在看的那頁
playwright-cli -s=<session> tab-new <網址>
# 列出所有分頁（包括你自己開的）
playwright-cli -s=<session> tab-list
```

- 怎麼確認：`tab-list` 列得出你開著的分頁。2026-11-05 在 henry-laptop 實測：`tab-new` 兩次後列出三個分頁。
- 收：agent `playwright-cli -s=<session> detach`；你關掉 ssh。Chrome 和登入留著，下次照上面再開就沿用。
- 坑：
  - **這個 profile 的 Chrome 已經開著時，再帶 `--remote-debugging-port` 啟動會被轉給舊的那支、新參數全部被忽略、也不報錯**：
    9222 就是不通。先 `curl 127.0.0.1:9222/json/version`（Windows：`curl.exe`）看是不是已經在了；不是就把那個視窗關掉重開。
  - ssh 印 `remote port forwarding failed`：已配置主機的 9222 被佔著（另一台電腦還開著，或 headless 在跑）。
  - 從 ssh session 啟動的 Chrome，session 一結束就被 Windows 一起收掉：Chrome 要從桌面的終端機開。
  - Windows 要有 `company-ec2` 這個 ssh Host：chezmoi 不部署 ssh config 到 Windows，自己在 `~\.ssh\config` 加，先 `ssh company-ec2 hostname` 確認。

## 日常 profile：一定要你平常的 Chrome

只在 passkey、硬體金鑰、裝置 SSO 這種獨立 profile 也登不進去的網站用。只交出一個分頁。

1. **第一次**：日常 Chrome 裝 [Playwright Extension](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm)。
2. **連線**：已配置主機的 9555 → 個人電腦的 9555（`-L`，[怎麼打](README.md#ssh-轉發怎麼讀)）。
3. 已配置主機起 relay：

   ```bash
   # 起插件要連的 relay，固定聽 9555，等你的 Chrome 連進來（預設等 5 分鐘）
   personal-chrome-attach -s=<session>
   ```

   這支是 agent-config 的 browser-access skill 附的：relay 本來每次隨機 port，它固定到 9555；有 token 時不把網址印出來。
4. 在**新分頁**（agent 會直接改這個分頁）：
   - 有設 token：開 `http://127.0.0.1:9555/connect`，按「複製」，貼進同一個分頁的網址列。這個網址每次一樣，可以加書籤。
   - 沒設 token：貼 `personal-chrome-attach` 印出的 `chrome-extension://…` 網址，再在插件畫面選這個分頁、按允許。
5. 怎麼確認：`personal-chrome-attach` 印「已接上,session:<session>」。之後 `playwright-cli -s=<session> <指令>`。
6. 收：`playwright-cli -s=<session> detach`，再關掉 ssh。Chrome 和分頁留著。

- token：插件狀態頁上的 token 設成**已配置主機**的環境變數 `PLAYWRIGHT_MCP_EXTENSION_TOKEN`，之後貼網址就接上、不用選分頁。token 不進 repo、不貼進對話。
- 逾時：`personal-chrome-attach` 預設等 5 分鐘，沒人連就自己收掉，重跑會是新的網址。

## 連不上時

轉發本身的問題（`Address already in use`、`channel … open failed`）見 [remote-access〈ssh 轉發連不上〉](README.md#ssh-轉發連不上)。

| 現象 | 原因 | 處理 |
|---|---|---|
| 9222 一直不通，Chrome 卻開著 | 同 profile 的 Chrome 早就開著、沒帶 debug port，新參數被吞掉 | 關掉那個 Chrome 視窗，重開 |
| `remote port forwarding failed`（9222 或 1080） | 已配置主機的 port 被佔 | `ss -ltnp \| grep <port>` 看是誰；另一台的 ssh 或 headless 先收掉 |
| chrome-devtools-mcp 接到的不是你要的那支 | 9222 同時只有一支 Chrome | `curl 127.0.0.1:9222/json/version` 看 `User-Agent` |
| `personal-chrome-attach` 說逾時 | 5 分鐘內沒人連進來 | 重跑，用新的網址 |
| 經公開網址連 9222 回 `500 Host header is specified…` | Chrome 只接受 IP 或 `localhost` 的 `Host` | 不開公網，改走 ssh，見[能怎麼連](#能怎麼連) |
