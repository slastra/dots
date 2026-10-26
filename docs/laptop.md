# The laptop

How `hosts/lap` differs from the desk. The [README](../README.md) covers the desk.

`lap` is a Lenovo Slim 7 14IRP8 (i7-1360P, 2880×1800 40–120 Hz panel). It
runs the same lastshell checkout as the desk (one tree; `services/Host.qml`
switches the desk-only chips off) and the files under `hosts/lap/config/`
in place of the desk's `config/hypr`. `capture.sh` and `hotkeys.py` are the
desk's, unchanged.

Presence comes from the ST VL53L1 time-of-flight sensor on the Intel sensor
hub, through [deskpresence](https://github.com/slastra/deskpresence)
(`systemd/deskpresence-tof.service`): away 30 s fades and blanks the panel
through `scripts/laptop-screen.sh`; hypridle's timeouts go through
`scripts/presence-guard.sh`, so reading without touching anything isn't
idle.

Brightness steps a perceptual level (CIE L*), so 5% looks the same at the
floor as at full, and every change eases instead of jumping. The keys go
through lastshell: a tap is one step, holding glides (the ACPI video bus
reports no hold, only firmware repeats of the tap).

`SUPER + SHIFT + N` (or a click on the network chip) is the Wi-Fi picker:
joined, saved, then nearby networks by signal; a new secured one asks for
its password. `scripts/wifi.py` talks to iwd over D-Bus and is its
passphrase agent, and runs only while the picker is open or a join is in
flight.

With hyprglaze off (battery, eco) the background is a still Rosé Pine mesh
gradient: `walls/mesh.png`, rendered by `scripts/mesh-wallpaper.py` (not
committed; run it once), shown by hyprpaper as
`systemd/user/wallpaper-still.service`. Starting either one stops the
other, and hyprglaze's drop-in brings the still back when it stops cleanly.
The unit is not the packaged hyprpaper.service: that one Requires
graphical-session.target, and stopping it took hyprglaze down too.
Clicking the battery chip opens the Eco dialog.

Battery: idle went from ~9.7 W to ~2.5 W (screen dim, nothing working).
Eco mode (`scripts/eco.sh`, Super+Shift+E; the lastshell dialog on
Super+Ctrl+E) drops to power-saver, 60 Hz, no blur, animation or animated
border, and switches Bluetooth and the keyboard light off. On battery
without eco, `scripts/power-watch.sh` still turns 120 Hz, blur and
hyprglaze off. VRR stays off: it disables the panel's PSR2 self-refresh.

`hosts/lap/etc/` holds copies of the root-owned tweaks, installed by hand
with `sudo install -Dm644 <file> /etc/<same path>` (nothing here installs
them):

| File | Why |
|---|---|
| `udev/rules.d/70-lenovo-tof-sensor.rules` | The ToF sensor's streams and enable switch for the `input` group, and report latency 1000 ms so the hub batches samples (~9 wakeups/s down to ~1). |
| `udev/rules.d/80-pci-runtime-pm.rules` | PCI runtime PM `auto` for every device. |
| `sysctl.d/80-power.conf` | NMI watchdog off, dirty writeback every 15 s. |
| `modprobe.d/80-audio-power.conf` | HDA codec power saving. |
| `intel_lpmd/intel_lpmd_config.xml` | intel-lpmd parks onto the E-cores (8–15) when lightly loaded, in power-saver only (~0.2 W). |
| `boot/kernel-params` | `pcie_aspm.policy=powersupersave`: without it the NVMe never reaches L1.2 and s2idle never reaches S0ix. |

`local/bin/say` is the piper one-liner Claude Code speaks through; it plays
via PipeWire (`pw-play`), since `aplay` opening the card directly knocked
the speaker sink out with EBUSY. The OpenRouter key dictation and the
reader use stays out of the repo (`~/.config/lastshell/openrouter.key`).
