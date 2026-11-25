# Oracle VPS：分清楚是哪個帳號的

Oracle 上有兩個帳號（tenancy），Always Free 額度各算各的。tenancy A 是我的，tenancy B 是別人的，不要動。
ssh config 的 Host 名不一定等於 OCI Console 上的 display name，每台叫什麼、在哪個帳號，寫在
[`home/private_dot_ssh/private_config.tmpl`](../../home/private_dot_ssh/private_config.tmpl)〈公網〉那節的註解。

## 判斷某台屬於哪個帳號

登進那台，問 instance metadata 的 `compartmentId`：

```bash
curl -sH "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/instance/ | jq -r .compartmentId
```

| 輸出裡有 | 帳號 |
|---|---|
| `z3lry3` | tenancy A（我的） |
| `7yh5zf` | tenancy B（別人的，不要動） |

出處：[OCI〈Getting Instance Metadata〉](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/gettingmetadata.htm)。

## 拿掉的 Host

- **oracle-2**（`129.159.185.160`）：在 tenancy B，是 2026-07-20 前的舊 hermes micro（Console 上叫 `instance-20260709-1122`）。
  不是我的，別終止它。
