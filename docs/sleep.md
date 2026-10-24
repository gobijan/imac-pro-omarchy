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

## Thunderbolt warnings on resume

After sleeps longer than about a minute, the Thunderbolt driver logs about a
dozen warnings on wake:

```text
WARNING: drivers/thunderbolt/ctl.c:1130 at tb_cfg_read ... tb_cfg_read: -108
```

They appear with the stock `amdgpu` too, so they are not caused by the 5K
patch. Most likely the firmware powers the controller down during longer
sleeps. The Thunderbolt domains come back after resume. If a Thunderbolt device
ever stops working after wake, the place to start is a sleep hook that unbinds
the NHI before suspend and rebinds it after. The upstream patcher's `t2suspend`
module contains such a hook.

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
