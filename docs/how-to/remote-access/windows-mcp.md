# Windows 桌面：windows-mcp

讓別台的 agent 操作某台 Windows 的 GUI app（截圖、點擊、打字）。agent 怎麼做寫在 agent-config 的
[`windows-access` skill](https://github.com/henry5720/agent-config/blob/main/skills/windows-access/SKILL.md)；
這份是你自己在 agent 那台（例如 company-ec2）要打的常用指令。

- **agent 跟那台 Windows 同一台**（那台 WSL 裡的 Claude Code、Codex）：`mcp.yaml` 的 `windows-mcp` 走 stdio，client 用時才帶起來，裝好就好，下面都不用。
- **別台**：用 agent-config 的 `remote-access` CLI（`~/.claude/skills/remote-access/scripts/remote-access`）在那台起 server、經 `tailscale serve` 接 MCP。

## 第一次

1. **那台 Windows 裝 Windows-MCP**：裝了 dotfiles 的在 PowerShell 打 `tools` 勾 windows-mcp，見 [Windows 主機〈windows-mcp〉](../windows.md#windows-mcp)；
   沒裝 dotfiles 的照 [CursorTouch/Windows-MCP](https://github.com/CursorTouch/Windows-MCP) 的 README 裝。那台要能 ssh 進去、有登入桌面。
2. **先接受 host key**：新機器，或 ssh config 的 HostName 剛改成全名時，先手動跑一次 `ssh <host> true`，回答 `yes`。
   `remote-access` 用 `BatchMode=yes` 連，不會問 host key，known_hosts 裡沒有這個名字就直接 `Host key verification failed`。
3. **agent 這台產生 key**：`remote-access key init`，再開新的 session（`~/.zshenv` 從 `~/.config/windows-mcp/auth.env` 讀 key）。

## 常用指令

`<host>` 是 ssh config 的 Host（`desktop`、`laptop`…）。參數看 `remote-access <子命令> --help`。

| 要做的事 | 指令 |
|---|---|
| 接上那台（第一次在那台加 `--create-task`，會留一個常駐 task） | `remote-access up windows-mcp <host>` |
| 看接著哪幾台、驗證過沒 | `remote-access ps` |
| 收掉那台 | `remote-access down windows-mcp <host>` |
| 換 key（交過、懷疑外洩），已接上的機器一起換 | `remote-access key rotate`，再開新的 session |

接上之後在 session 裡打 `/mcp` 重連。

## 常駐 task 不用了

`down` 不刪常駐 task。那台以後不再接時，先 `remote-access down windows-mcp <host>`，再在那台的 PowerShell 跑：

```powershell
Unregister-ScheduledTask -TaskName remote-access-windows-mcp -Confirm:$false
```

之後要再用就重新 `up --create-task`。

## 坑

`up` 的錯誤訊息和 serve 模式的坑見 remote-access 的
[reference.md](https://github.com/henry5720/agent-config/blob/main/skills/remote-access/reference.md)；
server 本身的坑（`/mcp/` 307、`Host` 檢查、session 順序）見 windows-access 的
[reference.md](https://github.com/henry5720/agent-config/blob/main/skills/windows-access/reference.md)。
