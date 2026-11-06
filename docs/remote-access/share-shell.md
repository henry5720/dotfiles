# 網頁 shell：share-shell

服務卡：把一個 terminal 臨時開成公網網頁，給不在 tailnet、只有瀏覽器的人用。

| 項目 | 內容 |
|---|---|
| 服務 | ttyd，綁 127.0.0.1:7681；它自己沒有密碼，`share-shell` 每次產一組隨機的 |
| 連線 | Funnel 10000（tailnet 外），見 [remote-access〈Tailscale Funnel〉](README.md#tailscale-funnel) |
| 操作者 | 人，用瀏覽器打字 |
| 用完收什麼 | Ctrl+C：funnel 和 ttyd 一起關，見 [〈共通規則〉](README.md#共通規則) |

## 用法

```bash
share-shell                                   # 開 login zsh
share-shell herdr session attach default      # 最後面接什麼，網頁就開什麼（tail -f 也行）
```

```
  https://company-ec2.tail9b4b9b.ts.net:10000
  帳號 guest  密碼 <每次隨機>
  (Ctrl+C 關閉，關了就失效)
```

整段複製給對方。用完 Ctrl+C，或直接關掉那個終端機。

```
對方的瀏覽器 ──公網──► funnel :10000 ──► ttyd 127.0.0.1:7681
```

`share-shell` 同時起這兩個，Ctrl+C 一起關。

script 在 [`home/dot_local/bin/executable_share-shell`](../../home/dot_local/bin/executable_share-shell)。
它比 dev server 多做的只有一件：**幫 ttyd 產密碼**。

- **密碼每次隨機。** 這是公網上能打字的 shell（`-W`），擋在前面的只有這組密碼。固定密碼等於
  每個拿過的人永遠有效，貼在聊天室也收不回來。反正網址也要傳給對方，順便帶上密碼不多一步。
- **從 herdr 的 pane 裡跑也能 attach herdr。** ttyd 會繼承 `HERDR_ENV`，網頁裡再
  `herdr session attach` 會被當成巢狀擋掉（nested herdr is disabled）；script 起 ttyd 前先拿掉它。
- **要不要 sudo 自己判斷**：看 `tailscale debug prefs` 的 `OperatorUser`，是你就不加。

2026-10-02 在 company-ec2 實測收尾：

| 怎麼結束的 | funnel | ttyd |
|---|---|---|
| Ctrl+C（SIGINT） | 撤掉 | 被 trap 收掉 |
| 整個 process group 被 SIGKILL（例如 herdr 關 pane） | 撤掉，公網連過去 connection refused | 跟著死 |
