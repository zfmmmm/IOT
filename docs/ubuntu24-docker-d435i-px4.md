# Ubuntu 24.04 Docker Deployment for D435i + PX4 IMU

This guide is for a real Ubuntu 24.04 machine. Use Docker because ROS Noetic is not a native Ubuntu 24.04 target, while this project depends on ROS Noetic packages.

## 1. Clone and Sync

```bash
cd ~
git clone -b wsl-native-release https://github.com/zfmmmm/IOT.git VINS-Fusion
cd ~/VINS-Fusion
git submodule sync --recursive
git submodule update --init --recursive
```

If the submodule was half-cloned before, clean it and retry:

```bash
cd ~/VINS-Fusion
rm -rf PX4-Autopilot
git submodule sync --recursive
git submodule update --init --recursive
```

## 2. Install and Build Docker Images

```bash
cd ~/VINS-Fusion
chmod +x scripts/setup_ubuntu24_docker.sh
./scripts/setup_ubuntu24_docker.sh
```

If the script adds your user to the `docker` group, logout and login once, then rerun:

```bash
cd ~/VINS-Fusion
./scripts/setup_ubuntu24_docker.sh
```

The script builds:

- `vins-noetic-d435i:latest`
- `vins-noetic-d435i-px4:latest`
- `kalibr:latest` when it is missing and `BUILD_KALIBR=auto`

If Kalibr build fails because of network or upstream Docker changes, localization can still run. Build Kalibr later with:

```bash
cd ~/VINS-Fusion
BUILD_KALIBR=true ./scripts/setup_ubuntu24_docker.sh
```

## 3. Connect Hardware

Connect both:

- Intel RealSense D435i, preferably through a USB 3 port.
- NxtPX4/PX4 flight controller.

Check devices:

```bash
lsusb
ls -l /dev/serial/by-id || true
ls /dev/ttyACM* || true
```

The preferred FCU path is:

```text
/dev/serial/by-id/usb-Matek_HKUST_UAV_NxtPX4_0-if00
```

If your board appears with another name, pass it through `FCU_URL`.

## 4. Check Calibration Runtime

```bash
cd ~/VINS-Fusion
./scripts/d435i_px4_kalibr.sh check
```

## 5. Record a Calibration Bag

Keep the AprilGrid fixed. Move the whole D435i + PX4 rigid body slowly.

```bash
cd ~/VINS-Fusion
DURATION=150 COUNTDOWN=30 PREVIEW=true ./scripts/d435i_px4_kalibr.sh record
```

If the preview does not show, confirm `DISPLAY` works and that the desktop allows Docker X11 windows:

```bash
xhost +local:docker
```

## 6. Calibrate and Import Into VINS

```bash
cd ~/VINS-Fusion

BAG=$(ls -t calibration/bags/d435i_px4_*.bag | grep -v active | head -1)

BAG_FREQ=4 ./scripts/d435i_px4_kalibr.sh calibrate-cam "$BAG"

BASE=$(basename "$BAG" .bag)
CAMCHAIN=$(find calibration/bags calibration/results/cam -name "${BASE}*camchain.yaml" | sort | tail -1)

KALIBR_IMU_EXTRA_ARGS="--bag-from-to 5 145 --timeoffset-padding 0.5 --dont-show-report" \
BAG_FREQ=3 \
./scripts/d435i_px4_kalibr.sh calibrate-imu "$BAG" "$CAMCHAIN"

./scripts/d435i_px4_kalibr.sh embed-vins "$BAG"
```

`embed-vins` first backs up the old config under:

```text
config/realsense_d435i/backup/<bag_name>_<timestamp>/
```

Then it updates:

- `config/realsense_d435i/left.yaml`
- `config/realsense_d435i/right.yaml`
- `config/realsense_d435i/realsense_stereo_px4_imu_config.yaml`

## 7. Run VINS Localization

```bash
cd ~/VINS-Fusion
RUN_RVIZ=true RUN_LOOP=false ./docker/run_d435i_px4.sh
```

If the flight controller serial path is different:

```bash
FCU_URL=/dev/serial/by-id/<your_fcu_device>:921600 \
RUN_RVIZ=true RUN_LOOP=false \
./docker/run_d435i_px4.sh
```

After startup, move the rig slowly in a textured area for VINS initialization. Avoid starting with fast motion, white walls, or a single flat target filling the image.

## 8. Print Loop-Closure Error in Terminal

When VINS is running, the terminal prints:

```text
[VINS POSE] Press p or Enter in this terminal to print current VINS position.
```

Use it like this:

1. Put the rig on the start mark and press `p` or Enter.
2. Walk a loop and return to the same mark.
3. Press `p` or Enter again.

The second print shows the error from mark #1:

- `dx`, `dy`, `dz`
- horizontal error
- 3D error
- yaw error

Manual trigger also works:

```bash
rostopic pub -1 /vins_estimator/print_pose std_msgs/Empty "{}"
```

## 9. Update This Branch Later

On the Ubuntu 24.04 machine:

```bash
cd ~/VINS-Fusion
git fetch origin
git checkout wsl-native-release
git pull --ff-only origin wsl-native-release
git submodule sync --recursive
git submodule update --init --recursive
```

To push new code from that machine:

```bash
cd ~/VINS-Fusion
git checkout wsl-native-release
git status
git add .
git commit -m "Describe your change"
git push origin wsl-native-release
```

If PX4 submodule code changed:

```bash
cd ~/VINS-Fusion/PX4-Autopilot
git checkout wsl-native-release
git add .
git commit -m "Describe PX4 change"
git push origin wsl-native-release

cd ~/VINS-Fusion
git checkout wsl-native-release
git add PX4-Autopilot
git commit -m "Update PX4 submodule pointer"
git push origin wsl-native-release
```
