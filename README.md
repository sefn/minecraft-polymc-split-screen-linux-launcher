# minecraft-polymc-split-screen-linux-setup
Play Minecraft split-screen (locally) using PolyMC in Linux (on a specific monitor, and disable HDR)

## What is this?

I use this to play Minecraft split-screen on Linux. Uses PolyMC and launches 2 defined instances with different users, disables HDR on my PC monitor (so HDR works on the TV to which I stream using Sunshine/Moonlight - and re-enables once Minecraft is exited), then re-arranges the two windows in a split-screen orientation (side-by-side) on my defined monitor.

## Requirements

* PolyMC installed (e.g. through Flatpak), with 2 instances and 2 local users setup
* Some bash utilities installed:
  * **kscreen-doctor** (to disable/enable HDR if you use that part)
  * **wmctrl**, **xdpyinfo** and **xrandr** to re-arrange 2 Minecraft windows into split screen

## Credits

Thanks to Gemini 2.5 Pro Preview 05-06 for being there for me and helping me automate this.
