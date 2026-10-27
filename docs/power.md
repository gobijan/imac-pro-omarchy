# Power profile

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

## Back to stock

```bash
./install.sh power-stock
```

This deletes the saved AC profile, so Omarchy picks `performance` again, now
and at every login.
