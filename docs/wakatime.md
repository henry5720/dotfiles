# WakaTime

勾了選裝工具 `wakatime` 才有。wakatime-cli 負責把時間送上 WakaTime，但它自己不會動：
要各工具的官方 plugin 觸發它才會記到。

```text
Claude Code ─ claude-code-wakatime ─┐
Codex CLI ─── codex-cli-wakatime ───┼─→ ~/.wakatime/wakatime-cli ─→ WakaTime
code-server ─ vscode-wakatime ──────┘        讀 ~/.wakatime.cfg 的 API key
```

## 裝什麼

`wakatime` 加上同時勾的那個工具，apply 時才裝它的 plugin；只勾其中一個不裝，已經裝了就跳過。
之後才補勾任一邊，打 `tools` 勾完就會裝。

| 同時勾 | 裝什麼 | 確認 |
|---|---|---|
| `claude` | [claude-code-wakatime](https://github.com/wakatime/claude-code-wakatime) | `claude plugin list` 有 `claude-code-wakatime@wakatime` |
| `codex` | [codex-cli-wakatime](https://github.com/wakatime/codex-cli-wakatime) | `codex plugin list` 的 installed 有 `codex-cli-wakatime@wakatime` |
| `code-server` | Open VSX 的 [WakaTime.vscode-wakatime](https://open-vsx.org/extension/WakaTime/vscode-wakatime) | `code-server --list-extensions` 有 `wakatime.vscode-wakatime` |

## 第一次要做的

- Codex 的 hook 要先 review 過才會跑：第一次開 codex 會提示，同意後才開始記。
- Claude Code、Codex 的 plugin 用 node 跑 hook，要一起勾 `nvm`。
- API key 留空（init 時沒填）就不部署 `~/.wakatime.cfg`，什麼都不會送。要改見[裝完之後](after-install.md)。

## 沒記到

- 看 `~/.wakatime/wakatime.log`，Codex 的在 `~/.wakatime/codex-cli.log`。
- `~/.wakatime/wakatime-cli --today` 看今天送了多少。

## 為什麼這樣裝

- wakatime-cli 照官方 `install_cli.py` 的位置：本體 `~/.wakatime/wakatime-cli-linux-<arch>`，
  symlink 成 `~/.wakatime/wakatime-cli`。各 plugin 都找這裡，也會自己更新它。
- 不裝 zsh 的 WakaTime 外掛：官方的 [terminal 頁面](https://wakatime.com/terminal)明講別用 terminal
  plugin。以前裝過的機器，apply 時會刪掉舊的 `~/.config/zsh/wakatime-zsh-plugin`（列在 `home/.chezmoiremove`）。
