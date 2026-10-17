# codegraph

[codegraph](https://github.com/colbymchenry/codegraph) 把程式碼建成 symbol 圖,agent 用 `codegraph_explore`
一次拿到「相關符號原始碼 + 呼叫路徑」,取代一堆 grep。CLI 要勾選裝工具 `codegraph`(要一起勾 `nvm`);
共用 git hook 和 `codegraph-setup-repo` 每台都部署,找不到 `codegraph` 時什麼都不做。
它同時是 CLI、MCP server 和背景 daemon,三樣東西由不同地方管:

```text
CLI ─────────── chezmoi:選裝工具跑 npm install -g @colbymchenry/codegraph
MCP server ──── agent-config 的 mcp.yaml,skillshare 寫進 Claude / Codex / OpenCode
索引 ────────── 每個 repo 自己的 .codegraph/
  ├─ 建索引 ─────── codegraph-setup-repo ~/code/<repo>
  ├─ 新 worktree ── 共用 post-checkout hook:複製主索引 + sync
  └─ git pull ──── 共用 post-merge hook:sync
```

## 裝

chezmoi 只跑 `npm i -g @colbymchenry/codegraph`(`home/.chezmoiscripts/run_onchange_after_npm-install-codegraph.sh.tmpl`)。
另外一行要不要跑自己決定:

```bash
codegraph install -t claude -l global -y   # 只為了 Claude 的 prompt hook 和權限,MCP 不靠它
```

**MCP 不靠 `codegraph install`。** `codegraph install` 現在只剩一件事是別人不做的:在 `~/.claude/settings.json`
加 `codegraph prompt-hook` 和 `permissions.allow`。不跑的話 MCP 照樣能用,只是少了 prompt hook 提醒、
呼叫工具時要多按幾次允許。不要用 `-t opencode`、`-t codex`,那兩邊的 MCP 交給 skillshare 寫。

`codegraph install` 會動三個地方:

| 它改了什麼 | apply 之後還在嗎 | 為什麼 |
|---|---|---|
| `~/.claude.json` 的 `mcpServers.codegraph` | 在 | chezmoi 不管 `~/.claude.json` |
| `~/.claude/settings.json` 的 `codegraph prompt-hook` + `permissions.allow` | 在 | `modify_settings.json.tmpl` 只釘 chrome-devtools plugin 開關與 commit attribution,其餘照留 |
| `~/.claude/CLAUDE.md` 的 `<!-- CODEGRAPH_START -->` 區塊 | 會改到 agent-config | 這份是指向 agent-config `instructions/agents-md/AGENTS.md` 的 symlink,寫進去就是改 source |

- 第一列:它沒有「只裝 hook、不寫 MCP」的選項。內容跟 `mcp.yaml` 一字不差時 skillshare 列為 `unchanged`,不會衝突,
  但也不會認領;要讓 skillshare 接手就 `skillshare mcp import codegraph --from claude`
  (見 agent-config 的[〈從舊版 dotfiles 升上來的機器〉](https://github.com/henry5720/agent-config/blob/main/docs/mcp.md#從舊版-dotfiles-升上來的機器))。
- 第三列:那段已經收進 agent-config 的 `AGENTS.md`,**保留英文原文和 START/END 標記** ——
  `codegraph upgrade` 會重寫兩個標記之間的內容,翻成中文的話每次升級都會在 agent-config 留下修改。

⚠️ **第一次 `codegraph install` 會把 `~/.claude.json` 從 600 改成 644**(2026-08-20 在沒裝過的機器實測;
`--refresh` 不會重現)。那個檔有帳號資訊、chezmoi 不管它,裝完自己修:

```bash
stat -c %a ~/.claude.json    # 644 就修
chmod 600 ~/.claude.json
```

### 換 node 版本之後

npm 全域套件綁在當前 node 版本(`npm config get prefix` 是 `~/.nvm/versions/node/<版本>`)。`nvm use` 換版本後
`codegraph` 就從 PATH 上消失,而 MCP server 的 command 是裸的 `codegraph` —— 它會變成連不上,
而不是報「找不到指令」。重跑一次 `npm i -g @colbymchenry/codegraph` 就好。playwright-cli 同理。

## 哪些 repo 要建索引

判準是「檔案多到 grep 不完」。實測:

| 專案 | 索引到的檔 | init 耗時 | 峰值記憶體 | 索引大小 |
|---|---|---|---|---|
| 工作用的前端(React) | 7,135 | 20 秒 | 2.9 GB | 261 MB |
| 工作用的主後端(Python) | 2,604 | 31 秒 | 2.8 GB | 274 MB |
| `~/code/fizzt-frontend` | 54 | 1.4 秒 | — | 1.8 MB |
| 這個 dotfiles repo | **5** | — | — | 400 KB |

後兩個不值得:54 個檔 agent 直接讀還更準。dotfiles 這種幾乎只有 shell script 和設定檔的 repo
特別不值得 —— codegraph 不解析那兩種。

⚠️ **峰值記憶體 2.9 GB。** `wsl/.wslconfig` 給 16 GB,別讓兩三個 init 同時跑。

## 每個 repo 接上

```bash
codegraph-setup-repo ~/code/<repo>   # 建索引;repo 被 husky 搶走 core.hooksPath 時補轉接
```

新機器上的清單檔、沒有清單時的行為,見[新機器設定 4.6](new-machine-setup.md#46-各-repo-的-codegraph-setup)。
手動操作:

```bash
cd <repo>
codegraph init      # 建索引
codegraph status    # 看索引狀態
codegraph sync      # 手動同步(-q 給 hook 用)
codegraph uninit -f # 移除(注意是 -f,不是 -y)
```

`.codegraph/` 裡自帶一份 `.gitignore`(`*` 加 `!.gitignore`),db 不會進版控;目錄本身由全域
`~/.config/git/ignore` 擋掉,不會出現在 `git status`。

## 索引什麼時候會跟上你的改動

codegraph 的 README 寫「存檔 2 秒內自動同步」,**但那要有 watcher,而 watcher 綁在 MCP server 上**。實測:

| 情境 | 結果 |
|---|---|
| `codegraph init` 完就放一個新檔進去 | 等 15 秒索引完全不動;`pgrep codegraph` 也沒有任何 watcher 行程 |
| 有 `codegraph serve --mcp`(cwd 在該專案)時放新檔 | **第 1 秒進索引** |
| 沒有 server 時改檔,之後才開 server | 啟動當下就補完 |

所以你在那個 repo 開 Claude Code / opencode,MCP server 起來、watcher 跟著跑,改的檔就自動同步;
沒開 agent 的那段時間不同步,下次開 agent 就補上。

**你不會在裡面開 agent 的 repo 永遠等不到「下次」** —— 例如從前端用 `-p <那個 repo>` 查過去的後端。
那邊沒有 server,`git pull` 拉進來的改動不會進索引,而查詢不會告訴你索引是舊的。
這個縫由共用的 `post-merge` hook 補:`git pull` / `git merge` 之後跑 `codegraph sync -q`。
sync 比對的是內容雜湊不是 mtime,內容沒變就不重解析(實測 `touch` 1000 個檔 0.77 秒);
fast-forward 與 `--no-ff` 都會觸發。

⚠️ MCP server 不保證跟著 session 死。找殘留的:

```bash
for p in $(pgrep -f "codegraph.*serve --mcp"); do echo "$p -> $(readlink /proc/$p/cwd)"; done
```

## 新 worktree 的索引

什麼都不用做:共用的 `post-checkout` hook 會把主 checkout 的 `.codegraph/` 複製過來再 sync。

```text
$ git worktree add -b tmp ../wt-check
codegraph: 索引已從 /home/henry/code/<主 checkout> 複製並同步
```

`git worktree add` 會觸發 `post-checkout`,所以用 herdr、`git worktree add` 還是 IDE 開都一樣。
不想在某個 repo 放 hook 轉接時,手動:

```bash
cd <新 worktree>
cp -r <主 checkout>/.codegraph .codegraph && codegraph sync -q
```

為什麼是複製,不是重建或共用:

| 做法 | 結果 |
|---|---|
| 在 worktree `codegraph init` | 25 秒、峰值 2.9 GB |
| `cp -r` 主索引 + `codegraph sync` | **約 1 秒、峰值 123 MB**。索引 db 沒有絕對路徑,sync 只重解析跟主 checkout 不同的檔 |
| symlink 主索引 | **不行**:worktree 的 sync 會寫回索引,把主 checkout 那份寫髒(`node_modules` 可以 symlink,這個不行) |
| 站在 worktree 用 `codegraph_explore` 的 `projectPath` 查主 checkout | **不行**,見下 |

`projectPath` 查到的是主 checkout 的檔案內容,而輸出自己寫著
「verbatim, current on-disk source … Treat each block as a Read you have already performed」。
agent 會當成磁碟上的內容、不再 Read;你在 worktree 改過的檔案會拿到舊簽名,路徑又只是相對路徑,
**沒有任何不一致的訊號**(`--max-files 0` 也關不掉那段原始碼)。真的只要跨檔關係就走 CLI,
它只輸出 `符號 + 檔案:行號`:

```bash
codegraph callers <symbol> -p ~/code/<repo>
codegraph impact  <symbol> -p ~/code/<repo>
```

## 共用 git hook 怎麼接上

全部在全域、由 chezmoi 部署,**不用逐 repo 設**:

| chezmoi 檔案 | 部署到 | 做什麼 |
|---|---|---|
| `home/dot_config/git/ignore` | `~/.config/git/ignore` | 全機器忽略 `.codegraph/`(git 預設就讀這路徑) |
| `home/dot_config/git/config` | `~/.config/git/config` | `includeIf "gitdir:~/code/"` 帶進 `config-code` |
| `home/dot_config/git/config-code` | 同目錄 | `core.hooksPath = ~/.config/git/hooks` |
| `home/dot_config/git/hooks/executable_post-checkout` | `~/.config/git/hooks/post-checkout` | 新 worktree:複製主索引 + sync |
| `home/dot_config/git/hooks/executable_post-merge` | `~/.config/git/hooks/post-merge` | `git pull` / `merge` 後 sync |

- 只有 `~/code/` 底下的 repo 生效。`includeIf` 比對的是 **gitdir**,herdr 放在
  `~/.herdr/worktrees/<repo>/<slug>/` 的 worktree,gitdir 是 `~/code/<repo>/.git/worktrees/<slug>`,所以也算。
- git 同時讀 `~/.config/git/config` 和 `~/.gitconfig`,身分設定留在 `~/.gitconfig`,不用動。
- 改 `core.hooksPath` 會讓 repo 自己的 `.git/hooks/` 失效。設定當時 `~/code` 的 12 個 repo 加 8 個子 repo,
  `.git/hooks/` 全部只有 `.sample`,沒踩掉東西。

### repo 自己搶走 core.hooksPath

repo 在 local config 設了 `core.hooksPath`,共用 hook 就**靜默失效** —— local 贏 global。husky 就是這樣做的
(`core.hooksPath=.husky/_`)。

```bash
git config --local --get core.hooksPath   # 有輸出 = 被搶走了
```

`codegraph-setup-repo` 遇到 husky 會自動補轉接:在 `.husky/post-checkout`、`.husky/post-merge` 放一支
轉呼叫 `~/.config/git/hooks/<同名>` 的小腳本,並寫進 `.git/info/exclude`。不是 husky 的它只警告、不猜。

- 用 `.git/info/exclude` 不用 `.gitignore`:前者機器本地、永不 commit,共用 git dir 所以所有 worktree 立刻生效。
- 轉接和共用 hook 最後都明確 `exit 0`:husky 用 `sh -e` 跑 hook 並把 exit code 傳回去,
  `[ 條件 ] && ...` 在條件不成立時整條回 1,husky 就印 `husky - post-checkout script failed (code 1)`。
- 不要改 `.git/config` 蓋回共用的 `core.hooksPath`:套件安裝可能把 husky 設定寫回去,而且會讓 husky 自己的 hook 停止運作。
