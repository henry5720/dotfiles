# playwright-cli

## 為什麼裝

agent 要點、填表、跑流程、截圖時用 `playwright-cli`;查原因(慢、記憶體、console 錯誤)才用 chrome-devtools-mcp,
分工見 [ADR 0001](../adr/0001-browser-tools-drive-vs-debug.md)。

```text
選裝工具 playwright-cli ── Linux、Windows:mise 的 npm:@playwright/cli(會一併列 Node LTS)
        │                  macOS:npm install -g @playwright/cli(會一併裝 nvm)
        ├─ open ───→ 本機 Chrome:Linux 是 /opt/google/chrome/chrome ←── 選裝工具 headless-chrome 裝的那支
        │                         macOS 是 /Applications 的 Google Chrome(自己裝)
        │                         Windows 是一般的 chrome.exe ←────── headless-chrome 用 winget 確保有
        └─ attach ─→ 遠端瀏覽器:--extension 接你 Chrome 上的插件、--cdp=<網址> 接 CDP 端點
skill ──────────── 不在這個 repo,agent-config 用 skillshare 發
```

attach 的指令與連法見[瀏覽器](../remote-access/browser.md)。

| 問題 | 答案 |
|---|---|
| 哪些機器裝得了 | 除了原生 Termux 都裝得了(#349):Playwright 官方支援 Windows、WSL、macOS 14 以上、Debian 與 Ubuntu 的 x86-64 與 arm64([系統需求](https://playwright.dev/docs/intro));非 Debian 系 2026-11-20 在 `fedora:42` 容器實測 `attach --cdp` 可用。不跟 `headless-chrome` 綁:WSL、ARM、非 Debian 系、沒有 root 的機器裝不了本機 Chrome,一樣能 attach |
| 為什麼不讓它自己抓 | `playwright-cli install-browser` 不給參數會把 chromium、firefox、webkit 全抓下來,系統函式庫還要另外 apt |
| skill 在哪 | `playwright-cli install --skills` 那份由 agent-config 用 skillshare 發 |
| Windows 上找哪支 Chrome | 預設的 `chrome` channel 依序找 `%LOCALAPPDATA%`、`%ProgramFiles%`、`%ProgramFiles(x86)%` 底下的 `Google\Chrome\Application\chrome.exe`([playwright 原始碼](https://github.com/microsoft/playwright/blob/28c4b2e0ad892723c17c0b8d280207c1da670998/packages/playwright-core/src/server/registry/index.ts#L822-L829)),每次開用臨時的 user-data-dir,跟日常 profile、開著 9222 的獨立 profile 不衝突 |

## 坑

| 問題 | 答案 |
|---|---|
| 原生 Termux 為什麼不行 | Termux 的 Node 平台是 `android`,playwright-core 只認 `linux`、`darwin`、`win32`,連 `playwright-cli --version` 都丟 `Unsupported platform: android`(2026-11-20 termux-docker 實測 0.1.25)。同一台平板的 proot Ubuntu 照 Linux 的裝法(還沒在 proot 實測) |
| 沒有本機 Chrome 會怎樣 | 安裝時只提醒、印 attach 的兩種接法;`open` 直接報錯 `Chromium distribution 'chrome' is not found`,**不會自己下載**(2026-10-06 在 `node:22-bookworm-slim` 容器實測 0.1.22) |
| 換過 node 版本後不見了 | 只有 macOS 會:npm 全域套件綁在當下的 node 版本,`nvm use` 換版本後重跑 `npm i -g @playwright/cli`。Linux、Windows 由 mise 的 npm backend 裝,不綁 node 版本 |

## 更多

- [playwright-cli](https://github.com/microsoft/playwright-cli)：官方 README 與指令
