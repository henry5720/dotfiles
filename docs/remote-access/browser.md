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
| [插件](#插件獨立-profile日常-profile-都能裝) | 個人電腦（獨立 profile 或日常 profile） | 一定要日常 profile 裡的東西（passkey、硬體金鑰、裝置 SSO），或你不在 tailnet | 插件 relay 9555：`personal-chrome-attach`（tailnet 外加 `--tunnel`） | 就是你眼前的視窗 | 多個（收在一個分頁群組） |

- **獨立 profile 和日常 profile 是兩支 Chrome。** Chrome 136 起，日常 profile 不能開 debug port，
  一定要另一個 `--user-data-dir`（[Chrome 官方說明](https://developer.chrome.com/blog/remote-debugging-port)）。
  日常 profile 只能靠插件接。插件裝在獨立 profile 也行：你不在 tailnet、開不了 9222 的 ssh 轉發時，就走插件。
- **9222 是通用的 CDP 入口**：`playwright-cli attach --cdp` 操作、chrome-devtools-mcp 查原因，接的是同一個 port。
  chrome-devtools-mcp 的設定寫死 `127.0.0.1:9222`，所以當下佔著 9222 的那支 Chrome 就是它查的那支。

## port 與驗證

| port | 是什麼 | 誰定的 | 驗證 |
|---|---|---|---|
| 9222 | Chrome 的 CDP（headless 或獨立 profile） | 慣例（Chrome 沒有預設，要自己給 `--remote-debugging-port`）；我們固定用它，因為 `mcp.yaml` 寫死 | **沒有**：連得到就能操作整支 Chrome，包括它的登入 |
| 9377 | `playwright-cli show`（看 agent 的畫面、接手） | 我們選的（`show --port` 沒有預設，`0` 是隨機） | **沒有**：連得到就能操作 |
| 9555 | 插件的 relay | 我們選的（relay 本身每次隨機；tailnet 內 `personal-chrome-attach` 轉到這台的 9555，ssh 指令才能固定；tailnet 外是你那台的 `cloudflared access tcp` 聽 9555） | connect 網址裡的隨機路徑，拿到完整網址就能接；你在插件畫面按允許（tailnet 內可設插件的 token 省掉這步） |
| 1080 | 反向 SOCKS（借你的網路） | SOCKS 的慣例 port | **沒有** |

除了 9222，其他都能換：連線兩邊的 port 和服務起的 port 一起改就好。
同一台的同一個 port 同時只能一個：個人電腦把 9222 轉到已配置主機時，那台就不能再開 headless 的 9222，反過來也一樣。

## 能怎麼連

服務開好之後，連線方式照[連線](README.md#判準)挑。9222、9377、1080 只能走前兩種；9555 多一條 tailnet 外的一次性 tunnel：

| 連線 | 9222／9377／1080 | 9555（插件） |
|---|---|---|
| 同一台：直接連 `127.0.0.1` | ✓ | ✓ |
| tailnet 內：[ssh -L／-R](README.md#ssh-轉發怎麼讀) | ✓ | ✓ |
| tailnet 內：`tailscale serve` | ✗ tailnet 裡每台裝置都連得到，等於把 Chrome 交給整個 tailnet | ✗ 同左 |
| tailnet 外：一次性 tcp tunnel | ✗ 見下 | ✓（[`personal-chrome-attach --tunnel`](#tailnet-外一次性-tunnel)） |
| tailnet 外：Funnel、http quick tunnel | ✗ 見下 | ✗ |

9555 能開出去，因為 **connect 網址就是鑰匙，用完就收掉**：

- relay 只認 connect 網址裡的隨機路徑（`crypto.randomUUID()`）。只拿到 trycloudflare 網址的人猜不到它，連上也只回 400。
- 一次性：detach、逾時、被中斷時 `personal-chrome-attach` 收掉 tunnel，那條網址和路徑跟著失效，下次是新的。
- 每次接都要你在插件畫面選分頁、按允許。
- 反過來，網址和路徑都拿到的人能搶在 agent 之前接上你的 Chrome。所以 connect 網址只交給本人，不貼到別人看得到的地方。

上面是 [agent-company#43](https://github.com/henry5720/agent-company/issues/43) 的原型在 2026-11-06 測的結果（company-ec2，playwright-cli 0.1.23，cloudflared 2026.10.7）。

9222、9377、1080 不開公網的原因：

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

## 插件：獨立 profile、日常 profile 都能裝

agent 經 [Playwright Extension](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm)
接你那支 Chrome。接上後 agent 能開多個分頁：受控的分頁收在同一個 Chrome 分頁群組，`tab-new` 開的會被拉進群組，
你把分頁拖進、拖出群組也會接上、放開（依據見[多分頁](#多分頁)）。

插件裝在哪個 profile 由你決定：

- **獨立 profile**：agent 碰不到你平常的登入。你在 tailnet 內的話，獨立 profile 直接走[9222](#獨立-profile讓-agent-控你看得到的-chrome)比較省事；不在 tailnet、開不了 ssh 轉發，就在獨立 profile 裝插件。
- **日常 profile**：一定要日常 profile 裡的東西（passkey、硬體金鑰、裝置 SSO）時。接上期間 agent 用的是你的登入，看著它做。

共通步驟：

1. **第一次**：在要給 agent 用的那個 profile 裝插件。
2. **連線**：看你在不在 tailnet，照下面[tailnet 內](#tailnet-內ssh-轉發)或[tailnet 外](#tailnet-外一次性-tunnel)其中一段做。
3. **怎麼確認**：`personal-chrome-attach` 印「已接上,session:<session>」，agent 跑 `playwright-cli -s=<session> tab-list` 列得出你的分頁。
   之後用 `playwright-cli -s=<session> <指令>` 操作，開新分頁做事用 `tab-new <網址>`，不蓋掉你正在看的那頁。
4. **收**：`playwright-cli -s=<session> detach`。Chrome 和分頁留著。

### tailnet 內：ssh 轉發

1. **連線**：已配置主機的 9555 → 個人電腦的 9555（`-L`，[怎麼打](README.md#ssh-轉發怎麼讀)）。
2. 已配置主機起 relay：

   ```bash
   # 起插件要連的 relay，固定聽 9555，等你的 Chrome 連進來（預設等 300 秒）
   personal-chrome-attach -s=<session>
   ```

   這支是 agent-config 的 browser-access skill 附的：relay 本來每次隨機 port，它固定到 9555；有 token 時不把網址印出來。
3. 在**新分頁**（agent 會直接改這個分頁）：
   - 有設 token：開 `http://127.0.0.1:9555/connect`，按「複製」，貼進同一個分頁的網址列。這個網址每次一樣，可以加書籤。
   - 沒設 token：貼 `personal-chrome-attach` 印出的 `chrome-extension://…` 網址，再在插件畫面選這個分頁、按允許。
4. 收：detach 之後關掉 ssh。

- token：插件狀態頁上的 token 設成**已配置主機**的環境變數 `PLAYWRIGHT_MCP_EXTENSION_TOKEN`，之後貼網址就接上、不用選分頁。token 不進 repo、不貼進對話。
- 逾時：`personal-chrome-attach` 預設等 300 秒，沒人連就自己收掉，重跑會是新的網址。

### tailnet 外：一次性 tunnel

你不在 tailnet、沒有 ssh 入口，例如 company agent 在它的 container 裡要接你的 Chrome。
插件只肯連 `127.0.0.1` 上的 relay，所以你那台要有一個聽 `127.0.0.1:9555` 的轉發：`cloudflared access tcp`，
經一條 Cloudflare tcp quick tunnel 接到 agent 那台的 relay。

```text
你的 Chrome ─插件─▶ 127.0.0.1:9555 ─cloudflared access tcp─▶ <x>.trycloudflare.com ─tcp quick tunnel─▶ agent 那台的 relay ◀─ playwright-cli
```

**已配置主機（agent）**：

```bash
# 起 relay，再開一條 cloudflared tcp quick tunnel 指向它；印出你要做的三步，停到 session 結束
#   --timeout=<秒>  等你接上的秒數（預設 300）
personal-chrome-attach --tunnel -s=<session>
```

- 要 `playwright-cli`（≥ 0.1.23）和 `cloudflared`。沒有 cloudflared 時印下載頁網址、exit 1。
- 不帶 token：tunnel 模式不讀 `PLAYWRIGHT_MCP_EXTENSION_TOKEN`，每次你在插件畫面選分頁、按允許。
- 不在 agent 這台聽 9555，所以同一台可以同時開多條，session 名要不同。

它印出的樣子（2026-11-06 在 company-ec2 實跑 `personal-chrome-attach --tunnel -s=tunneltest --timeout=600`，
cloudflared 2026.10.7、playwright-cli 0.1.23；hostname 和 UUID 每次不同，這條 tunnel 已收掉，UUID 改成 `<uuid>`）：

```text
tunnel 開好了。connect 網址就是鑰匙,只交給使用者本人。把下面三步交給他,請他在 600 秒內做完:
  1. 安裝 cloudflared(第一次才要),依 OS 從官方下載頁選:https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/
  2. 開一個新的終端機貼這行,開著別關:
     cloudflared access tcp --hostname lamps-meetings-entity-possession.trycloudflare.com --url 127.0.0.1:9555
  3. 在裝了 Playwright Extension 的 Chrome 開新分頁,網址列貼上這個 connect 網址,在插件畫面選分頁、按允許:
     chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html?mcpRelayUrl=ws%3A%2F%2F127.0.0.1%3A9555%2Fextension%2F<uuid>&client=%7B%22name%22%3A%22Claude+Code%22%7D&protocolVersion=2
等使用者接上(最多 600 秒)…
已接上,session:tunneltest。用 playwright-cli -s=tunneltest <指令> 操作;用完 playwright-cli -s=tunneltest detach(Chrome 和分頁留著)。
session tunneltest 結束了,收掉 tunnel。
cloudflared 剩 0 個(要 0)。
```

（「等使用者接上」和「已接上」之間還會夾 playwright-cli attach 自己的輸出，這裡省略。）

agent 把「tunnel 開好了」到「等使用者接上」那段原樣交給你；印到「等使用者接上」就可以交了。

**你（個人電腦）照那三步做**：

1. 裝 cloudflared（第一次才要）：依你的 OS 從[官方下載頁](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/)選。
   Windows 也可以 `winget install --id Cloudflare.cloudflared -e`，裝完當下的終端機找不到它時見 [remote-access〈Cloudflare quick tunnel〉](README.md#cloudflare-quick-tunnel)。
2. 開一個新的終端機，貼 agent 給的那行（hostname 已填好），**開著別關**：

   ```bash
   # 在你這台聽 127.0.0.1:9555，轉到 agent 那台的 relay
   cloudflared access tcp --hostname <x>.trycloudflare.com --url 127.0.0.1:9555
   ```

3. 在裝了插件的 Chrome 開**新分頁**，網址列貼 connect 網址，在插件畫面選分頁、按允許。

- **connect 網址就是鑰匙**：拿到它和 hostname 的人能搶在 agent 前面接上你的 Chrome（見[能怎麼連](#能怎麼連)）。只給本人，不貼到別人看得到的地方。
- 收：agent detach 後 `personal-chrome-attach` 收掉 tunnel，印「cloudflared 剩 0 個(要 0)。」；你那台的 `cloudflared access tcp` 按 Ctrl-C。
  腳本只檢查 cloudflared 行程剩 0 個；要確認公網也斷了，照 [remote-access〈共通規則〉](README.md#共通規則)打那個網址，回 `530` 才算。
- 逾時、attach 失敗（例如你按了拒絕）、cloudflared 起不來或中途結束：都會收掉 cloudflared、exit 1；被中斷（Ctrl-C、SIGTERM）exit 130。網址每次不同，重跑就是新的三步。

### 多分頁

接上後的分頁收在同一個 Chrome 分頁群組：relay 自己接上的分頁（一開始那個、popup、`tab-new` 開的）會被拉進群組，
你把分頁拖進、拖出群組也會接上、放開。依據是 Playwright Extension 的原始碼（microsoft/playwright main，2026-11-05 的 commit）：
[`connectedTabGroup.ts`](https://github.com/microsoft/playwright/blob/58d69dcc392af3a6994eab0323dc2e883f05f396/packages/extension/src/connectedTabGroup.ts#L63-L70)、
relay 轉給插件的指令包含 `chrome.tabs.create`（[`relayConnection.ts`](https://github.com/microsoft/playwright/blob/58d69dcc392af3a6994eab0323dc2e883f05f396/packages/extension/src/relayConnection.ts#L41-L47)）。

2026-11-06 實機驗過（Chrome Web Store 版插件、playwright-cli 0.1.23，經上面的 tcp tunnel 從 company-ec2 接
henry-desktop 的獨立 profile）：

| 做了什麼 | 結果 |
|---|---|
| 接上後 `tab-new` 兩次 | `tab-list` 列出三個分頁（connect 頁加兩個新分頁）；你那邊看到三個都在同一個分頁群組 |
| `tab-select 1` 後點連結，再 `tab-select 2`、切回 1 | 每次 `eval` 讀到的都是選中那頁；分頁 1 的點擊只換了分頁 1 的頁面 |
| 你把一個分頁拖出群組 | 它從 `tab-list` 消失 |
| 再拖回群組 | 它回到 `tab-list`，`tab-select` 過去讀得到標題 |

## 連不上時

轉發本身的問題（`Address already in use`、`channel … open failed`）見 [remote-access〈ssh 轉發連不上〉](README.md#ssh-轉發連不上)。

| 現象 | 原因 | 處理 |
|---|---|---|
| 9222 一直不通，Chrome 卻開著 | 同 profile 的 Chrome 早就開著、沒帶 debug port，新參數被吞掉 | 關掉那個 Chrome 視窗，重開 |
| `remote port forwarding failed`（9222 或 1080） | 已配置主機的 port 被佔 | `ss -ltnp \| grep <port>` 看是誰；另一台的 ssh 或 headless 先收掉 |
| chrome-devtools-mcp 接到的不是你要的那支 | 9222 同時只有一支 Chrome | `curl 127.0.0.1:9222/json/version` 看 `User-Agent` |
| `personal-chrome-attach` 說「等了 N 秒沒人連進來」 | `--timeout` 秒內（預設 300）沒人連進來 | 重跑，用新的網址 |
| `找不到 cloudflared:--tunnel 要它` | agent 那台沒有 cloudflared | 照它印的官方下載頁裝 |
| `cloudflared 沒開出 trycloudflare.com 網址` | quick tunnel 沒開成，常見是被限流回 `429`；它會印 cloudflared 最後幾行 | 看那幾行，過一陣子重跑 |
| `cloudflared 自己結束了,tunnel 斷了` | 接上之後 agent 那台的 cloudflared 掉了 | 重跑，用新的三步 |
| 經公開網址連 9222 回 `500 Host header is specified…` | Chrome 只接受 IP 或 `localhost` 的 `Host` | 不開公網，改走 ssh，見[能怎麼連](#能怎麼連) |
