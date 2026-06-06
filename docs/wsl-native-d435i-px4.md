# WSL Ubuntu 20.04 Native Deployment

This repository contains the calibrated D435i stereo + external PX4 IMU setup that was validated for `VINS-Fusion` stereo + IMU mode. The goal of this guide is to let a fresh WSL2 Ubuntu 20.04 machine install, build, and run the same pipeline without Docker.

## 1. Clone the repos

```bash
cd ~
git clone -b wsl-native-release git@github.com:zfmmmm/IOT.git VINS-Fusion
cd VINS-Fusion
git submodule update --init --recursive
```

`PX4-Autopilot` is tracked as a submodule because the board-side changes live there.

## 2. Attach the D435i and PX4 board into WSL

On Windows PowerShell as Administrator:

```powershell
usbipd list
usbipd bind --busid <BUSID_OF_D435I>
usbipd attach --wsl --busid <BUSID_OF_D435I>
usbipd bind --busid <BUSID_OF_PX4>
usbipd attach --wsl --busid <BUSID_OF_PX4>
```

Inside WSL, confirm both devices are visible:

```bash
lsusb
ls -l /dev/serial/by-id
```

WSLg is enough for RViz and the preview windows. No extra X11 server is required on current Windows 11 builds.

## 3. One-shot install

From the repo root:

```bash
cd ~/VINS-Fusion
chmod +x scripts/*.sh vins_estimator/scripts/*.py
INSTALL_PX4_DEPS=true BUILD_PX4=false ./scripts/setup_wsl_native_noetic.sh install
```

What this does:

- installs ROS Noetic desktop and catkin tooling
- installs MAVROS, RealSense ROS, librealsense, GeographicLib datasets
- creates `~/vins_ws`
- links this repo into that catkin workspace
- builds the VINS workspace
- optionally installs PX4 host build dependencies

If you only need the runtime side and the board is already flashed, `INSTALL_PX4_DEPS=false` is fine.

## 4. Optional: rebuild the PX4 firmware

If you need to rebuild the board-side firmware on the new machine:

```bash
cd ~/VINS-Fusion
./scripts/build_px4_nxt_dual.sh
```

This runs:

```bash
make hkust_nxt-dual_default
```

## 5. Preflight check

```bash
cd ~/VINS-Fusion
./scripts/setup_wsl_native_noetic.sh check
```

You should see:

- `mavros`, `realsense2_camera`, `rviz`, `vins`, `loop_fusion` all discoverable through `rospack`
- the D435i listed by `rs-enumerate-devices`
- the PX4 serial device under `/dev/serial/by-id` or `/dev/ttyACM0`

## 6. Run the live pipeline

```bash
cd ~/VINS-Fusion
RUN_RVIZ=true RUN_LOOP=false ./scripts/run_wsl_native_d435i_px4.sh
```

Expected early logs:

- `D435i infrared projector disabled`
- `waiting for stereo+IMU init excitation ...`

That second message is expected. It means the initialization guard is waiting for enough feature tracks, parallax, and IMU rotation before allowing VINS to initialize.

On WSL the native launcher keeps `INITIAL_RESET=false` by default. This is intentional: `realsense2_camera` device reset can make the D435i disappear from the attached WSL USB session.

## 7. Correct initialization motion

Do this right after the pipeline starts:

1. face a textured scene, not a white wall
2. move slowly left/right, up/down, forward/back by 20-40 cm
3. add small yaw, pitch, and roll
4. avoid fast shaking during the first 10-20 seconds

When the excitation is good, the terminal should print:

```text
Initialization finish!
```

Only trust the trajectory after that point.

## 8. Record a verification bag

If you want a reproducible debug bag while the live pipeline is running in another terminal:

```bash
cd ~/VINS-Fusion
DURATION=60 ./scripts/record_vins_debug.sh
```

This records:

- stereo infrared images and camera_info
- `/mavros/imu/data_raw`
- `/mavros/timesync_status`
- VINS odometry/path
- TF

The script closes the bag cleanly so it becomes a normal `.bag`, not `.bag.active`.

## 9. Calibration assets already embedded

The currently used calibration and tuning live in:

- `config/realsense_d435i/left.yaml`
- `config/realsense_d435i/right.yaml`
- `config/realsense_d435i/px4_imu_bmi088.yaml`
- `config/realsense_d435i/realsense_stereo_px4_imu_config.yaml`

The initialization anti-drift guard is also part of this repo now, so the native run keeps the same behavior that was validated on the Docker side.
