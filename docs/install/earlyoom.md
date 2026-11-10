# earlyoom：agent 吃滿記憶體時，ssh 還連得上

平行的 agent 同時跑 tsc、vitest、vite build，記憶體和 swap 一起被吃滿，整台卡到 ssh 都連不上（#298）。
勾選裝工具 `earlyoom` 後，這台會照下表決定搶資源時誰先被擠，記憶體快滿時在卡死之前砍掉最肥的程序。
名詞見 [GLOSSARY](../../GLOSSARY.md)「裝機」段。

| 程序 | 包含 | 搶資源時 |
|---|---|---|
| 保留服務 | ssh、tailscale、ssm-agent、journald、dbus | 記憶體不被回收；CPU 拿 10 倍份量；earlyoom 不砍 |
| 常駐服務 | 保留服務以外、一直開著的服務，含 docker container（例如 company agent） | 工作程序被回收完才輪到；CPU 拿 10 倍份量 |
| 工作程序 | agent、tsc、vitest、VS Code server、codegraph | 最先被回收；快滿時 earlyoom 從最肥的砍 |

```text
記憶體開始不夠
  ├─ 1. kernel 回收（換到 swap）：工作程序 → 常駐服務超過保護量的部分；保留服務的保底量永遠不拿
  └─ 2. 可用記憶體 <5% 且 swap <10%：earlyoom 砍 oom_score 最高的程序（保留服務不砍）
```

只在 Debian 系、有 systemd 的 Linux 裝得了；用途 full 預設勾。沒有 root 的機器 apply 時略過，記進略過彙整。

## 為什麼是保護保留服務與常駐服務，不是限制 agent

平常工作程序想用多少就用多少，搶的時候才讓位。限制 agent（`MemoryMax`、`CPUQuota`）的話，資源空著時 agent 也用不到，
而且 herdr server 要重啟才進得了限制的 slice。

不採用的其他做法：

- **systemd-oomd**：一次砍整個 cgroup；所有 agent 在同一個 session scope，等於全砍。
- **earlyoom `--prefer node`**：tsc、vitest、VS Code、codegraph、company agent 的程序名稱都是 `node`／`MainThread`，
  claude 是版本號（例如 `2.1.322`），挑不出來。用預設（最大的先砍）就好，實際上最肥的通常就是 tsc。
- **只保護整個 `system.slice`**：保護量照用量比例分給底下的程序，docker 用得多就拿走大部分，sshd 分到的不夠。
  所以保留服務各自另設保底。
- **常駐服務放進 earlyoom 的避開清單**：container 裡的程序名稱也是 `node`、`codex`，避開它等於 agent 也避開。

## 數字怎麼來

數字都在 [`home/.chezmoidata/earlyoom.yaml`](../../home/.chezmoidata/earlyoom.yaml)，每台共用一份。

| 設定 | 值 | 為什麼 |
|---|---|---|
| 保留服務的保底量 | 512M（固定量） | 保留服務用量不隨機器變大（30G 的機器實測合計約 220M），抓兩倍。用百分比在 1G 機器保不住，在大機器又讓漏記憶體的服務長大不被回收 |
| 常駐服務的保護量 | 15%（百分比） | container 的用量跟著機器變大 |
| CPUWeight | 1000（預設 100） | 搶 CPU 時拿到工作程序的 10 倍；不搶時工作程序照用滿 |
| earlyoom 門檻 | `-m 5 -s 10` | 常見的伺服器設定：可用記憶體 ≤5% 且 swap 剩 ≤10% 送 SIGTERM，一半時送 SIGKILL |

參考：Meta 把 sshd、journald、dbus 放在保底記憶體的 slice
（[resctl-demo](https://facebookmicrosites.github.io/resctl-demo-website/docs/demo_docs/res_protection/memory)、
[cgroup2 memory strategies](https://facebookmicrosites.github.io/cgroup2/docs/memory-strategies.html)）；
[earlyoom](https://github.com/rfjakob/earlyoom)。

改 yaml 後 `chezmoi apply` 就會重寫設定並套上，不重啟 ssh、tailscale、docker、herdr。
拿掉清單上的 unit，下次 apply 會收掉它的設定。

## 寫了哪些檔

都在 `/etc`，由 `run_onchange_after_install-earlyoom` 用 sudo 寫：

```text
/etc/systemd/system/system.slice.d/50-earlyoom.conf   常駐服務的保護量、保留服務的保底量、CPUWeight
/etc/systemd/system/<保留服務>.d/50-earlyoom.conf     MemoryMin=infinity、CPUWeight（總量受上面的保底量限制）
/etc/default/earlyoom                                 EARLYOOM_ARGS：門檻與避開清單
```

`tailscaled-.service.d` 是前綴 drop-in，`tailscaled-preview.service` 這類 `tailscaled-*` 也套到。
`/etc/default/earlyoom` 是套件的設定檔：哪天 earlyoom 套件升級也改了它，`apt upgrade` 會問要留哪一份，選留現在的，再 `chezmoi apply`。

沒有 root 的機器要請管理員照上面寫好，再 `sudo systemctl daemon-reload && sudo systemctl enable --now earlyoom`。

容器裡 systemd 沒在跑：設定照寫，不啟用，開機後才生效。

取消勾選不會拿掉這些設定（選裝工具都不解除安裝）。要拿掉：

```bash
sudo rm /etc/systemd/system/*.d/50-earlyoom.conf
sudo systemctl daemon-reload
sudo systemctl disable --now earlyoom
```

保留服務的保底量是大家共用的：清單上某個服務漏記憶體長大時，會跟其他保留服務照用量比例分這 512M，ssh 分到的跟著變少。
真的遇到再給那個 unit 另設 `MemoryMax`。

## 怎麼確認生效

```bash
systemctl show system.slice -p MemoryMin -p MemoryLow -p CPUWeight   # 512M、15% 換算的值、1000
systemctl show ssh.service -p MemoryMin -p CPUWeight                 # infinity、1000
systemctl is-active earlyoom                                         # active
journalctl -u earlyoom -n 10                                         # 開頭印出門檻與避開清單
```

## earlyoom 砍了誰

```bash
journalctl -u earlyoom | grep -i -E 'sending|killed'
```

被砍的通常是最肥的工作程序（tsc、vitest），重跑就好。container 裡的程序也可能被砍（不在避開清單），
被砍了就重開那個 container；常駐服務要固定的上限，自己給 container 設 `--memory`。
