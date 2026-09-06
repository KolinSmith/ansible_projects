# sd_card_longevity

Cuts writes to an SD-booted SBC so the card lasts longer. Deliberately a
**safe subset** — it does not rewrite the root `/etc/fstab` line.

## What it does

1. **Disables Raspbian's `dphys-swapfile`** (swap file on the card).
2. **Installs `zram-tools`** and configures compressed swap in RAM
   (`/etc/default/zramswap`) — an OOM safety net with zero card writes.
3. **Mounts `tmpfs` on `/tmp` and `/var/tmp`** so temp writes stay in RAM.

## Not done (on purpose)

- Root mount options — RPi OS Bookworm already mounts `/` with `noatime`.
  Add `commit=600` by hand if you want writes batched harder.
- `log2ram` / ramlog — the homelab convention is to leave logs on disk
  (`orangepi_disable_ramlog`); with a light workload the writes are small.

## Variables

See `defaults/main.yml` — zram percent/algo/priority, the tmpfs path list,
and toggles for each piece.
