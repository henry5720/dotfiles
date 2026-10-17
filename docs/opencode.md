# opencode 設定

`~/.config/opencode/opencode.json`(權限 600)由 `home/dot_config/opencode/modify_private_opencode.json.tmpl` 產生,
兩方共用:

```text
opencode.json
  ├─ provider、model、agent、plugin、instructions… ── 本 repo 說了算,每次 apply 整份蓋回 repo 版
  └─ mcp ──────────────────────────────────────────── skillshare 寫(agent-config 的 mcp.yaml),apply 原樣保留
```

`modify_` 的做法:整份照 repo 的版本輸出,只有 `mcp` 換回現有檔案裡的那段
(誰寫哪一段見 agent-config 的[〈誰寫哪一段〉](https://github.com/henry5720/agent-config/blob/main/docs/mcp.md#誰寫哪一段))。

- ⚠️ installer 或 opencode 自己寫進 `mcp` 以外的設定,下次 `chezmoi apply` 會被蓋回 repo 版,**而且不出聲**。
  要留住就改 repo 那份再 apply。
- `plugin`(`opencode-wakatime`、`oh-my-opencode-slim`)是 opencode 自己的 plugin,跟 Claude 的 `/plugin` 無關。
- `model`、`small_model` 取自 `oh-my-opencode-slim.json` 目前 preset 的 orchestrator 與 explorer。
- `instructions` 引用 `~/.config/opencode/commit-instructions.md`,那是指到 agent-config 的 symlink,
  見 [AI agent 環境〈規則〉](ai-agent-setup.md#規則)。
- 要加 MCP 不是改這裡,見 agent-config 的 [docs/mcp.md](https://github.com/henry5720/agent-config/blob/main/docs/mcp.md)。
  chrome-devtools 等 MCP 的版本也釘在 `mcp.yaml`,升級改那裡再 `skillshare sync mcp -g`。

## 改完怎麼驗證

這個檔含明文 API key,不要直接 `cat`:

```bash
chezmoi cat ~/.config/opencode/opencode.json | jq empty   # JSON 合法嗎
chezmoi apply ~/.config/opencode/opencode.json
opencode mcp list                                        # 看有沒有 connected
```

## provider 與 API key

自訂 base URL 的 `codex-lb-gcp` provider 寫在 repo 裡,所以不能只靠 `opencode auth login`。
API key 是 `chezmoi init` 時問的 `codexLbApiKey`,只存在 repo 外的 `~/.config/chezmoi/chezmoi.toml`;
之後要改見[裝完之後](after-install.md#憑證與-git-身分寫進哪裡)。

fork 這個 repo 時要換掉 provider 的 base URL,並在 `chezmoi init` 輸入自己的 key。
不要把渲染後的 `~/.config/opencode/opencode.json` 收回 repo,那份含明文 key。

## 為什麼拿掉 sequential-thinking

以前也寫在這份設定裡:Anthropic 從 2025-12 起建議改用 extended thinking 取代,而且長 session 記憶體會漲到 10GB 以上。
