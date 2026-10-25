# Fans

## What Omarchy sets up

Omarchy installs `t2fanrd` and writes `/etc/t2fand.conf`: a linear curve from
55 °C to 75 °C for both fans, from 1100 to 2500 rpm. t2fanrd takes both ends
from the SMC (`fan*_min`, `fan*_max`), so at idle, with the CPU at about 40 °C,
the fans never go below 1100 rpm. Tuning the curve only changes how they behave
under load.

## The SMC minimum is fixed, lower speeds are not

The fans live under `/sys/bus/acpi/devices/APP0001:00/`. The SMC rejects writes
to `fan*_min` with `Input/output error`. In manual mode
(`fan*_manual=1`) it does accept a lower `fan*_output`:

- At 800 rpm both fans ran steadily (811 and 781 rpm read back) and were
  clearly quieter.
- In the first minutes at 800 rpm the CPU package went from 40 to 45 °C and the
  GPU edge from 34 to 37 °C, far below the curve's 55 °C start.

800 rpm is below Apple's own floor. The curve above 55 °C is unchanged, and
when t2fanrd stops it hands the fans back to the SMC (`fan*_manual=0`).

## t2fanrd-quiet

Stock t2fanrd has no setting for the floor. `./install.sh fans` builds
upstream t2fanrd at `48baf96` with
[`patches/t2fanrd-quiet.patch`](../patches/t2fanrd-quiet.patch):

- **`min_speed`** per fan replaces the SMC minimum. Without it, the daemon
  behaves as before.
- **Its own config**, `/etc/t2fand-quiet.conf`
  ([`config/etc/t2fand-quiet.conf`](../config/etc/t2fand-quiet.conf):
  Omarchy's curve plus `min_speed=800`). Omarchy's `/etc/t2fand.conf` stays
  as Omarchy wrote it and no longer matters.
- **GPU temperature.** Upstream reads only `/sys/class/drm/card0`. On the iMac
  Pro the Radeon Pro Vega is `card1`, so the fans followed only the CPU. The
  patch reads the first `card[0-9]` with a temperature sensor, and the fans
  follow whichever of CPU package and GPU edge is hotter.
- **Resume.** The SMC returns to automatic control after suspend
  (`fan*_manual=0`). Upstream sets manual mode only at startup, so after the
  first suspend the SMC ran the fans on its own until the next boot. The patch
  sets manual mode with every speed write and writes at least every 30 s.

## Updates leave it alone

Nothing of this is in a pacman package, so there is nothing for an update to
replace or conflict with:

| File | Why updates don't touch it |
|---|---|
| `/usr/local/bin/t2fanrd-quiet` | pacman never installs to `/usr/local` |
| `/etc/systemd/system/t2fanrd.service` | overrides the unit in Omarchy's `t2fanrd` package under the same name, so the service stays enabled and Omarchy's `systemctl` calls reach the quiet build |
| `/etc/t2fand-quiet.conf` | Omarchy only knows `/etc/t2fand.conf` |

Omarchy's `t2fanrd` package stays installed and updates as usual; its binary
just isn't started. `./check.sh` shows whether the quiet build is the one
running. If it ever isn't, `./install.sh fans` puts it back; running it again
is harmless.

```bash
./install.sh fans
```

To go back to the stock daemon:

```bash
sudo rm /etc/systemd/system/t2fanrd.service /usr/local/bin/t2fanrd-quiet /etc/t2fand-quiet.conf
sudo systemctl daemon-reload
sudo systemctl restart t2fanrd
```
