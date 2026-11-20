# 選單每台列全部工具，環境只決定預設勾什麼、勾了裝不裝得起來

每台機器（Linux、macOS、原生 Termux、Windows 主機）走同一個流程：`chezmoi init` → 用途 → 選單 → apply。
選單列 `home/.chezmoitemplates/tool-menu` 的全部工具；環境（OS、WSL、架構、是不是 Debian 系）只決定每個工具在這台的狀態：

| 狀態 | 選單 | 預設組合 | 勾了 |
|---|---|---|---|
| 可裝 | 照常列 | 照用途 | 裝 |
| 不建議（例：WSL 的 tailscale，網路借外層的 Windows） | 列，後面標原因 | 不勾 | 照裝 |
| 裝不了（例：WSL、ARM 的 headless-chrome） | 列，後面標原因 | 不勾 | 略過；apply 照樣跑完，最後列出原因 |

「工具 × 環境 → 狀態＋原因」只寫在選裝工具表 `home/.chezmoidata/tool-table.yaml`（各工具的 `install` 與 `rules`，spec #315），
由裝法判斷 `home/.chezmoitemplates/tool-install` 算出；選單標註、預設組合、略過彙整、選裝工具的腳本、套件清單
與各 client 的設定目錄（`.chezmoiignore`）都照它的結果。表上沒有這個 OS 的裝法、也沒有規則對到時自動算裝不了，
原因固定是「沒有這個環境的裝法」；要解釋的（有裝法卻用不了、刻意不裝）才在表上寫規則。
config 樣板（`chezmoi init`）直接讀不到 data 目錄的值，但 `include ".chezmoidata/tool-table.yaml" | fromYaml` 讀得到
（chezmoi 2.74.1 實測，`chezmoi init` 也一樣），所以判斷在 init 時用 `include` 讀表，apply 時直接用 data。
（#331 以前規則寫成 `.chezmoitemplates/` 底下的樣板，就是因為當時以為 init 讀不到 data 目錄。）
選裝工具的腳本與各 client 的設定目錄看 `tools-to-install`（判斷結果裡要裝的：勾了、裝得了的，加上被連帶裝的 node），裝不了的勾了就不跑、不部署；
略過由一支 `run_onchange_after_record-env-skipped` 統一記下，`run_after_zz-root-skipped-summary` 跟「沒有 root」分兩段列出。
加一個環境限制只要在表上那個工具加一條規則，不用改各工具的腳本。

Windows 主機也出用途與選單、也跑安裝腳本（#275）：CLI 用 mise、app 用 winget（都寫在選裝工具表，跟 Linux 同一筆），
腳本寫成 `.ps1`，`.chezmoiignore` 的 Windows 段只放行 `.chezmoiscripts/*.ps1`，sh 腳本照舊不會到 Windows。
Windows 上 mise 裝得了的都可裝（`node` 也由 mise 裝 LTS，Linux 從 #342 起也是；herdr 也是，#309；playwright-cli 走 mise 的 npm backend、headless-chrome 用 winget 裝 Chrome，#327），
claude、codex 與 agent-config 的 skillshare 走官方 `install.ps1`（#316、#317、#321），opencode 走 mise 的 npm backend（#318），codegraph 走 mise 的 aqua backend（#323），
wakatime 把官方 release 的 wakatime-cli 放到 plugin 找的位置、為勾了的 agent 裝 plugin（#324），其他沒有 Windows 裝法的標裝不了：
工具本身沒有 Windows 版（code-server、mise 的 btop），或是要 systemd 的系統服務（earlyoom、snapserver）。zsh 則是 Windows 的 shell 換成 PowerShell。
Windows 的略過彙整是一支 `zz-env-skipped.ps1`。
原本「只有 sh 版、沒在 Windows 驗過」的那一批（coding agent、codegraph、wakatime）已經照 [ADR 0005](0005-install-method-by-tool-kind.md) 補上 Windows 的裝法（#314）。

## Considered Options

| 做法 | 結果 | 為什麼 |
|---|---|---|
| 選單不列這台不支援的工具（#272 以前） | 不選 | 使用者不知道有這個工具、也不知道為什麼沒有；條件散在 config 樣板的 `$skip` 和各腳本開頭，兩邊各寫一份，WSL、ARM、macOS 各自對不齊 |
| 原生 Termux 不問，固定套精簡 | 不選 | 每次 `chezmoi init` 都把 tools 重算回固定那幾項，手動加的會不見；平板也想用 `tools` 加減工具 |
| Windows 主機只管 shell 設定，不跑安裝腳本 | 不選 | 假設 Windows 一定是 WSL 的外層；fork 的人可能沒有 WSL，Windows 就是開發機，CLI 工具要自己照 Runbook 一個個 winget |
| 勾了裝不了的工具就報錯、中斷 apply | 不選 | 排在後面的工具會全部沒裝；選單上已經標了原因，使用者是知情勾的，略過再列出來就夠 |
| 每支工具腳本自己判斷環境、自己記略過 | 不選 | 只有部分工具有自己的腳本（走 apt、pkg、mise 的沒有），新增一個環境限制要改好幾支腳本；改成一支腳本照判斷結果統一記 |
| 列全部、標狀態，原因只寫在選裝工具表 | **選** | 換 OS 不用重學；勾之前就知道結果；新增環境限制只加一條規則 |

## 代價

- **選單文字變長。** 原因接在說明後面，終端機窄時會折行。原因要短，寫「為什麼不行」；repo 裡有另一條裝得起來的路才接著寫（「改勾 bottom」「到 proot Ubuntu 裝」）。
  缺的是 root 時只寫事實、不教人怎麼做：選單的原因（#315 2026-11-20 的決定）和 apply 時的略過訊息（#339）都一樣，
  略過訊息寫略過了什麼、缺什麼、為什麼要 root、對應的指令。使用者可能有別的辦法（例如把 `.deb` 解到家目錄），怎麼補由他決定。
- **原因文字有字元限制。** 不能有半形 `/`（e2e 的 `--promptMultichoice` 拿它分隔選項）、`'`（略過腳本用單引號包它）、`=`；
  `script/tests/test_tool_table.py` 會擋。
- **e2e 要在主機上渲染選單文字。** 標註依環境而變，`script/tests/e2e.sh` 的 `menu_choice` 改用主機的 chezmoi 渲染
  `tool-menu-labels`，主機要有 chezmoi 與 python3。
- **Windows 的 `.ps1` 綁在 Windows PowerShell 5.1。** 第一次 init 時 pwsh 7 多半還沒裝、5.1 的執行原則預設 `Restricted`，
  所以 config 的 `[interpreters.ps1]` 固定用 `powershell -ExecutionPolicy Bypass`（偏離 chezmoi 預設的 pwsh）。
  5.1 讀沒有 BOM 的檔案用 ANSI 字碼頁：渲染結果只能有 ASCII，中文訊息（含表上的原因）用 base64 放進腳本、執行時才解。
- **勾了裝不了的工具，略過只印一次。** `record-env-skipped` 是 `run_onchange_`：勾選或原因沒變，之後的 apply 不再印，
  `chezmoi status` 也不會一直有待跑的腳本。
