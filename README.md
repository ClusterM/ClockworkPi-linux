# Raspberry Pi Linux kernel for ClockworkPi cyberdecks

Fork of the [Raspberry Pi Linux kernel](https://github.com/raspberrypi/linux) with device-tree overlays and driver tweaks for **uConsole**, **DevTerm**, and related ClockworkPi hardware. The patches below are meant for **any board in this family** that uses the same drivers and PMICs, not only one model. Based on work by [ak-rex](https://github.com/ak-rex/ClockworkPi-linux), with additional changes maintained here.

## What this tree adds

- **ClockworkPi-oriented support** — overlays and integration for CM4/CM5 and classic Pi builds where applicable.
- **Upstream-aligned base** — tracks the Raspberry Pi kernel tree; changes are kept as small, reviewable patches on top.
- **Hardware-focused tweaks** — backlight steps, PMIC/battery behavior, and infrared timing tuned for real devices (not generic defaults).

---

## Custom changes (this fork)

### 1. OCP8178 backlight — 21 brightness steps (was 10)

The **OCP8178** one-wire backlight driver (used on several ClockworkPi LCD setups) originally exposed only **10** usable levels (`MAX_BRIGHTNESS_VALUE` 9 plus off), which made the panel jump in coarse steps.

- **What changed:** `MAX_BRIGHTNESS_VALUE` is raised to **21** (22 hardware indices including 0), with a new **lookup table** mapping each step to chip register values. Steps are spread across the 0–31 hardware range so the UI can approximate **about 5% per step** from minimum to maximum useful brightness.
- **Why:** Finer control in dim environments and when avoiding “too bright / too dark” with only a few levels.


### 2. AXP PMIC battery driver (AXP228 path) — what changed for you

These edits are in the **AXP20x battery** driver (`axp20x_battery.c`) and the small **regmap** update in `axp20x.c` needed so the fuel gauge can be used the way below. The battery appears in sysfs as **`axp20x-battery`**:

`/sys/class/power_supply/axp20x-battery/`

**Design (`*_design`) vs live gauge readings**

- **`charge_full_design`** and **`energy_full_design`** are **not** live measurements from the fuel gauge. They are the **nominal design** values the kernel keeps for “how big the pack should be”: what you put in the **device tree**—either baked into the overlay or overridden from **`config.txt`** (`charge_full_design_uah`, `energy_full_design_uwh`). If you only set **charge** in the overlay/config, **energy** design is **estimated** in the driver (see probe below). Those numbers drive **percentage** and **energy_now** math. In this fork, both sysfs files report the same internal **design energy** figure (in **µWh**); the name `charge_full_design` follows the kernel ABI, but the value matches **`energy_full_design`** here.
- **`charge_full`** and **`charge_now`** are **operational** values from the PMIC’s fuel gauge (µAh). **`charge_now`** is the **remaining** charge estimate. **`charge_full`** is the **full-charge capacity the PMIC currently holds in its fuel-gauge state**—it may have been **programmed** (device tree, sysfs write, or earlier calibration) or **learned** by the chip; it is not the same thing as the static `*_design` numbers above.

**Other sysfs files**

| File | Meaning (plain language) |
|------|---------------------------|
| **`charge_full`** | **Current** full-capacity figure stored in the PMIC fuel gauge (µAh): whatever the chip is using now—**set** (DT, sysfs, or prior learn) or **auto-estimated** by the gauge. **Writable** — writing µAh programs that stored value (runtime, same family of effect as design charge from DT). |
| **`charge_now`** | **Remaining** charge from the gauge (µAh). |
| **`charge_full_design`** | See above: **design** baseline (µWh in this driver), from overlay/config or estimate. |
| **`energy_full_design`** | Same **design** energy in **µWh** as above, from overlay/config or estimate. |


**Calibration (`calibrate`)**

- Sysfs: **`/sys/class/power_supply/axp20x-battery/calibrate`**
- **Read:** Raw bits from the PMIC **coulomb / calibration control** register (which calibration-related flags are set).
- **Write:** **`1`** turns on only the **full-capacity re-learn enable** bit on the AXP228 (`AXP228_FULL_CAPACITY_CALIBRATE_EN`). **`0`** clears that bit. In this fork, enabling calibration **no longer** sets the extra **`AXP228_CAPACITY_CALIBRATE`** bit in the same register that the previous code toggled together with it—so you avoid flipping that second path when you only want full-capacity learning.

**Boot behaviour added in probe**

- If the device tree gives **`charge-full-design-microamp-hours`**, that value is written into the PMIC and checked against what can be read back.
- If it does **not**, the driver reads the **design charge** already stored in the PMIC and logs it.
- **`energy-full-design-microwatt-hours`** from the device tree is used when present; otherwise **energy** design is **estimated** from the design charge using **3.7 V** as a typical average cell voltage (`charge_design_uAh × 37 / 10` → µWh).

**Other changes in the same patch**

- **Power key (PEK):** **instant power-on** on a short press—the PMIC is configured so you no longer need to **hold the button for about a second** to turn the device on (other PEK timing bits are set in the same register write as in the patch).
- Overlay **`clockworkpi-custom-battery-overlay`** was **removed**; capacity is tuned via the main ClockworkPi overlays and **parameters** below.

**Setting battery capacity from `config.txt`**

The ClockworkPi overlays keep **design capacity properties at `0`** in the `.dts` (no baked-in pack size) so nothing assumes a default mAh/Wh. Set **`charge_full_design_uah`** when you know your pack’s design charge; otherwise the driver falls back to the **PMIC / estimate** behaviour described in **Boot behaviour** above.

**`energy_full_design_uwh`** has **little practical benefit** in normal use: the driver already derives design energy from the charge figure when you do not set it, and day-to-day behaviour does not depend on tuning both separately. **You can omit it** and only pass **`charge_full_design_uah`**.

ClockworkPi overlays expose those parameters so you can match your pack without rebuilding. Example for **uConsole CM5** — set design charge to **6.9 Ah** (6900000 µAh):

```ini
dtoverlay=clockworkpi-uconsole-cm5,charge_full_design_uah=6900000
```

Use the overlay name that matches your board (`clockworkpi-uconsole`, `clockworkpi-devterm`, CM5 variants, etc.). You only need a second line if you insist on supplying design energy manually (usually unnecessary):

```ini
dtoverlay=clockworkpi-uconsole-cm5,charge_full_design_uah=6900000,energy_full_design_uwh=25530000
```

**Applying a new capacity value:** The PMIC may keep the **old** design capacity until it loses **all** power. A normal shutdown or reboot is often not enough—the chip can stay alive from the cells. **Remove the battery cells** (full disconnect), wait a moment, reinsert, then boot. The same caveat applies if you **write** a new value to **`charge_full`** in sysfs: it may not visibly stick until after that kind of full power cycle.

---

### 3. LIRC / RC core — longer IR timings for AC remotes

Air conditioner IR protocols often use **long marks/spaces** (sometimes near or above **500 ms** in space duration).

- **`IR_MAX_DURATION`** in `include/media/rc-core.h` is increased from **500 ms** to **2000 ms** so raw IR events are not truncated.
- **`LIRCBUF_SIZE`** in `drivers/media/rc/lirc_dev.c` is increased from **1024** to **4096** so the userspace LIRC buffer can hold longer pulse trains.

Together, these avoid losing long frames when sending or receiving such signals from the IR hardware on ClockworkPi devices (or any other setup using this kernel’s LIRC stack with long IR frames).

---


## Building and deploying

Follow the standard **Raspberry Pi kernel build** workflow (cross-compile or native), install modules/kernel image as for your board (CM4/CM5 vs Pi 4, etc.), and enable the appropriate **`dtoverlay=`** for your ClockworkPi device in `config.txt`. Override battery parameters if your pack differs from the default overlay values.

For upstream history and base kernel documentation, see [raspberrypi/linux](https://github.com/raspberrypi/linux) and the original [ak-rex/ClockworkPi-linux](https://github.com/ak-rex/ClockworkPi-linux) project.

---



## Prebuilt kernel (GitHub Actions & GitHub Pages)

This repository runs **GitHub Actions** that cross-build an **arm64** image with **`bcm2712_defconfig`** (Raspberry Pi 6.12-style tree): compressed kernel image, **out-of-tree modules**, and **Broadcom `.dtb`** files from `arch/arm64/boot/dts/broadcom/`. Successful runs on branch **`clockworkpi-6.12.x-live`** also publish a small **GitHub Pages** site with the **kernel release string**, **last build time**, and a **direct download link** for the tarball.

| What | URL |
|------|-----|
| **Download page (GitHub Pages)** | [https://clusterm.github.io/ClockworkPi-linux/](https://clusterm.github.io/ClockworkPi-linux/) |
| **Repository** | [https://github.com/ClusterM/ClockworkPi-linux/](https://github.com/ClusterM/ClockworkPi-linux/) |
| **Workflow runs & artifacts** | [Actions](https://github.com/ClusterM/ClockworkPi-linux/actions) |

If the tarball is too large for Pages or you need an older run, grab the same file from the **Artifacts** section of the corresponding workflow run.

### Installing the prebuilt tarball (kernel, modules, device trees)

**Warning:** Do this on a **Raspberry Pi OS** (or compatible) system with **backups** of `/boot/firmware`. Wrong kernel/module mismatch will fail to boot until you recover the boot partition. The **module directory name must match** `uname -r` after you boot the new kernel.

1. **Download** the `kernel-*.tar.xz` file from the Pages site or Actions, then extract, for example:
   ```sh
   mkdir -p /tmp/k && tar -xJf kernel-*.tar.xz -C /tmp/k
   ```

2. **Kernel image** — the archive contains **`kernel-*.img`**. Install the decompressed image to `/boot/firmware`:
   ```sh
   sudo cp /tmp/k/kernel-*.img /boot/firmware/
   ```

3. **Modules** — the tree under `modules/lib/modules/<version>/` must be copied to the root filesystem:
   ```sh
   KREL=$(basename /tmp/k/modules/lib/modules/*)
   sudo rsync -a /tmp/k/modules/lib/modules/"$KREL"/ /lib/modules/"$KREL"/
   sudo depmod -a "$KREL"
   ```

4. **Device trees** — copy the **`.dtb`** files you need from `dtbs/` into the `/boot/firmware`:
   ```sh
   sudo rsync -a /tmp/k/dtbs/ /boot/firmware/
   ```

5. **Edit config.txt** - change image name into `/boot/firmware/config.txt`. Example config:
   ```
   TODO
   ```
