# AI agent 環境:為什麼這樣分

[AI agent 環境:誰管什麼](ai-agent-setup.md)寫的是規則、skill、MCP、plugin 各在哪、怎麼更新;
這份寫為什麼這樣分,以及看到新工具時怎麼決定要不要裝。

## 三個原則

1. **除了規則,全部都是可選的。** skill、MCP、plugin 沒有「標準配備」,
   看你需要什麼就裝什麼,不裝也完全能用。
2. **本 repo 只維護「你自己寫的規則」。** 別人寫的 skill、MCP、plugin 一律不複製進來。
3. **這裡只記「去哪裡拿」,不記東西本身。** 重灌時照著指令重裝,不是還原備份。

## 規則只留一份

每家 agent 讀的全域檔名不一樣 —— Claude 是 `~/.claude/CLAUDE.md`,Codex、opencode 是 `AGENTS.md`。
各寫一份的話,改了 A 忘了改 B,兩邊行為就會不一樣(這件事真的發生過)。
所以只留一份真的檔案在 agent-config,各 client 的檔名都是 skillshare extras 建的 symlink;內容和「連到哪」為什麼分兩個 repo 管,
見 [ADR 0003](adr/0003-agent-instructions-linked-by-skillshare-extras.md)。

## 規則要寫什麼

只寫「換到任何一個 repo 都還成立」的事。判斷方法:

| 這件事是… | 寫在哪 |
|---|---|
| 換個 repo 就不成立(技術棧、build 指令、專案慣例) | **那個 repo 自己的 `AGENTS.md`**(Claude Code 2.1.277 起,repo 沒有 `CLAUDE.md` 時直接讀它) |
| 一套多步驟流程(查 bug、TDD、需求對齊) | **skill**,用到才載入 |
| linter、git hook、權限設定做得到 | **交給那些工具**;寫成規則只是「希望 agent 不要這樣做」 |

還有一條:**規則要能判斷有沒有違規**。
「講白話一點」沒辦法判斷;「一個句子拿掉抽象名詞就沒有資訊了就重寫」可以。
判斷不了的規則,你沒辦法抓它,agent 也就不會穩定遵守。

## 不要把本體放在 `dotfiles/.claude/CLAUDE.md`

看起來很整齊,但會出事。Claude 認的專案指引位置是 `./CLAUDE.md`、`./.claude/CLAUDE.md`(沒有它們時是 `./AGENTS.md`),
而多份 CLAUDE.md 是**接在一起**送進去、不是互相覆蓋。

所以在 dotfiles 裡開 Claude 會讀到兩次:一次是你的個人設定,一次是「dotfiles 這個專案的設定」——
同一份規則載入兩遍,白花錢,而且重複的指令本身就會讓 agent 更難遵守。

這條**不包含** repo 根目錄的 `AGENTS.md`。那份寫的是「怎麼改這個 repo」(檔名前綴、秘密、驗證方式),
和個人偏好不重複,載入一次,是正常的專案指引。

## 要不要裝一個新工具

看到一個工具想裝的時候,問下面四個問題。**這裡不列「該裝什麼」的清單** —— 清單會過時
(要看現況跑 `skillshare list -v`),判準不會。

### 1. 跟現有的重疊嗎

重疊的不要裝第二份。**skill 每多一個,每個 session 就多一段 description 常駐在 context 裡**,
而重複的指令本身會讓 agent 更難遵守(跟上面「不要把本體放在 dotfiles」同一個道理)。
caveman 只挑一個裝的例子見 [agent-config 的〈選 skill 的原則〉](https://github.com/henry5720/agent-config#選-skill-的原則)。

### 2. 成本量過了嗎

量,不要估。codegraph 的數字是實際跑出來的:7,135 檔的前端 261 MB、20 秒、**峰值 2.9 GB
記憶體**;`wsl/.wslconfig` 只給 16 GB,這個數字會影響「幾個 worktree 能同時 init」這種決定。

而量過之後結論可能翻盤:原本因為「11 個 worktree × 261 MB 太貴」打算不在 worktree 用
codegraph,量完發現 `df` 有 931 G 可用(0.3%),而且複製主索引只要 1 秒 —— 反對的理由兩個
都不成立。**憑印象估成本會做出錯的決定。**

### 3. 它承諾的行為,實測過嗎

README 寫的不算。codegraph 的 README 說「存檔 2 秒內自動同步」,實測 `init` 完根本沒有
watcher 行程,要有 MCP server 在跑才會同步(見 [codegraph〈索引什麼時候會跟上你的改動〉](codegraph.md#索引什麼時候會跟上你的改動))。
照 README 相信的話,就不會發現沒開 agent 的 repo 永遠不同步 —— 共用的 `post-merge` hook 就是實測後才補的。

### 4. 它自己寫的設定,chezmoi 會不會蓋掉

裝完跑 `chezmoi verify`。四種情況:

| installer 寫進哪 | 結果 | 怎麼辦 |
|---|---|---|
| `modify_` 納管的檔(`~/.claude/settings.json`、`~/.codex/config.toml`、`~/.codex/personal.config.toml`) | 留著 —— 那幾支只釘自己那段,其餘原封帶過 | 不用管,在[新機器 Runbook](new-machine-setup.md) 記一行重裝指令 |
| `~/.config/opencode/opencode.json` | `mcp` 留著,**其他 key 會被 apply 蓋掉,而且不出聲** | 把它要的內容收進 repo 那份,見 [opencode](opencode.md) |
| 規則的 symlink(`~/.claude/CLAUDE.md`、各 `AGENTS.md`) | 寫進去就改到 agent-config 的 source | 在 agent-config 看 `git diff`,要留就 commit |
| 沒被 chezmoi 管的路徑(含 `~/.claude.json`) | 留著,但換機器就沒了 | MCP 收進 agent-config(`skillshare mcp import`);其他的在[新機器 Runbook](new-machine-setup.md) 記一行重裝指令 |
