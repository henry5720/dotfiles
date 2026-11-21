# claude

## 為什麼裝

Claude Code，主力 coding agent。一般模式、背景模式（`--bg`、`claude agents`、`claude attach`）怎麼選，
以及同一個對話在兩個地方打開會怎樣，見[操作已配置主機〈coding agent〉](../configured-host.md#coding-agent)。

## 常用指令

```bash
claude agents            # 看背景 session（--help 只寫 Manage background agents）
claude respawn --all     # 重啟所有背景 session，讓它們換上新的 claude 執行檔
claude daemon status     # 背景 session 的 daemon 在不在、哪個版本
```

## 坑

### 改了環境變數，背景 session 還是舊的

背景 session 由 `claude daemon` 產生，環境變數跟著 daemon 走，不跟著你現在的 shell。
改了 env（例如 `GRAPHIFY_API_KEY`）之後，開一個新 shell（讓它讀到新 env），依序跑：

```bash
claude daemon stop --any --keep-workers   # 停掉舊 daemon，背景 session 留著
claude agents                             # 從這個 shell 重新帶起 daemon
claude respawn --all                      # 背景 session 從新 daemon 重開
```

2026-11-21 實測：7 個背景 session 都帶到新 env。

## 更多

- [Claude Code](https://code.claude.com/docs/en/)：官方文件
