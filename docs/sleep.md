# Sleep

## Suspend works without any extra fixes

Omarchy's T2 setup (`/etc/limine-entry-tool.d/t2-mac.conf`) boots with
`intel_iommu=on iommu=pt pm_async=off mem_sleep_default=deep`, and on
`linux-t2` deep S3 suspend works:

- With the stock driver there were 11 suspends between 2026-10-22 and
  2026-10-24, and 9 returned. The two without a `suspend exit` in the log were
  both on 2026-10-22, the day of the install, while the system was still being
  set up; the cause is unknown. All six suspends since 2026-10-23 returned, the
  longest after about 20 hours.
- With the 5K patch, standby also returned cleanly. Both tiles were healthy
  again about three seconds after resume (`APPLE5K: link-health PASS ... 0 recovery attempts`).
  Wi-Fi reconnected and the T2 audio driver resumed.

## The first wake of a boot waited a minute for Thunderbolt

The iMac Pro has two Thunderbolt 3 controllers (Alpine Ridge, behind the CPU
root ports `05:02.0` and `05:03.0`). During deep sleep the firmware powers
both down, and they do not come back: after wake their config space reads as
all ones (`lspci` shows `Unknown header type 7f`), the Thunderbolt driver logs
a dozen `tb_cfg_read: -108` warnings, and the USB-C ports stay dead until the
next boot.

On the first resume of a boot, Linux also waits for them: the kernel log
shows a gap of 29.7 s before `pcieport 0000:06:00.0: Unable to change power
state from D3cold to D0` and another 29.7 s before the same line for
`0000:4c:00.0`. Measured from the kernel's own timestamps, which stop during
sleep, from `ACPI: PM: Low-level resume complete` to `PM: suspend exit`:

| Resume | Kernel resume time |
|---|---|
| First of a boot, 4 cycles 2026-10-23 to 2026-10-26 | 66.9 to 67.6 s, of that 59.4 s in the two waits |
| Second of a boot, 2 cycles | 5.5 and 5.6 s |

The second resume is fast because the controllers were already dead when
Linux suspended them again. Only when Linux puts a live controller to sleep
does the wake wait for it, so a controller that is no longer on the PCI bus
is never waited for.

`./install.sh sleep` installs `imacpro-tb-sleep.service`
([unit](../config/etc/systemd/system/imacpro-tb-sleep.service),
[script](../config/usr/local/bin/imacpro-tb-sleep)). Before every sleep it
removes both controllers' PCI subtrees (`echo 1 > .../remove` on each
upstream port, after a `sync`). After wake it rescans the PCI bus, which
brings them back if the firmware powered them up again and costs nothing if
it did not. USB-C devices on the Thunderbolt ports were lost on wake before
and still are; a disk there should be unmounted before sleep.
`./install.sh sleep-stock` removes the hook. `./check.sh` shows how long the
last wake took.

## ACPI interrupt storm after the first wake

After the same resume, GPE 13 fires about 380 times a second
(`/sys/firmware/acpi/interrupts/gpe13`) and a `kworker/0:*+kacpid` thread
keeps one core at 95 %, which also raises the fan speed. It started with the
first resume and lasts until reboot. `./check.sh` warns about it.

## Not used: `imac-patcher --apply t2suspend`

The upstream patcher's `t2suspend` module is marked "not tested on T2 hardware".
It also masks hibernate and, on Omarchy, removes the hibernation setup
(`omarchy-hibernation-remove`). Suspend already works without it.

## Hibernate

Omarchy sets hibernation up: a 31 GB swap file plus `resume=` and
`resume_offset=` on the kernel command line. It has never been tried on this
machine, and it is untested with the 5K patch. On the 2017 iMac (iMac18,3) the
upstream project reports that hibernate hard-hangs. On a desktop that suspends
reliably you can ignore it.

## Tried and disabled

`/etc/limine-darwin.conf.disabled` contains `acpi_osi=Darwin`. It was an
attempt to let Apple's firmware use its macOS Thunderbolt power paths. It is
disabled and not part of this setup.
