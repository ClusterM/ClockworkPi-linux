Raspberry Pi Linux kernel with tweaks for the uConsole and other ClockworkPi cyberdecks by [ak-rex](https://github.com/ak-rex/ClockworkPi-linux) and me
=======================================================================================================================================================

This repository is based on the Linux kernel from https://github.com/raspberrypi/linux

It includes:
* Additional drivers for ClockworkPi cyberdecks
* Overlays by [ak-rex](https://github.com/ak-rex/ClockworkPi-linux)
* My custom tweaks

My tweaks:
* **Updated the ocp8178 backlight driver to provide 21 brightness levels instead of 10**  
  By default, there are only 10 brightness levels, so the screen can sometimes be too bright or too dark. These 21 levels correspond to a 0%–100% scale in 5% steps.
* **AXP228 driver tuning and fixes**  
  Includes calibration fixes, capacity tuning, and removal of the need to hold the power button for a second.
* **Increased the maximum LIRC IR duration from 500 ms to 2000 ms**  
  Needed for AC control
