<div align="center">

# 🎧🖱️ AirPodsMouse

### Turn your AirPods case into an air mouse.

Open the lid, point the case at your screen, and steer the cursor with your wrist.<br>
No extra hardware: it reads the motion sensors of the AirPods sitting in the case.

![macOS](https://img.shields.io/badge/macOS-14%2B-000000?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white)
![CoreMotion](https://img.shields.io/badge/CoreMotion-Headphone%20Motion-0A84FF?style=for-the-badge)
![SceneKit](https://img.shields.io/badge/SceneKit-3D%20Viewer-34C759?style=for-the-badge)

<img src="docs/3d-view.png" alt="Live 3D view of the AirPods case orientation" width="720">

<sub><i>The built-in 3D viewer: the case and its axes follow your hand in real time.</i></sub>

[**Quick start**](#-quick-start) •
[**Controls**](#-controls) •
[**3D viewer**](#-3d-viewer) •
[**How it works**](#-how-it-works) •
[**Troubleshooting**](#-troubleshooting) •
[**Roadmap**](#-roadmap)

</div>

---

## 📖 Table of contents

1. [Features](#-features)
2. [Requirements](#-requirements)
3. [Quick start](#-quick-start)
   - [Build](#1-build)
   - [Set up permissions](#2-set-up-permissions)
   - [Calibrate](#3-calibrate)
4. [Controls](#-controls)
5. [3D viewer](#-3d-viewer)
6. [How it works](#-how-it-works)
7. [Project structure](#-project-structure)
8. [Command-line options](#-command-line-options)
9. [Troubleshooting](#-troubleshooting)
10. [Roadmap](#-roadmap)

---

## ✨ Features

| | Feature | Details |
|---|---|---|
| 🎯 | **Air pointing** | Rotate the case left/right and up/down to move the cursor |
| 🔄 | **Twist to click** | Twist the case like a key for a **left click** |
| ⚡ | **Flick to right-click** | A quick up/down flick for a **right click** *(optional)* |
| 🧭 | **Any grip** | Horizontal motion comes from gravity, so it doesn't matter how the earbuds lie in the case |
| 🎚️ | **3-second calibration** | Learns your vertical axis once and saves it |
| 🧊 | **Live 3D viewer** | See the case orientation, its axes, and click feedback |
| 🫨 | **Jitter-free** | Dead zone, smoothing, and acceleration curve |
| ⌨️ | **Global hotkeys** | Always a way to pause or quit |
| 🪶 | **Menu bar app** | No Dock icon, no window unless you open one |

## 📋 Requirements

| | |
|---|---|
| 💻 **Mac** | macOS 14 Sonoma or later |
| 🎧 **AirPods** | With motion sensors: **AirPods Pro (1st & 2nd gen)**, **AirPods 3 / 4**, **AirPods Max** |
| 🛠️ **Tools** | Xcode Command Line Tools: `xcode-select --install` |

> [!WARNING]
> AirPods 1st and 2nd gen have no gyroscope and **won't work**.

---

## 🚀 Quick start

### 1. Build

```bash
git clone https://github.com/Harlo9/AirPodsMouse.git
cd AirPodsMouse
./build.sh
open AirPodsMouse.app
```

Look for **🎧🖱** in the menu bar.

### 2. Set up permissions

| Step | Where | Why |
|:---:|---|---|
| 1 | *System Settings → [your AirPods] → **Automatic Ear Detection: Off*** | Keeps the sensors streaming while the AirPods are in the case |
| 2 | Open the **case lid** and check the AirPods are connected | |
| 3 | Allow **Motion & Fitness** when prompted | Read the AirPods motion sensors |
| 4 | *System Settings → Privacy & Security → **Accessibility** → AirPodsMouse* | Move the cursor and click |

> [!TIP]
> Each rebuild can make macOS forget the Accessibility permission. Remove AirPodsMouse with **−**, add it back, and relaunch.

### 3. Calibrate

Press **`⌃ ⌥ C`**, then during the next 3 seconds:

> 👉 Point the case at the screen → **tilt it UP** and back, 2–3 times

A *Glass* sound means you're done. The calibration is saved, so you only do this once.

> [!IMPORTANT]
> The **twist-to-click** gesture only works after calibration: it needs to know which way the case is pointing.

---

## 🎮 Controls

### Gestures

| Gesture | Action | Default |
|---|---|:---:|
| ↔️ Rotate the case left / right | Move cursor horizontally | ✅ |
| ↕️ Tilt the case up / down | Move cursor vertically | ✅ |
| 🔄 Quick **twist** (like a key) and back | **Left click** | ✅ |
| ⚡ Quick **flick** up/down and back | **Right click** | ⬜ enable in menu |

The cursor freezes during a gesture, so clicks land exactly where you aimed.

### Hotkeys

| Shortcut | Action |
|---|---|
| `⌃ ⌥ Q` | Quit |
| `⌃ ⌥ P` | Pause / resume |
| `⌃ ⌥ C` | Calibrate |
| `⌃ ⌥ V` | Open the 3D viewer |

### Menu bar

The app UI is in French. Click **🎧🖱** for:

| Menu item | Meaning |
|---|---|
| Calibrer | Calibrate |
| Vue 3D | Open the 3D viewer |
| Pause | Pause cursor control |
| Inverser gauche/droite · haut/bas | Invert horizontal / vertical axis |
| Clic droit : petit coup sec | Toggle flick → right click |
| Clic gauche : tourner le poignet | Toggle twist → left click |
| Sensibilité + / − | Sensitivity up / down |
| Quitter | Quit |

---

## 🧊 3D viewer

Open it with **`⌃ ⌥ V`**, or launch with `open AirPodsMouse.app --args --3d`.

| Element | Meaning |
|---|---|
| 🔴 Red arrow | Case's **right** axis |
| 🟢 Green arrow | Case's **up** axis |
| 🔵 Blue arrow / dot | Where the case is **pointing** |
| Thin arrows | Fixed world reference |
| Case flashes 🔵 / 🟠 | Left / right click detected |
| Bottom line | Live rotation speeds (rad/s) |

Drag to orbit, scroll to zoom, and click **Recentrer** to reset the orientation.

> [!TIP]
> Press `⌃ ⌥ P` to pause the cursor while you play with the 3D view.

---

## 🧠 How it works

```
 AirPods (in the open case)
        │  CMHeadphoneMotionManager: attitude, rotation rate, gravity
        ▼
 ┌────────────────────────────────────────────────┐
 │  ω = gyroscope rotation rate   (earbud frame)  │
 │  g = gravity direction         (earbud frame)  │
 │                                                │
 │  horizontal speed = −ω · g          no calib.  │
 │  vertical speed   =  ω · a          a learned  │
 │  twist speed      =  ω · (a × g)    pointing   │
 └────────────────────────────────────────────────┘
        │  dead zone → acceleration curve → smoothing
        ▼
   CGEvent: mouse move / click
```

- **Horizontal** is the rotation around the vertical, which gravity gives directly, so it doesn't depend on how the earbuds sit in the case.
- **Vertical axis `a`** is learned during calibration with a principal-component analysis of your up/down tilts. The sign comes from the direction of the first tilt.
- **Pointing axis** `a × g` is perpendicular to both, so the twist gesture needs no extra calibration and doesn't move the cursor.
- **Relative motion**: velocity-based like a real mouse, so there's no drift to fight and your trackpad keeps working alongside it.

---

## 🗂️ Project structure

```
AirPodsMouse/
├── main.swift       # Motion processing, gestures, calibration, menu bar, hotkeys
├── Viewer3D.swift   # SceneKit live 3D viewer
├── build.sh         # Builds & ad-hoc signs AirPodsMouse.app
└── docs/
    └── 3d-view.png  # README screenshot (generated with --snapshot)
```

## 💻 Command-line options

| Command | Effect |
|---|---|
| `open AirPodsMouse.app` | Normal launch (menu bar) |
| `open AirPodsMouse.app --args --3d` | Launch with the 3D viewer open |
| `./AirPodsMouse.app/Contents/MacOS/AirPodsMouse` | Run in the terminal and see live status logs |
| `./AirPodsMouse.app/Contents/MacOS/AirPodsMouse --snapshot out.png` | Render the 3D scene to a PNG and exit |

---

## 🛠️ Troubleshooting

| Problem | Fix |
|---|---|
| Cursor doesn't move at all | Re-grant **Accessibility** permission (see tip above) |
| No motion (3D view frozen, speeds stay at 0) | Turn off ear detection, keep the lid **open**, check the Bluetooth connection |
| Twist doesn't click | Calibrate first with `⌃ ⌥ C` |
| Up/down is reversed | Menu → **Inverser haut/bas** |
| Too fast / too slow | Menu → **Sensibilité + / −** |
| Clicks trigger too easily | Raise the `threshold` of `twist` / `flick` in `main.swift` |
| Cursor goes wild | Recalibrate with `⌃ ⌥ C` |

---

## 🗺️ Roadmap

- [ ] Multi-monitor support
- [ ] Double-click and drag & drop
- [ ] Scroll gesture
- [ ] Settings window with live sliders
- [ ] English UI

---

<div align="center">

Made with 🎧 and way too much wrist-twisting.

⭐ **Star the repo if your AirPods case is now a mouse.**

</div>
