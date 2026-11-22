# 網頁 shell：ttyd-serve

服務卡：把一個 terminal 開成網頁，給只有瀏覽器的人用；對方不在 tailnet 時再另外開 Funnel。

| 項目 | 內容 |
|---|---|
| 服務 | ttyd，綁 127.0.0.1:7681；它自己沒有密碼，`ttyd-serve` 每次產一組隨機的 |
| 連線 | 同一台直接開 `http://127.0.0.1:7681`；tailnet 內 ssh `-L 7681:127.0.0.1:7681`；tailnet 外 `remote-access funnel`，見 [remote-access〈Tailscale Funnel〉](README.md#tailscale-funnel) |
| 操作者 | 人，用瀏覽器打字 |
| 用完收什麼 | 兩個終端機各按 Ctrl+C：先收 Funnel，再收 ttyd，見 [〈共通規則〉](README.md#共通規則) |

## 用法

1. 起 ttyd：

   ```bash
   ttyd-serve                                   # 開 login zsh
   ttyd-serve herdr session attach default      # 最後面接什麼，網頁就開什麼（tail -f 也行）
   ```

   ```
     http://127.0.0.1:7681
     帳號 guest  密碼 <每次隨機>
     (Ctrl+C 關閉，關了就失效)

     要給 tailnet 外的人用，另開一個終端機跑:
     remote-access funnel open --port 7681 --https 10000 --path / \
       --expect-without 401 --expect-with 200 --auth-header-cmd 'echo "Authorization: Basic <guest:密碼>"'
   ```

2. 對方不在 tailnet 時，另開一個終端機貼上它印的 `remote-access funnel open` 那行。它從公網驗證不帶密碼回 401、帶了回 200，
   兩邊都對才印 `公開網址：https://…`；沒過就自己撤掉。`remote-access funnel --help` 看參數。
3. 把公開網址和帳號密碼一起給對方。
4. 用完先在 Funnel 那個終端機 Ctrl+C，等它印 `已收乾淨`（公網連不上了），再到 ttyd 那個終端機 Ctrl+C。

```
對方的瀏覽器 ──公網──► funnel :10000 ──► ttyd 127.0.0.1:7681
                      remote-access funnel   ttyd-serve
```

script 在 [`home/dot_local/bin/executable_ttyd-serve`](../../../home/dot_local/bin/executable_ttyd-serve)，`ttyd-serve --help` 看用法。
它只做 ttyd 這半：

- **密碼每次隨機。** 這是能打字的 shell（`-W`），擋在前面的只有這組密碼。固定密碼等於
  每個拿過的人永遠有效，貼在聊天室也收不回來。反正網址也要傳給對方，順便帶上密碼不多一步。
- **從 herdr 的 pane 裡跑也能 attach herdr。** ttyd 會繼承 `HERDR_ENV`，網頁裡再
  `herdr session attach` 會被當成巢狀擋掉（nested herdr is disabled）；script 起 ttyd 前先拿掉它。
- **7681 有人在聽就不起**，不換 port。

## 為什麼要打兩個指令

以前一個指令同時起 ttyd 和 Funnel，現在拆成 `ttyd-serve` 和 `remote-access funnel`，多打一個指令。換到的是：

- **忘了收 ttyd 也連不到。** ttyd 綁在 loopback 又有密碼，Funnel 收掉之後外面就打不進來。
- **Funnel 開出去前先驗過。** `remote-access funnel` 從公網確認不帶密碼被拒、帶了才進得去，收掉後也確認公網連不上；只看 `tailscale funnel status` 會被騙（見〈Tailscale Funnel〉）。
- **要不要 sudo 由 `remote-access funnel` 判斷**，ttyd-serve 不用碰 tailscale。

ttyd 這半 2026-11-22 實測（Ubuntu、ttyd 1.7.7）：不帶密碼 401、帶了 200，收尾如下：

| 怎麼結束的 | ttyd |
|---|---|
| Ctrl+C（SIGINT） | 被 trap 收掉，7681 沒人聽 |
| SIGTERM | 同上 |
