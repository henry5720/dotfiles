# Ubuntu 24.04 EC2：Chrome for Testing／headless 研究

> **研究快照，不是現況。** 後來決定 EC2 不裝 Chrome，改用 SSH `-R` 連 Windows 的 Chrome，做法見 [chrome-devtools-mcp.md](chrome-devtools-mcp.md)。

本文件針對 issue「研究 EC2 headless Chrome 的安裝與版本策略」。查詢時間為 2026-09-21；目前執行環境不是目標 Ubuntu 24.04 EC2，因此沒有把本機結果當成目標驗證。

## 已由官方來源確認的事實

- **Chrome for Testing（CfT）是合適的自動化來源。** Chrome 官方說明它是不自動更新、與 Chrome 發行流程同步、每個版本可重現的測試專用 binary：[Chrome for Testing](https://developer.chrome.com/blog/chrome-for-testing)。版本與下載 URL 應從 [known-good-versions-with-downloads.json](https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json) 或 [last-known-good-versions-with-downloads.json](https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json) 取得，不要依賴 `latest` URL。
- **Linux 架構。** CfT 的官方 README 列出 `linux64`，並列出 `linux-arm64` 自 Chrome `153.0.8001.0` 起支援：[CfT README（supported platforms）](https://github.com/GoogleChromeLabs/chrome-for-testing#supported-platforms)。2026-09-18 的 last-known-good feed 中，Stable `153.0.8010.52` 同時提供 [linux64](https://storage.googleapis.com/chrome-for-testing-public/153.0.8010.52/linux64/chrome-linux64.zip) 與 [linux-arm64](https://storage.googleapis.com/chrome-for-testing-public/153.0.8010.52/linux-arm64/chrome-linux-arm64.zip)（兩者 HTTP 200）。因此先以 `uname -m` 選資產：`x86_64→linux64`、`aarch64→linux-arm64`；若固定低於 153，ARM 資產可能不存在。
- **Puppeteer/MCP 也辨識 ARM。** Puppeteer 25.10.0 的 `detectBrowserPlatform()` 將 Linux `arm64` 映射為 `linux-arm64`，其 Chrome URL resolver 以 `153.0.8001.0` 為切換門檻：[detectPlatform.ts](https://github.com/puppeteer/puppeteer/blob/puppeteer-v25.10.0/packages/browsers/src/detectPlatform.ts)、[chrome.ts](https://github.com/puppeteer/puppeteer/blob/puppeteer-v25.10.0/packages/browsers/src/browser-data/chrome.ts)。這是下載器行為；仍須在 EC2 目標 AMI 上驗證所需共享函式庫。
- **Chrome DevTools MCP 版本與需求。** `chrome-devtools-mcp` v1.9.0（[npm metadata](https://registry.npmjs.org/chrome-devtools-mcp/1.9.0)，SHA-512 integrity `sha512-RnzXoJiUQ44hpOihWk90uOhLD/CnwDkDy0ldHMZONJ2nYQ+dWN1fq1luHHqyd+7FuYnyIlCY6uTThbN5ut9kSQ==`）要求 Node `^20.19.0 || ^22.12.0 || >=23`，並依賴 Puppeteer 25.10.0：[package.json](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/chrome-devtools-mcp-v1.9.0/package.json)。官方 MCP README 要求 Node LTS 與目前 Stable Chrome，並說明 `@latest` 會隨版本更新：[README](https://github.com/ChromeDevTools/chrome-devtools-mcp#readme)。
- **MCP 啟動選項。** 官方設定文件定義 `--headless`、`--executable-path`、`--isolated`、`--user-data-dir`、`--browser-url`、`--chrome-arg`、`--no-usage-statistics`、`--no-performance-crux` 等：[configuration.md](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/configuration.md)。`--browser-url` 是連到已啟動的 Chrome；若由 MCP 啟動，應指定 CfT 的 `--executable-path`。
- **Sandbox 不應以 `--no-sandbox` 當預設。** Puppeteer troubleshooting 指出 Chrome 需要可用 sandbox；`--no-sandbox` 會停用關鍵防護且強烈不建議：[Setting Up Chrome Linux Sandbox](https://pptr.dev/troubleshooting#setting-up-chrome-linux-sandbox)。Ubuntu 23.10+ 的 AppArmor user-namespace 限制可能使下載的 CfT 出現 `No usable sandbox!`；Chromium 官方建議建立針對該 binary 的 AppArmor 例外，或使用受信任的 setuid sandbox，並警告全域停用限制會削弱安全性：[AppArmor user namespace restrictions](https://chromium.googlesource.com/chromium/src/+/main/docs/security/apparmor-userns-restrictions.md)。MCP 官方 troubleshooting 另指出 root 執行時 Chrome 通常立即退出，應用非 root 使用者：[MCP troubleshooting](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/troubleshooting.md#running-as-root)。
- **系統依賴。** Puppeteer 列出的 Debian/Ubuntu 常見套件包含 `ca-certificates`、`fonts-liberation`、`libasound2`、`libatk*`、`libc6`、`libcairo2`、`libcups2`、`libdbus-1-3`、`libgbm1`、`libnss3`、`libpango*`、`libx11*` 等；實機以 `ldd <chrome>/chrome | grep not` 找出缺件，再依 Chromium 的 [dist_package_versions.json](https://source.chromium.org/chromium/chromium/src/+/main:chrome/installer/linux/debian/dist_package_versions.json) 補齊。不要把這份清單當成跨 AMI 的完整安裝腳本。

## 建議的可審核基線（尚待人決定是否採用）

1. 以非 root 的專用服務帳號執行；保留 Chrome sandbox，先處理 Ubuntu AppArmor 例外。只有隔離環境的臨時診斷才考慮 `--no-sandbox`，並標記為例外。
2. 在部署輸入中固定完整 CfT 版本與 SHA256（從該版本 JSON 的下載資訊／物件 metadata 取得），下載 `linux64` 或 `linux-arm64`；更新由人工審核的新版本變更執行。CfT 不會自動更新，這正是可重現性的優點。
3. MCP server 也固定 npm 版本（不要用 `@latest`），並讓 lockfile／快取驗證 integrity。範例（假設 binary 已安裝於 `/opt/chrome-for-testing/153.0.8010.52/chrome-linux64/chrome`）：

```json
{
  "command": "npx",
  "args": [
    "--yes", "chrome-devtools-mcp@1.9.0",
    "--headless",
    "--executable-path=/opt/chrome-for-testing/153.0.8010.52/chrome-linux64/chrome",
    "--isolated",
    "--no-usage-statistics",
    "--no-performance-crux"
  ]
}
```

`--isolated` 會在結束時清理暫存 profile；若需要跨工作保留登入狀態，改用權限受限的 `--user-data-dir`，不要混用日常 profile。這個設定由 MCP 啟動 Chrome，與 repo 現有 WSL `--browser-url=http://127.0.0.1:9222` 模式不同。

4. 若選擇遠端 Chrome（SSH/Tailscale/其他隧道），MCP 僅使用 `--browser-url`／`--ws-endpoint` 連線；DevTools endpoint 綁 `127.0.0.1`，隧道與暴露範圍由主機部署決定。9222 等於完整瀏覽器控制權，不能直接綁公網。

## 尚待產品／運維決定的問題

- EC2 實例固定 `x86_64` 還是必須支援 Graviton `arm64`？這會決定是否把 153+ 作為最低 Chrome 版本。
- 版本更新節奏與回滾保存多久？需決定 CfT 完整版本、SHA256、Node/npm lockfile 的保存位置，以及誰批准升級。
- 採「MCP 自己啟動 headless」或「主機外部啟動後以 SSH/Tailscale 隧道連線」？兩者的登入狀態、網路邊界與監控責任不同。
- 是否允許任何需要 AppArmor 調整的 CfT binary，或改採發行版／Google Chrome 套件以取得既有 policy？此決定應先在目標 Ubuntu 24.04 AMI 做 sandbox smoke test。

## 限制

本研究沒有在 EC2 Ubuntu 24.04 安裝或啟動 Chrome，也沒有宣稱當前工作站的套件、AppArmor 或架構結果適用於目標機器。Chrome DevTools MCP v1.9.0 與 CfT feed 會繼續發布新版本；上面的版本與 feed 日期是可追溯的研究快照，不是永久承諾。
