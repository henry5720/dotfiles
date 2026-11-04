# PROTOTYPE：remote GUI 的瀏覽器（a2）用哪個工具接

不會 merge。回答 [#248](https://github.com/henry5720/dotfiles/issues/248)，結論記在該 issue 的 resolution comment。

2026-11-04 的方向（issue 留言）：操作一律 `playwright-cli`，a2 只留給「一定要人自己的瀏覽器」，
走 `attach --extension` 接日常 profile；擋機房 IP 改用 a1 + 反向 SOCKS。
只測 a、b；a 失敗才測 c（BrowserMCP v2）。

- 環境：company-ec2，`@playwright/cli` 0.1.23 裝在暫存目錄（`PWCLI` 指過去）。
- 檔案：`shim.sh`（假瀏覽器執行檔）、`fwd.mjs`（port 轉發）、`a-attach-extension.sh`、`b-socks.sh`。

## 原始碼查到的（playwright-core 0.1.23 `CDPRelayServer`）

- `attach --extension=chrome`（單寫 `--extension` 會報 no target）在 **ec2 本機**起 relay：
  綁 `localhost`、**隨機 port**、路徑 `/extension/<uuid>`；Host header 只認 loopback 名稱、不看 port。
- connect 頁靠 spawn 本機 Chrome 打開；設 `PLAYWRIGHT_MCP_EXECUTABLE_PATH` 就改 spawn 那支，且不檢查本機有沒有裝 extension。
- 預設 30 秒內要連上（`PWTEST_EXTENSION_CONNECT_TIMEOUT`）；`PLAYWRIGHT_MCP_EXTENSION_TOKEN` 有設就帶進網址。
- 連線方向：extension（Windows）→ relay（ec2），所以人那邊開 **`ssh -L`**。

## Dry run（ec2 單邊，不用人）

- shim 寫出 `chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html?mcpRelayUrl=ws://127.0.0.1:9555/extension/<uuid>…`，
  `fwd.mjs` 把 9555 轉到 relay 的隨機 port，`curl 127.0.0.1:9555` 回 404（relay 只收 websocket，正常）。
- `PLAYWRIGHT_MCP_PROXY_SERVER=socks5://127.0.0.1:1` 時 `open` 回 `ERR_PROXY_CONNECTION_FAILED`：proxy 環境變數有生效。
- ec2 直連 IP `18.141.90.104`；YouTube 觀看頁 `playabilityStatus=OK`、`yt-dlp --simulate` 拿得到標題：**現在沒被擋**。

## 人要做的（Windows 桌機前）

### a：attach --extension

1. 日常 Chrome 裝 [Playwright Extension](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm)。
2. WSL 開一條（不用 `company-ec2-chrome`，那條帶 9222 的 `-R`）：
   `ssh -N -L 127.0.0.1:9555:127.0.0.1:9555 company-ec2`
3. 跟 agent 說「a 好了」；agent 在 ec2 跑 `a-attach-extension.sh`，貼出一個 `chrome-extension://…` 網址。
4. 5 分鐘內把網址貼到日常 Chrome 的網址列，照畫面選分頁／按允許。記下：跳了什麼視窗、要選什麼、有沒有看到 token。
5. agent 跑完後，看 Chrome：分頁還在嗎、有沒有「受自動測試軟體控制」橫幅。

### b：反向 SOCKS

1. WSL 開：`ssh -N -R 127.0.0.1:1080 company-ec2`
2. 跟 agent 說「b 好了」；agent 跑 `b-socks.sh`，比對直連 IP 和經 SOCKS 的 IP。

## 實測結果

（待填）
