# PROTOTYPE：Headless 瀏覽器（a1）用哪個工具、留幾支

不會 merge。回答 [#247](https://github.com/henry5720/dotfiles/issues/247)，結論記在該 issue 的 resolution comment。

- 環境：company-ec2，Google Chrome 154 headless（9333、暫存 profile），`@playwright/cli` 0.1.23、`agent-browser` 0.41.2 裝在暫存目錄。2026-11-04 實測。
- 重跑：`bash run.sh`（需要 google-chrome、node、jq、能連外）

## 實測 11：playwright-cli 一律 `attach --cdp` 能不能取代 `open`

| session | 語系 | 視窗 | cookie |
|---|---|---|---|
| attach a（設 cookie、resize 1440x900） | en-US | 1440x900 | sid=AAA |
| attach b（帶 zh-TW 設定檔） | en-US | 1440x900 | sid=AAA |
| open d（帶 zh-TW 設定檔） | zh-TW | 1280x720 | (none) |

- attach 的 session 全部操作同一個分頁、共用 cookie；`--config` 被忽略；`state-load` 會蓋掉共用 profile 的 cookie。
- attach 下 goto、click、截圖、錄影、state-load、detach（Chrome 留著）都能用。
- 結論：不合併。`verify-in-browser` 的平行 session、設定檔語系、`auth*.json` 都靠 `open` 的隔離 context。

## 實測 8：agent-browser

- `--pin-tab`：自己開新分頁；別的 CDP client 把自己的分頁切到前景後，click 仍落在 agent-browser 的分頁。
- snapshot 位元組：

| 頁面 | agent-browser | agent-browser `-i` | playwright-cli `snapshot --filename` |
|---|---|---|---|
| news.ycombinator.com | 26,574 | 14,797 | 47,540 |
| playwright.dev/docs/intro | 25,097 | 8,085 | 31,587 |

- skill：入口 `skills/agent-browser/SKILL.md` 3,220 B ＋ `skill-data/core/SKILL.md` 14,457 B；本機 playwright-cli SKILL.md 15,428 B。
- 每個 session 的 daemon 在 `127.0.0.1:<隨機 port>` 開 HTTP dashboard，不用驗證，回 `Access-Control-Allow-Origin: *`。
- 結論：不採用。

## 實測 3：`playwright-cli show` dashboard

- `show --port 8899` 只綁 127.0.0.1；開「Enable interactive mode」後，在畫面上點擊、打字、Backspace 都進到頁面（`clicked 1 | input=hi12`）。
- attach 的 session 也會列在 dashboard。
- 結論：人要看 a1 畫面用 `show --port` + `ssh -L`。

## 附帶發現

- 0.1.23 要 `~/.cache/ms-playwright/ffmpeg-1013`，機器上只有 0.1.22 的 `ffmpeg-1011`。沒補裝時，第一次 `video-start`/`video-stop` 回報影片路徑但沒有檔案；之後 `video-start` 才報 `Executable doesn't exist`。補裝：`npx playwright install ffmpeg`。
- `home/.chezmoiscripts/run_onchange_after_npm-install-playwright-cli.sh.tmpl` 已裝就跳過，不會升級。
