# Power profile, turbo and clock floor

## What Omarchy sets up

At every login Omarchy's autostart runs `omarchy-powerprofiles-init`, which
calls `omarchy-powerprofiles-set autodetect`. On AC it restores the profile
saved in `~/.local/state/omarchy/powerprofiles/ac`. With nothing saved it picks
`performance`. The iMac Pro is always on AC, so it runs `performance` unless a
profile was picked in Omarchy's power panel. A plain `powerprofilesctl set`
saves nothing and lasts only until the next login.

`performance` sets the energy-performance preference (EPP) of `intel_pstate`
to `performance`, so the Xeon W jumps to high clocks at the slightest load.
`balanced` sets `balance_performance`: the CPU still turbos to 4.2 GHz under
load, but ramps up less eagerly.

## Measured

Idle desktop, both profiles alternated twice in 24 s blocks, sampled every 3 s.
The whole-machine figure is the SMC's `PSTR`, measured after the power supply;
the wall adds roughly 10 %. The CPU package figure is RAPL.

| | performance | balanced |
|---|---|---|
| Whole machine (SMC `PSTR`) | 129 W | 123 W |
| CPU package (RAPL) | 42 W | 36 W |
| CPU package temperature | 56 °C | 54 °C |
| Fans | 850 rpm, bursts to 1050 | 800 rpm |

With `performance` the package sits just above 55 °C, where the fan curve
starts ([fans.md](fans.md)), so short bursts of work lift the fans. With
`balanced` it stays below and the fans stay at their 800 rpm floor. During a
parallel test suite (six Ruby workers and Postgres) the machine was noticeably
quieter with `balanced`. Power there was not compared at equal work.

## Setting it

```bash
./install.sh power
```

This runs `omarchy-powerprofiles-set ac balanced`, the same as picking
Balanced in Omarchy's power panel. Omarchy restores it at every login, and its
updates keep it: the state file is yours, and the migration that touches power
profiles only re-applies the saved one. Picking another profile in the panel
replaces it; `./install.sh power` puts `balanced` back. `./check.sh` shows both
the active and the saved profile.

## Turbo off

`balanced` still lets the CPU turbo. The 8-core W-2140B has a base clock of
3.2 GHz and turbos to 4.2 GHz on one core and, in the test below, 3.9 GHz on
all of them. The firmware sets the package's long-term power limit (RAPL
`long_term`) to 200 W, above the chip's 120 W TDP, so under load turbo never
lets up. The package temperature follows the load within seconds, and the
fans follow the package.

`./install.sh cpu` turns turbo off. It writes `1` to
`/sys/devices/system/cpu/intel_pstate/no_turbo` and installs
[`/etc/tmpfiles.d/imacpro-cpu.conf`](../config/etc/tmpfiles.d/imacpro-cpu.conf),
which writes it again at every boot. The CPU then runs at most at its base
clock. The power profile still decides how eagerly it gets there, and at idle
it still drops to 1.2 GHz, unless the [clock floor](#clock-floor) is set. No
package owns the file, so updates leave it alone.

### Measured

All 16 threads busy (`openssl speed -multi 16 -bytes 16384 sha256`), with
clock, package temperature and fans sampled every 3 s. During the turbo run
other work was running as well, so this compares heat, not throughput. In both
runs the package temperature levelled off within half a minute.

| | turbo | turbo off |
|---|---|---|
| Clock, all cores | 3.9 GHz | 3.2 GHz |
| CPU package temperature | 84 to 87 °C | 67 to 69 °C |
| Fans | 2500 rpm, their maximum | 1800 to 1920 rpm |

Under full load the fans still rise, but stay well below full speed. The cost
is speed under load: going by the clocks, up to 18 % on all cores (3.9 to
3.2 GHz) and 24 % on one (4.2 to 3.2 GHz).

`powerprofilesctl` may list `performance` as degraded
(`high-operating-temperature`): power-profiles-daemon reads `no_turbo=1` as
the firmware throttling a hot CPU. Nothing else follows from it.

Not yet tested across sleep. `./check.sh` shows whether turbo is off, now and
from boot.

## Clock floor

With `balanced` the CPU drops to 1.2 GHz when it has little to do. From that
clock Hyprland loses frames when a window opens, and the animation stutters
right at its start.

The animation itself is not the problem. With windows that hold a tiny
buffer, and with windows that render on the GPU and hand over a GPU buffer
(mpv), Hyprland lost no frame in any run. foot renders on the CPU and hands
over each new picture as a memory buffer, which Hyprland copies to the GPU
before it draws the next frame. At 5120×2880 a full-screen window is 56 MB.
A new window brings one such buffer, and every window that changes size to
make room brings another. At the idle clock Hyprland does not get that done
within the 16.7 ms of one refresh.

`./install.sh floor` sets the lowest clock a busy core may run at to the
3.2 GHz base clock. It writes `76` to
`/sys/devices/system/cpu/intel_pstate/min_perf_pct` and installs
[`/etc/tmpfiles.d/imacpro-cpu-floor.conf`](../config/etc/tmpfiles.d/imacpro-cpu-floor.conf),
which writes it again at every boot. The value counts in percent of the
4.2 GHz turbo clock, and 76 % of that is 3.2 GHz. With turbo off, a core
that has work runs at exactly 3.2 GHz. Cores without work sleep as before.

### Measured

A small Wayland client asked Hyprland when each of its frames reached the
screen (`wp_presentation`). Two refresh intervals between two frames are one
lost frame. On an otherwise empty workspace three foot windows opened one
after another and closed again, each after 2 s of standstill. Every figure is
one series of 18 such window events in three rounds, with the settings taking
turns.

| Floor | Lost frames in 18 window events |
|---|---|
| none: 1.2 GHz | 10 and 8 |
| 2.1 GHz (`50`) | 2 |
| 3.2 GHz (`76`) | 0 and 0 |

What the floor costs at idle, each setting three times for 8 s in turn, CPU
package from RAPL:

| | no floor | 2.1 GHz | 3.2 GHz |
|---|---|---|---|
| CPU package | 22.5 W | 23.0 W | 24.0 W |
| CPU package temperature | 52 to 53 °C | 52 °C | 54 °C |

Eight seconds are too short for the temperature to settle, and the fans were
not compared.

The GPU's clocks play a smaller part. In a first, shorter series, with
windows that hold a plain full-size buffer and the cpufreq governor
`performance` in place of the floor, 1 lost frame per run was left where the
stock setting lost 2 and 4. With the GPU forced to its highest clocks as well
(`power_dpm_force_performance_level=high`) none was left. That costs about
30 W at idle (46 to 54 W for the GPU instead of 15 to 23 W), so this repo
leaves the GPU alone.

One thing is open. At the start of the tests the GPU's memory clock dropped
to 167 MHz at idle. Since the tests that switched the performance level to
`high` or `manual` and back to `auto`, it has stayed at its top level,
786 MHz, and the tables above were measured in that state. Whether it drops
again after a reboot, and whether the floor then leaves a lost frame now and
then, has not been measured.

Not yet tested across sleep. `./check.sh` shows whether the floor is on, now
and from boot.

## Back to stock

```bash
./install.sh power-stock
```

This deletes the saved AC profile, so Omarchy picks `performance` again, now
and at every login.

```bash
./install.sh cpu-stock
```

This removes the tmpfiles rule and turns turbo back on right away.

```bash
./install.sh floor-stock
```

This removes the tmpfiles rule, and the CPU drops to 1.2 GHz at idle again
right away.
