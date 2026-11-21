# 開 sshd：讓別台 ssh 進來

服務卡：要讓別台 ssh 進這台時，這台要先有 sshd 在跑。照平台查暫時開／關、常駐、公鑰放哪。

| 項目 | 內容 |
|---|---|
| 服務 | sshd；Linux、Windows、macOS 聽 22，Termux 聽 8022 |
| 連線 | 一律走 tailnet，不開到公網，見 [remote-access〈判準〉](README.md#判準) |
| 操作者 | 人（terminal、VS Code Remote-SSH）或 agent（ssh 指令、`ssh -R` 轉發） |
| 用完收什麼 | 只是臨時讓人連進來的話，照下表「關」那欄關掉 |

## 總覽

| 平台 | 暫時開 | 關 | 常駐 | port |
|---|---|---|---|---|
| [Linux（有 root）](#linux有-root) | `sudo systemctl start ssh` | `sudo systemctl stop ssh.socket ssh.service` | 裝好預設就常駐 | 22 |
| [Linux（沒有 root）](#linux沒有-root) | `/usr/sbin/sshd -D -f ~/.sshd/sshd_config` | Ctrl+C | 要管理員 | 自選 ≥ 1024 |
| [Termux](#termux) | `sshd` | `pkill sshd` | Termux:Boot | 8022 |
| [Windows](#windows) | `Start-Service sshd` | `Stop-Service sshd` | `Set-Service -Name sshd -StartupType 'Automatic'` | 22 |
| [macOS](#macos) | 系統設定 → 一般 → 共享 → 遠端登入 | 同一處關掉 | 開了就常駐 | 22 |

公鑰放哪、權限怎麼設見[公鑰放哪、權限](#公鑰放哪權限)。連的那一方的 `~/.ssh/config` 要寫對 `User` 和 `Port`，見 [`home/private_dot_ssh/private_config.tmpl`](../../home/private_dot_ssh/private_config.tmpl)。

## 公鑰放哪、權限

權限不對時 sshd 不讀那個檔，連線只會回 `Permission denied (publickey)`。

| 被連的那台 | 公鑰放哪 | 權限 |
|---|---|---|
| Linux、macOS、Termux | `~/.ssh/authorized_keys` | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` |
| Windows，管理員帳號（Administrators 群組） | `C:\ProgramData\ssh\administrators_authorized_keys`，放使用者目錄的不會被讀 | 系統管理員 PowerShell：`icacls.exe "$env:ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"` |
| Windows，一般帳號 | `C:\Users\<使用者>\.ssh\authorized_keys` | 預設就對 |

Windows 帳號是不是管理員：`net localgroup administrators` 的清單裡有沒有它。
`icacls` 回找不到 `Administrators` 時換成 SID `*S-1-5-32-544`（2026-11-20 繁中 Windows 11 用 `Administrators` 可以）。

## Linux（有 root）

Debian、Ubuntu 的服務叫 `ssh`，沒裝先 `sudo apt install openssh-server`。

```bash
sudo systemctl start ssh                        # 暫時開
sudo systemctl stop ssh.socket ssh.service      # 關（只停 ssh.service 的話，下一條連線又會把它叫起來）
sudo systemctl enable --now ssh.socket          # 常駐（Ubuntu 22.10 之後，裝好就是這樣）
systemctl status ssh                            # 確認在跑
ss -ltn 'sport = :22'                           # 確認在聽 22
```

- **Ubuntu 22.10 之後是 socket activation**：常駐的是 `ssh.socket`，有連線進來才起 `ssh.service`，
  所以 `ssh.service` 顯示 `disabled` 是正常的。不是 Ubuntu 的 Debian 系照舊 `sudo systemctl enable --now ssh`。
- 公鑰：`ssh-copy-id <使用者>@<這台>`，或照[公鑰放哪、權限](#公鑰放哪權限)手動加。
- 改了 `/etc/ssh/sshd_config` 先 `sudo sshd -t` 檢查，再 `sudo systemctl restart ssh`。

出處：[Ubuntu Server〈OpenSSH server〉](https://ubuntu.com/server/docs/how-to/security/openssh-server/)、
[sshd now uses socket-based activation](https://discourse.ubuntu.com/t/sshd-now-uses-socket-based-activation-ubuntu-22-10-and-later/30189)。

## Linux（沒有 root）

沒有 sudo 也能用一般權限跑一支自己的 sshd，只是：只能登入成自己、port 要 ≥ 1024、host key 要自己產（系統那份只有 root 讀得到）。

```bash
mkdir -m 700 -p ~/.sshd
ssh-keygen -q -t ed25519 -N '' -f ~/.sshd/ssh_host_ed25519_key
cat > ~/.sshd/sshd_config <<EOF
Port 2222
HostKey $HOME/.sshd/ssh_host_ed25519_key
PidFile $HOME/.sshd/sshd.pid
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF

/usr/sbin/sshd -t -f ~/.sshd/sshd_config        # 檢查設定
/usr/sbin/sshd -D -e -f ~/.sshd/sshd_config     # 前景跑、log 印在終端機；Ctrl+C 關
ss -ltn 'sport = :2222'                         # 另一個終端機確認在聽
```

- **sshd 要用絕對路徑叫**：打 `sshd` 會直接結束，印 `sshd requires execution with an absolute path`。
- **`-f` 一定要給**：預設讀 `/etc/ssh/sshd_config`，裡面的 host key 你讀不到。也可以在指令上用 `-h <host key>`、`-p <port>` 蓋掉。
- **公鑰所在的目錄不能讓別人寫**：sshd 會拒絕（log 印 `bad ownership or modes for directory`），用預設的 `~/.ssh/authorized_keys` 就好。
- 常駐（開機自己起）要管理員裝成系統服務；沒有的話就開在 tmux／herdr 的 pane 裡。

出處：[sshd(8)](https://man.openbsd.org/sshd)（`-D`、`-e`、`-f`、`-h`、`-p`、`-t`）、[sshd_config(5)](https://man.openbsd.org/sshd_config)。

## Termux

裝 openssh（`pkg install openssh`，chezmoi 的 Termux [基底](../../GLOSSARY.md#裝機)已經含）後：

```bash
sshd                     # 開，聽 8022（非 root 綁不了 22）
pkill sshd               # 關
pgrep sshd               # 確認在跑
whoami                   # 連的那一方 ssh config 的 User，形如 u0_aXXX
logcat -s 'sshd:*'       # 連不上時看 log
```

- **不會自己開機啟動**，Termux 被關掉後要再跑一次。要常駐：從 F-Droid 裝 [Termux:Boot](https://github.com/termux/termux-boot)，
  打開一次 app，再建 `~/.termux/boot/start-sshd`：

  ```sh
  #!/data/data/com.termux/files/usr/bin/sh
  termux-wake-lock
  sshd
  ```

  Termux:Boot 要跟 Termux 本體同一個來源（同一把簽章）。
- 公鑰：加進 `~/.ssh/authorized_keys`。原生 Termux 上 chezmoi apply 會把 `~/.ssh/henry5720.pub` 自動加進去
  （[`run_onchange_after_termux-authorized-keys`](../../home/.chezmoiscripts/run_onchange_after_termux-authorized-keys.sh.tmpl)）。

出處：[Termux Wiki〈Remote Access〉](https://wiki.termux.com/wiki/Remote_Access)、[termux-boot README](https://github.com/termux/termux-boot#how-to-use)。

## Windows

Windows 10 1809、Server 2019 以後內建的 OpenSSH Server。以下都在**系統管理員**的 PowerShell 跑：

```powershell
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*'   # 看裝了沒
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0       # 沒裝就裝（Server 2025 預設已裝）

Start-Service sshd                                    # 暫時開
Stop-Service sshd                                     # 關
Set-Service -Name sshd -StartupType 'Automatic'       # 常駐
Get-Service sshd                                      # 確認：Status 是 Running
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'     # 確認防火牆有放 22（安裝時自動建）
```

公鑰放哪、權限見[公鑰放哪、權限](#公鑰放哪權限)。

出處：[Get started with OpenSSH Server for Windows](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)、
[Key-based authentication in OpenSSH for Windows](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement)。

## macOS

1. 蘋果選單 → 系統設定 → 一般 → 共享，點「遠端登入」旁的資訊按鈕，打開「遠端登入」。
2. 允許取用的選單選「所有使用者」，或「只限這些使用者」再加帳號。
3. 確認：同一個畫面「遠端登入：開啟」下方會顯示要打的 `ssh <使用者>@<主機>`。

- 開了就常駐，重開機也在；關掉一樣在這裡。
- 聽 22，公鑰加進 `~/.ssh/authorized_keys`（OpenSSH 預設，見 [sshd(8)〈AUTHORIZED_KEYS FILE FORMAT〉](https://man.openbsd.org/sshd#AUTHORIZED_KEYS_FILE_FORMAT)）。

出處：[Apple 支援〈允許遠端電腦取用你的 Mac〉](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac)。
