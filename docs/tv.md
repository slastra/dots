# The TV

The display is an LG OLED. `scripts/tv-screen.sh` turns the TV itself off
and on over the LAN instead of using DPMS. A DPMS wake forces an HDMI
2.1 FRL retrain the NVIDIA driver refuses to retry, which latches the
desktop at 60 Hz. `scripts/tv-pixel-refresh.sh` runs the panel's pixel
cleaning nightly by driving the TV's own menus over the remote-control
API. `scripts/lg-ipctl.py` speaks the TV's encrypted IP-control protocol;
its key lives in `~/.config/lgtv/ipcontrol.key`, outside this repo.

`deskpresence` (radar presence) owns blanking the TV. `scripts/tv-watchdog.sh`
is the fallback: if `deskpresence` has died, it blanks the TV after 10
minutes without input. `scripts/unblank.sh` lifts lastshell's blackout
shader on input if a crash left it applied.
