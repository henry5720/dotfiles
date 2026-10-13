# eza、zoxide、zsh-z、bat、ripgrep、fzf 在各平台怎麼裝

> 研究紀錄，回答 #107（map #104）。查詢日期 2026-10-06，版本號都是當天的值，之後會過期。
> 這份是當時的事實，不是現況設定；採不採用由 map 決定。

## 結論

在 Linux（含 Ubuntu）上，五個 binary 一律抓 GitHub release 的 tarball 裝到 `~/.local/bin`。
原生 Termux 一律 `pkg install`；zsh-z 是純 zsh 插件，跟現有插件一樣用 `.chezmoiexternal` 的 `git-repo` clone。

不走 apt，原因有四個：

- 22.04 沒有 eza。
- 兩版 apt 的 fzf（0.29、0.44）都沒有 `fzf --zsh`（0.48 才加），也低於 zoxide `zi` 要的 0.51。
- zoxide 官方 README 劃掉了 Ubuntu／Debian，建議改用 install script。
- bat、fd 在 Ubuntu 上叫 `batcat`、`fdfind`，dotfiles 得多寫一層 alias。

ripgrep、bat 在 24.04 的 apt 版本其實夠用，但只為它們兩個多開一條 apt 路徑，不值得。

`z-shell/zsh-eza` 不用 zinit 時不值得用：它就是 8 個 alias（`ls`、`l`、`ll`、`llm`、`la`、`lx`、`lt`、`tree`），
外加一個選用的 `cd` 後自動列目錄 hook 和一個只有 zi 會呼叫的 unload 函式。eza 沒裝時它會往 stderr 印錯誤，
違反 repo「裝不到要安靜略過」的規則。在 `dot_zshrc` 自己寫幾行 alias，效果一樣，也少一個外部 repo。

## 總表

版本欄：Ubuntu 22.04（jammy）／24.04（noble）是 packages.ubuntu.com 上的版本，Termux 是 termux-packages 的 `TERMUX_PKG_VERSION`，upstream 是 GitHub latest release。

| 工具 | jammy apt | noble apt | Ubuntu 上的指令名 | 原生 Termux | upstream 最新 | Linux release 資產（x86_64／aarch64） | apt 太舊的影響 |
|---|---|---|---|---|---|---|---|
| eza | **沒有** | `eza` 0.18.2（universe） | `eza` | `pkg install eza`，0.23.5 | v0.23.5（2026-07-09） | `eza_x86_64-unknown-linux-musl.tar.gz`（也有 gnu）／`eza_aarch64-unknown-linux-gnu.tar.gz`（aarch64 只有 glibc 版，沒有 musl） | 22.04 裝不到。24.04 的 0.18.2 已有 `--icons=always`（0.15.0 加的），夠用 |
| zoxide | `zoxide` 0.4.3（2020-07） | `zoxide` 0.9.3 | `zoxide` | `pkg install zoxide`，0.10.0 | v0.10.0（2026-07-04） | 全部 musl：`zoxide-<ver>-x86_64-unknown-linux-musl.tar.gz`／`aarch64-unknown-linux-musl`；另有 `.deb` | 官方 README 把 Ubuntu／Debian 劃掉，註明「更新很慢，請改用 install script」。22.04 那版是 2020 年的 |
| zsh-z | 不是套件（noble 查無） | 同左 | `z`（zsh 函式） | termux-packages 沒有 | 只有 git repo | 不需要：純 zsh，`source zsh-z.plugin.zsh` | 不適用。Zsh 4.3.11 以上都能跑 |
| bat | `bat` 0.19.0 | `bat` 0.24.0 | **`batcat`**（兩版都是） | `pkg install bat`，0.26.1 | v0.26.1（2025-12-02） | `bat-v<ver>-x86_64-unknown-linux-musl.tar.gz`／`aarch64-unknown-linux-musl`；另有 `.deb` | 主要是指令名問題，上游建議 `ln -s /usr/bin/batcat ~/.local/bin/bat` |
| ripgrep | `ripgrep` 13.0.0 | `ripgrep` 14.1.0 | `rg` | `pkg install ripgrep`，15.2.0 | 15.2.0（2026-07-15） | `ripgrep-<ver>-x86_64-unknown-linux-musl.tar.gz`／`aarch64-unknown-linux-musl`；`.deb` 只出 amd64 | 日常搜尋沒差別，舊一點不影響 |
| fzf | `fzf` 0.29.0 | `fzf` 0.44.1 | `fzf` | `pkg install fzf`，0.74.4 | v0.74.4（2026-09-12） | `fzf-<ver>-linux_amd64.tar.gz`／`linux_arm64`（Go 靜態連結）；另有 `.deb` | **兩版都太舊**：`fzf --zsh` 從 0.48.0 才有，zoxide 要求 fzf ≥ 0.51.0 |
| （參考）fd | `fd-find` 8.3.1 | `fd-find` 9.0.0 | **`fdfind`** | `pkg install fd`，10.5.0 | — | — | 不在 #104 範圍，列出來只是因為它跟 bat 一樣有改名問題 |

非 Debian Linux：eza、zoxide、bat、ripgrep、fzf 在 Arch、Fedora、Alpine 等都有發行版套件（見各 README），
但套件名和指令要逐一對，而且 repo 選單本來就只在 Debian 系出現。用同一份 release tarball 最一致：
不需要 root、不依賴套件管理員，x86_64 和 aarch64 都有。唯一的例外是 eza 的 aarch64 只出 glibc 版，
在 musl 系統（Alpine aarch64）上跑不起來。

## 各工具細節

### eza

- 24.04：`eza` 0.18.2，在 universe。來源：<https://packages.ubuntu.com/noble/eza>
- 22.04：查無（"Package not available in this suite"）。來源：<https://packages.ubuntu.com/jammy/eza>
- 上游給 Debian／Ubuntu 的官方做法是第三方 apt 源 `deb.gierens.de`，要加 GPG key 和 `sources.list.d`。
  另外有 Manual (Linux) 一段：下載 tarball 放進 `/usr/local/bin`。
  來源：<https://github.com/eza-community/eza/blob/main/INSTALL.md>（"Debian and Ubuntu"、"Termux"、"Manual (Linux)" 三段）
- `--icons=always|auto|never` 是 0.15.0（2023-10-19）加的，同時拿掉了 `--no-icons`。
  來源：<https://github.com/eza-community/eza/blob/main/CHANGELOG.md>
- Termux：0.23.5，依賴 `libgit2`，會一起裝 zsh 補全 `_eza`。
  來源：<https://github.com/termux/termux-packages/blob/master/packages/eza/build.sh>
- Release 資產：aarch64 只有 `-gnu`（含 `_no_libgit` 版），x86_64 有 gnu 和 musl，32 位 ARM 有 `arm-unknown-linux-gnueabihf`。
  上游沒有出 `.deb`。來源：<https://github.com/eza-community/eza/releases/latest>

### zoxide

- 22.04 是 0.4.3（上游 2020-07-04 的版本），24.04 是 0.9.3。
  來源：<https://packages.ubuntu.com/jammy/zoxide>、<https://packages.ubuntu.com/noble/zoxide>
- 上游 README 的 Linux 安裝表把 Debian、Ubuntu、Raspbian、Parrot 劃掉，註腳 [^1] 寫：
  "Debian / Ubuntu derivatives update their packages very slowly. If you're using one of these distributions, consider using the install script instead."
  來源：<https://github.com/ajeetdsouza/zoxide/blob/main/README.md>（Installation → Linux / WSL）
- 官方 install script（`curl -sSfL .../install.sh | sh`）預設裝到 `~/.local/bin`，可以用 `--bin-dir` 改位置。
  它透過 GitHub API 找 release，被 API rate limit 擋到時會直接報錯。
  來源：<https://github.com/ajeetdsouza/zoxide/blob/main/install.sh>（`_ZOXIDE_BIN_DIR_DEFAULT`、rate limit 那段）
- shell 整合寫 `eval "$(zoxide init zsh)"`；`zi`（互動選目錄）要 fzf，"The minimum supported fzf version is v0.51.0."
  來源：同上 README 第 2、3 步
- Termux：0.10.0，會一起裝 zsh 補全。來源：<https://github.com/termux/termux-packages/blob/master/packages/zoxide/build.sh>
- Release 資產在 Linux 上全是 musl 靜態版，Android 另有 `aarch64-linux-android`。來源：<https://github.com/ajeetdsouza/zoxide/releases/latest>

### zsh-z

- 純 zsh 實作，不是 binary。在 `.zshrc` 寫 `source /path/to/zsh-z.plugin.zsh` 就能用；補全要 `compinit`，
  而且 `_zshz` 要跟 plugin 檔放在同一個目錄。資料庫預設是 `~/.z`，格式和 `rupa/z` 相同。支援 Zsh 4.3.11 以上。
  來源：<https://github.com/agkozak/zsh-z/blob/master/README.md>
- Ubuntu 和 Termux 都沒有打包（packages.ubuntu.com noble 查無；termux-packages 沒有 `packages/zsh-z`）。
  所以安裝方式跟 repo 現有的 p10k、zsh-autosuggestions 一樣：`home/.chezmoiexternal.toml.tmpl` 第 1 段的 `git-repo`。
  在 Termux 和非 Debian Linux 上不用另外處理。

### bat

- 22.04 是 0.19.0，24.04 是 0.24.0，**兩版的執行檔都叫 `/usr/bin/batcat`**。
  來源：<https://packages.ubuntu.com/jammy/amd64/bat/filelist>、<https://packages.ubuntu.com/noble/amd64/bat/filelist>
- 上游說明改名的原因是跟另一個套件撞名（sharkdp/bat#982），建議 `ln -s /usr/bin/batcat ~/.local/bin/bat` 或 `alias bat="batcat"`；
  也提供 `.deb` 下載。來源：<https://github.com/sharkdp/bat/blob/master/README.md>（"On Ubuntu (using apt)"、"using most recent .deb packages"）
- Termux：0.26.1，指令就叫 `bat`，依賴 `less`、`libgit2`。來源：<https://github.com/termux/termux-packages/blob/master/packages/bat/build.sh>
- Release 資產：gnu 和 musl 的 tarball 都有（x86_64、aarch64、arm、i686），`.deb` 有 amd64、arm64、armhf、i686。
  來源：<https://github.com/sharkdp/bat/releases/latest>

### ripgrep

- 22.04 是 13.0.0，24.04 是 14.1.0，指令都叫 `rg`。
  來源：<https://packages.ubuntu.com/jammy/ripgrep>、<https://packages.ubuntu.com/noble/ripgrep>
- 上游寫 Ubuntu 18.10 以上可以直接 `apt-get install ripgrep`，也提供 `.deb`。
  來源：<https://github.com/BurntSushi/ripgrep/blob/master/README.md>（Installation）
- Termux：15.2.0，依賴 `pcre2`。來源：<https://github.com/termux/termux-packages/blob/master/packages/ripgrep/build.sh>
- Release 資產：x86_64 只有 musl；aarch64 有 gnu 和 musl；`.deb` 只出 amd64。來源：<https://github.com/BurntSushi/ripgrep/releases/latest>

### fzf

- 22.04 是 0.29.0，24.04 是 0.44.1。shell 整合檔放在 `/usr/share/doc/fzf/examples/key-bindings.zsh` 和 `completion.zsh`。
  來源：<https://packages.ubuntu.com/noble/amd64/fzf/filelist>
- `fzf --zsh`（一行 `source <(fzf --zsh)` 載入 key binding 和補全）是 0.48.0 加的。更舊的版本要自己 source `shell/` 底下的檔案，
  而且「檔案位置看套件管理員」。來源：<https://github.com/junegunn/fzf/blob/master/CHANGELOG.md>（0.48.0）、
  <https://github.com/junegunn/fzf/blob/master/README.md>（Setting up shell integration 的 NOTE）
- 想關掉某個鍵：在 source 前把對應的 `*_COMMAND` 設成空字串，例如 `FZF_CTRL_R_COMMAND= source <(fzf --zsh)`。
  這跟 map #104 的「Not yet specified」直接相關：如果 deja 要拿走 Ctrl-R，就用這個方式關掉 fzf 的 Ctrl-R。
  來源：同上 README 的 TIP
- 上游的 git 安裝法（`git clone ~/.fzf && ~/.fzf/install`）會改 shell 設定檔，跟 chezmoi 管 `.zshrc` 衝突，不適用。
  來源：同上 README（"Using git"）
- Termux：0.74.4，shell 腳本放在 `$PREFIX/share/fzf/`。來源：<https://github.com/termux/termux-packages/blob/master/packages/fzf/build.sh>
- Release 資產：Go 靜態連結，`linux_amd64`、`linux_arm64`、`armv5-7` 等都有，也出 `.deb`。來源：<https://github.com/junegunn/fzf/releases/latest>

## `z-shell/zsh-eza` 做了什麼

來源：<https://github.com/z-shell/zsh-eza>（`zsh-eza.plugin.zsh`、`functions/_zsh_eza_init`、`docs/README.md`）

| 項目 | 內容 |
|---|---|
| alias | `ls` `l` `ll` `llm` `la` `lx` `lt` `tree`，全部是 `eza <旗標> ${_zsh_eza_params}` |
| 預設旗標 | `--git --icons --group --group-directories-first --time-style=long-iso --color-scale=all` |
| 設定 | `zstyle ':zsh-eza:config' user-params／extra-params`：取代或附加預設旗標 |
| 選用 hook | `zstyle ':zsh-eza:config' autocd yes`：每次 `cd` 後自動執行 eza（`chpwd` hook） |
| unload | `zsh-eza_plugin_unload` 會還原原本的 alias。只有 zi 的 `zi unload` 會呼叫它 |
| eza 沒裝時 | 往 stderr 印 `Please install eza before using this plugin.`，回傳 1，不定義 alias |
| `TERM=dumb` | 什麼都不做 |
| 安裝 | README 主推 `zi light z-shell/zsh-eza`，也說明可用 OMZ、zplug、antigen；不用插件管理器時直接 source `zsh-eza.plugin.zsh` |

不用 zinit 時：

- 插件真正多出來的東西，只有 unload 和 `zi ice has'eza'`（沒有 eza 就不載入）。前者只對 zi 有意義，後者也是 zi 的語法。
- 直接 source 時，沒有 eza 的機器每開一次 shell 就會印一行錯誤，得自己先包一層 `(( $+commands[eza] ))`。
- 它會蓋掉 `ls` 和 `tree`，而且預設帶 `--git`（每次 `ls` 都去讀 git 狀態）。
- 結論：不值得多一個外部 repo。在 `dot_zshrc` 寫 `(( $+commands[eza] )) && alias ls='eza --icons=always --group-directories-first' ...` 這幾行就夠了。

## 套進這個 repo 的做法

`home/.chezmoi.toml.tmpl` 選單上方的註解規定，不走 apt 的工具要自己寫一支 `run_onchange_after_install-<工具>.sh.tmpl`。
已經有兩個前例：

- `run_onchange_after_install-wakatime.sh.tmpl`：下載 release 檔，`install -m 755` 到 `~/.local/bin`。
- `run_onchange_after_install-fastfetch.sh.tmpl`：下載 release 的 `.deb`。

`home/dot_zshrc` 第 23 行已經把 `~/.local/bin` 加進 PATH。

另外要注意兩件事：

- 這些腳本開頭都是 `{{ if has "<工具>" .tools }}`（fastfetch、gh 另外加了 `is-debian`）。
  但選單只在 Debian 系出現，非 Debian Linux 的 `tools` 一定是空的，所以實際上一樣裝不到。
  如果要在非 Debian Linux 也裝這五個工具，不能沿用選裝選單，得另外決定（例如當成預設工具，按 `.chezmoi.os` 分支）。
- 原生 Termux 把套件名加進 `home/.chezmoidata/packages.yaml` 的 `packages.termux` 就好，五個工具都在官方 repo。
