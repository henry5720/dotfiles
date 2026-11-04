# 沒有 root 的機器

別人給的帳號、公司的工作區常常不能 `sudo`。這份寫這種機器怎麼裝、裝完還剩什麼要自己做。
任何沒有 sudo 的帳號都適用；TeamSync 工作區當例子。

```text
一行裝好（chezmoi 自動處理不用 root 的部分，要 root 的記進略過彙整）
  └─ 有勾 tailscale、要當 ssh client 連 tailnet 的機器才繼續：
       ├─ 登入 tailscale（打開網址核准）
       └─ 例子：在 company-ec2 加這台的專用 key
字型（可選）：圖示變方塊才需要
```

## 1. 一行裝好

跟有 root 的機器同一行，不用回答用途與選單時用免回答那行（套精簡，只帶 git email）：

```bash
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply --promptDefaults \
  --promptChoice "用途：按一個字母（full 完整／minimal 精簡：server、ssh 連線用／custom 自訂）=m" \
  --promptString "git user.email=<email>" henry5720
```

參數說明見[新機器設定 2.3](new-machine-setup.md#23-一行指令裝好)。

不要用 `sudo chezmoi …`：以 root 執行、`$HOME` 又不屬於 root 時，chezmoi 一開頭就停，免得家目錄的檔案變成 root 擁有。

### chezmoi 怎麼判斷沒有 root

不用回答。本來就是 root、在 `sudo`／`admin`／`wheel` 群組（要密碼的照樣算，apply 時會問）、或 `sudo -n true`
成功，三條都不符才算沒有 root。

### 會自動處理什麼

| 項目 | 沒有 root 時怎麼做 |
|---|---|
| jq | 系統沒有就從 GitHub release 裝到 `~/.local/bin`；非 Debian 系 Linux 也一樣 |
| zsh（勾了才有） | 用 [zsh-bin](https://github.com/romkatv/zsh-bin)（5.8）裝到 `~/.local`；有 root、非 Debian 系也一樣 |
| bash 切 zsh | 不 `chsh`：`~/.bashrc` 最後加一段（`dotfiles:互動式 bash 切到 zsh` 標記之間），互動式 bash 一啟動就 `exec zsh`；`bash -c`、scp 這類非互動的留在 bash。要拿掉就刪那段、取消勾選 zsh |
| `~/.profile` | 沒有 `~/.profile`、`~/.bash_profile`、`~/.bash_login` 時補一個：把 `~/.local/bin` 加進 PATH、source `~/.bashrc`，讓 `bash -l` 開的終端機也找得到 chezmoi、也會切過去 |
| `TERM` | 沒設時 `.zshrc` 補成 `xterm-256color` |
| ssh client | 系統沒有 `ssh`（例：TeamSync 工作區）時，apt 不用 root 把 openssh-client 解到 `~/.local/opt/openssh`，`ssh`、`ssh-keygen`、`scp` 放在 `~/.local/bin`。系統已經有 `ssh` 就不補。只做 Debian 系；其他 Linux 沒有 `ssh` 請有 root 的人裝 |
| 有 root 時走 apt 或官方 `.deb` 的工具 | vim、ffmpeg、gh、code-server，與 Claude Code 讀 PDF 要的 `pdftoppm`，改用 [mise](https://mise.jdx.dev/) 裝到家目錄；非 Debian 系 Linux 也一樣 |
| tailscale（勾了才有） | 官方 static tarball 的 `tailscale`、`tailscaled` 裝到 `~/.local/bin`，狀態放 `~/.local/state/tailscale`；勾了 zsh 的話，之後開 zsh 時 tailscaled 沒在跑會自己背景起來 |

上表那幾個系統已經有的指令不交給 mise，不會重裝一份。清單在哪、怎麼更新、被 GitHub API 限流怎麼辦，見 [mise](mise.md)。

不用 root 的工具照常裝好，跟有 root 時一樣：eza、fzf、bat、ripgrep、starship、btop、fastfetch、ttyd 本來就由 mise 裝（#233），
Claude Code、Codex、OpenCode、herdr、WakaTime、agent-config 用各自的官方 installer。

### 略過彙整怎麼看

要 root 的步驟不會讓 apply 失敗：每一步印一行「略過什麼、手動怎麼做」，apply 最後在
`== 沒有 root,以下步驟已略過` 底下再彙整一次，整個 apply 照樣 exit 0。

| 彙整裡的項目 | 要做什麼 |
|---|---|
| 系統套件（基底的 git、curl、python3，與 libatomic1、Chrome 字型這類沒有 mise 替代的） | 請有 root 的人跑彙整裡那行 `sudo apt-get install` |
| tailscale | 只剩登入，見[第 2 步](#2-登入-tailscale)。下載失敗時這筆會寫原因與手動下載方式 |
| headless-chrome | 缺十幾個系統函式庫，只能請有 root 的人裝 |
| nvm 與 Node（勾了 `node` 或要 Node 的工具才有；codegraph、playwright-cli 跟著略過；opencode、wakatime 照裝，但要 node 的部分跑不起來） | 只在系統沒有 `libatomic.so.1` 時略過，請有 root 的人裝 `libatomic1` |
| ssh | 解不開 openssh-client 時才有，請有 root 的人裝 |

略過的步驟不會每次 apply 都重印；之後有了 root（或補上 `libatomic1`），下一次 `chezmoi apply` 會自己把它們跑一遍。

**沒勾 tailscale 就到此為止。** 下面只給要當 ssh client 連 tailnet 機器的人。

## 2. 登入 tailscale

系統的 tailscaled 已經在跑（例如管理員裝好的機器；`tailscale status` 是 Running，或 `systemctl is-active tailscaled`）時，
chezmoi 整段跳過、直接用系統那份，有沒有 root 都一樣、不會叫 sudo，這一步也不用做。

否則 tailscaled 走 userspace 模式：只給這個使用者用的 proxy，不用 root，有自己的 socket。

1. 起 tailscaled。勾了 zsh：開一個新的 zsh（或 `exec zsh`），沒在跑會自己背景起來，log 在
   `~/.local/state/tailscale/tailscaled.log`。沒勾 zsh：自己起，

   ```bash
   tailscaled --tun=userspace-networking --statedir=$HOME/.local/state/tailscale \
     --socket=$HOME/.local/state/tailscale/tailscaled.sock --port=0 &
   ```

2. 登入，打開印出的網址核准：

   ```bash
   tailscale --socket=$HOME/.local/state/tailscale/tailscaled.sock up
   ```

登入狀態在 `~/.local/state/tailscale`，不用重新登入。勾了 zsh 的話之後每次開 zsh 都會檢查、沒在跑就起來；
沒勾 zsh 就每次用之前照第 1 步起。要開機就起，用 systemd user service（要 `loginctl enable-linger`，通常要管理員）或 crontab 的 `@reboot`。

`~/.ssh/config` 的 `company-ec2` 會多一行 `ProxyCommand ~/.local/bin/tailscale --socket=… nc %h %p`，
登入之後 `ssh company-ec2` 就經 tailnet 連過去。其他 Host 不變。

## 3. 例子：連 company-ec2 的專用 key（一次性）

company-ec2 關了密碼登入，也沒開 Tailscale SSH，這台要一把 key。不要把 `henry5720` 或 AWS 發的 pem
複製過來：產一把這台專用的，外洩或不用了只要在 company-ec2 刪一行。

1. 在這台產 key。檔名用 `~/.ssh/company-henry.pem`：ssh config 的 `company-ec2` 寫死這個 IdentityFile。
   這把是這台自己的 key，跟其他機器上同名的 AWS pem 不是同一把：

   ```bash
   ssh-keygen -t ed25519 -N '' -C "teamsync-ws $(date +%F)" -f ~/.ssh/company-henry.pem
   cat ~/.ssh/company-henry.pem.pub
   ```

2. 在已經連得上 company-ec2 的機器，把那行公鑰加進 `authorized_keys`，前面加 `from=` 限定只能從 tailnet 連：

   ```bash
   ssh company-ec2 'cat >> ~/.ssh/authorized_keys'
   # 貼上一行:from="100.64.0.0/10" <第 1 步印出的公鑰>,換行後 Ctrl-D
   ```

3. 第一次連線核對主機指紋：在同一台已經連得上的機器跑下面這行，記下指紋；回這台 `ssh company-ec2`，
   問 `Are you sure you want to continue connecting` 時，畫面上的指紋一樣才打 `yes`：

   ```bash
   ssh company-ec2 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'
   ```

   沒勾 zsh 的機器先 `export TERM=xterm-256color` 再連：bash 沒有 export `TERM`，遠端 zsh 的行編輯會壞（字元重複）。

4. 撤銷：在 company-ec2 跑 `sed -i '/teamsync-ws/d' ~/.ssh/authorized_keys`。

## 字型（可選）

提示列（starship）的圖示變成方塊，不是 dotfiles 壞了：要改的是**你看畫面的那個終端機**的字型，跟 shell 在哪台機器無關。
各種終端機（Windows Terminal、瀏覽器、macOS、Linux 桌面）怎麼裝 Nerd Font，見[終端機字型](fonts.md)。

## 已知狀況

- `chezmoi status` 永遠有一行 ` R …zz-root-skipped-summary.sh`：略過彙整那支每次 apply 都要跑，不是沒套用完
- TeamSync 工作區的網頁終端機大約 15 分鐘沒動就斷線，按「重新連線」就好；tailscaled 沒在跑的話，開 zsh 時會自己起來
