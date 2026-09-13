# 沒有 sudo 的機器怎麼套 dotfiles

適用於「**你不是那台機器的管理員**」的帳號 —— 別人的機器分你一個 user,能 SSH 進去,
但不能裝套件。手上的例子是 `nettop`(`.ssh/config` 裡的 Tailscale 節點):

```
$ ssh nettop 'uname -a; id; getent group wheel'
Linux nettop 7.1.5-201.fc44.x86_64          # Fedora Linux 44 (KDE Plasma)
uid=1001(henry) groups=henry,incus,docker,guest,share
wheel:x:10:alan                              # root 是 alan,henry 不在 wheel
```

沒有腳本,**手動貼**。這種機器一台一台狀況都不同,寫成腳本反而要維護一份沒法在目標機器上測的東西。

## 為什麼 `script/ubuntu/*.sh` 在這裡不能用

兩個獨立的原因,缺一個都跑不起來:

1. **那些腳本只寫給 apt + snap。** `install-base.sh:12` 第一行就是 `sudo apt update`,
   Fedora 上直接 command not found。`install-base.sh:23` 的 `snap install chezmoi` 同理。
2. **套件安裝那段全要 root。** `install-base.sh` 的 12、13、23、43 行和 `install-tools.sh`
   的 23、30-31、64-65 行都是 `sudo`。`sudo -n true` 在 nettop 回 `a password is required`。

真正的好消息是:這類機器通常已經被管理員裝好常用工具了,根本不用裝。nettop 上
`zsh`、`git`、`curl`、`chezmoi`、`ffmpeg`、`btop`、`fastfetch` 全都在 `/usr/bin`。

## 先確認前置

```bash
for c in zsh git chezmoi; do printf "%-10s %s\n" "$c" "$(command -v $c || echo '缺')"; done
```

三個都有就往下做。**`zsh` 缺的話這條線就到此為止** —— 見最後一節。

## 貼這幾行

```bash
# 1. zsh 插件(~/.zshrc 讀 $HOME/.config/zsh,見 home/dot_zshrc)
mkdir -p ~/.config/zsh
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git        ~/.config/zsh/powerlevel10k
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions    ~/.config/zsh/zsh-autosuggestions
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.config/zsh/zsh-syntax-highlighting

# 2. 初始化並預覽 dotfiles(走 https,客人帳號沒有你的 SSH key)
chezmoi init https://github.com/henry5720/dotfiles.git
chezmoi diff
chezmoi apply

# 3. 預設 shell 換 zsh —— 改自己的帳號不需要 sudo
chsh -s "$(command -v zsh)"
```

第 2 步會依 `home/.chezmoi.toml.tmpl` 的 `promptStringOnce` 詢問尚未保存的值,不是每次
都問。欄位分成 3 個憑證(`code-server 密碼`、`codex-lb API key`、可留空的
`Context7 API key`)與 2 個 Git 身分(`git user.name` 預設 `henry`、`git user.email`)。
不信任或多人共用的機器不要填入真實憑證；缺少憑證的服務不能視為可用。值存在
`~/.config/chezmoi/chezmoi.toml`,不進 repo。

## `chsh` 失敗的退路

`chsh` 要輸入**自己的密碼**。純金鑰登入、從沒設過密碼的帳號會過不了,
訊息是 `PAM: Authentication failure`。這時不要找管理員,改成讓 bash 自己接手:

```bash
grep -q 'exec zsh' ~/.bashrc || echo '[ -z "$ZSH_VERSION" ] && exec zsh -l' >> ~/.bashrc
```

`grep -q` 是為了重跑不會累積成好幾行。`[ -z "$ZSH_VERSION" ]` 防遞迴。

## 什麼東西沒 root 也裝得起來

只有在工具真的缺、又非要不可時才走這條。裝到 `~/.local/bin`
(`home/dot_zshrc:23` 已經把它加進 PATH,不用再改)。

以下清單只是這台觀測到的情況,不是所有沒有 sudo 的機器都保證相同:

| 工具 | 沒 root 可行嗎 |
|---|---|
| nvm | 可,本來就裝在 `~/.nvm`,`install-tools.sh` 那段直接抄 |
| code-server | 可,`curl -fsSL https://code-server.dev/install.sh \| sh -s -- --method=standalone --prefix=~/.local` |
| btop / ffmpeg | 可,抓上游 static tarball 解到 `~/.local/bin` |
| fastfetch | 勉強,上游只發 `.deb`,要 `dpkg-deb -x` 拆出來,非 Debian 系還可能缺 lib |
| **zsh** | **不行**,上游沒有 static build,要自己編 |

所以這份文件救不了「連 zsh 都沒有」的機器 —— 而 zsh 是整份 dotfiles 的前提。
遇到那種只能去跟管理員要 `dnf install zsh`(或 apt),或者接受在那台就用 bash。
