# codex

## 為什麼裝

Codex CLI，跟 Claude Code 並用的 coding agent。MCP 由 agent-config 的 skillshare 寫進 `~/.codex/config.toml`，
見 agent-config 的 [〈誰寫哪一段〉](https://github.com/henry5720/agent-config/blob/main/docs/mcp/README.md#誰寫哪一段)。

## 常用指令

```bash
codex app-server daemon version   # 本機 CLI 和背景 daemon 各是哪一版
codex app-server daemon restart   # 重開背景 daemon（改了環境變數後要跑，見〈坑〉）
```

## 坑

### 改了環境變數，MCP 還是拿到舊的

`codex` 的 TUI 不自己開 MCP server，而是連到背景的 app-server daemon，由 daemon 開。
`config.toml` 裡的 `env_vars = [...]` 轉交的是 **daemon** 的環境，不是你這個 shell 的，
所以只重開 `codex` 沒用。daemon 會一直開著，可能是好幾天前從舊 shell 帶起來的。

改了 env（例如 `DISCORD_TOKEN`）之後，從會讀 `env.zsh` 的 zsh 重開 daemon，再重開 `codex`：

```bash
zsh -c 'codex app-server daemon restart'
```

確認新 daemon 有拿到（只看有沒有，不印值）：

```bash
pid=$(pgrep -f 'codex app-server --listen' | head -1)
tr '\0' '\n' < /proc/$pid/environ | grep -c '^DISCORD_TOKEN=.'   # 1 = 有
```

2026-11-23 實測：daemon 是 11/10 起的，`codex` TUI 有 `DISCORD_TOKEN`，discord MCP 仍回報沒有 token；
重開 daemon 後新 daemon 帶到了。Claude 的背景 session 也有同一類問題，見 [claude〈坑〉](claude.md#改了環境變數背景-session-還是舊的)。

## 更多

- [Codex CLI](https://developers.openai.com/codex/cli)：官方文件
