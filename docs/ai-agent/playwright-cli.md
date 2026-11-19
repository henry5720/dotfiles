# playwright-cli

agent 要點、填表、跑流程、截圖時用 `playwright-cli`;查原因(慢、記憶體、console 錯誤)才用 chrome-devtools-mcp,
分工見 [ADR 0001](../adr/0001-browser-tools-drive-vs-debug.md)。

```text
選裝工具 playwright-cli ── Linux:npm install -g @playwright/cli(會一併裝 nvm)
        │                  Windows:mise 的 npm:@playwright/cli(會一併列 Node LTS)
        └─ 開瀏覽器 ──→ Linux:/opt/google/chrome/chrome ←── 選裝工具 headless-chrome 裝的那支
                        Windows:一般的 chrome.exe ←────── headless-chrome 用 winget 確保有(已經有就跳過)
skill ──────────── 不在這個 repo,agent-config 用 skillshare 發
```

| 問題 | 答案 |
|---|---|
| 哪些機器出現在選單 | 跟 `headless-chrome` 同一個條件:Linux 要非 WSL、amd64、Debian 系;Windows 主機都可裝(#327)。WSL 不裝第二支 Linux Chrome(agent 要用瀏覽器時到已配置主機做,見[瀏覽器](../remote-access/browser.md)),ARM 沒有 Google 的 `.deb` |
| 沒有那支 Chrome 會怎樣 | 安裝時只提醒;`open` 直接報錯 `Chromium distribution 'chrome' is not found`,**不會自己下載**(2026-10-06 在 `node:22-bookworm-slim` 容器實測 0.1.22) |
| 為什麼不讓它自己抓 | `playwright-cli install-browser` 不給參數會把 chromium、firefox、webkit 全抓下來,系統函式庫還要另外 apt |
| skill 在哪 | `playwright-cli install --skills` 那份由 agent-config 用 skillshare 發 |
| Windows 上找哪支 Chrome | 預設的 `chrome` channel 依序找 `%LOCALAPPDATA%`、`%ProgramFiles%`、`%ProgramFiles(x86)%` 底下的 `Google\Chrome\Application\chrome.exe`([playwright 原始碼](https://github.com/microsoft/playwright/blob/28c4b2e0ad892723c17c0b8d280207c1da670998/packages/playwright-core/src/server/registry/index.ts#L822-L829)),每次開用臨時的 user-data-dir,跟日常 profile、開著 9222 的獨立 profile 不衝突 |
| 換過 node 版本後不見了 | npm 全域套件綁在當下的 node 版本,`nvm use` 換版本後重跑 `npm i -g @playwright/cli` |
