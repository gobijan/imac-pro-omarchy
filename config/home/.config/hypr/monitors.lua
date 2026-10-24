-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale, bitdepth = 10, cm = "dp3" })

-- iMac Pro: DP-1 is the right half of the 5K panel, which the patched amdgpu
-- drives as part of eDP-1. Keep it off even if something tries to enable it
-- (Omarchy's display panel lists it); `hyprctl reload` re-applies this.
hl.monitor({ output = "DP-1", disabled = true })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
