You are validating a native WSL2 Ubuntu 20.04 deployment of a customized VINS-Fusion project that uses:

- Intel RealSense D435i infrared stereo cameras
- an external PX4 / NxtPX4v2 IMU over MAVROS
- VINS-Fusion stereo + IMU mode
- the repository at `~/VINS-Fusion`

Your job is to act like a strict deployment auditor. Do not assume success. Verify everything with commands and concrete evidence.

## Success criteria

The deployment only passes if all of these are true:

1. Ubuntu is 20.04 inside WSL2.
2. ROS Noetic is installed and sourceable.
3. `PX4-Autopilot` submodule is present.
4. The catkin workspace builds successfully.
5. The D435i is visible inside WSL.
6. The PX4 board serial device is visible inside WSL.
7. The live launch starts without missing package errors.
8. The RealSense infrared projector is disabled automatically.
9. VINS waits for excitation first, then reaches `Initialization finish!`.
10. A short live motion test does not immediately diverge during initialization.

## Required behavior

- Use shell commands to verify each claim.
- Save logs under `~/VINS-Fusion/calibration/logs/`.
- If something fails, stop claiming progress and report the exact blocker.
- Distinguish between “build passes”, “launch starts”, and “tracking is stable”.
- Include absolute paths and exact command lines in your report.

## Verification procedure

Run these checks in order.

### 1. Environment

```bash
uname -a
lsb_release -a
echo "$WSL_DISTRO_NAME"
```

Fail if Ubuntu is not 20.04 or if this is not WSL.

### 2. Repository and submodule

```bash
cd ~/VINS-Fusion
git status -sb
git submodule status --recursive
```

Fail if `PX4-Autopilot` is missing or detached from the recorded commit.

### 3. ROS and package checks

```bash
source /opt/ros/noetic/setup.bash
rospack find mavros
rospack find realsense2_camera
rospack find rviz
```

Then:

```bash
cd ~/VINS-Fusion
./scripts/setup_wsl_native_noetic.sh check
```

### 4. USB visibility

```bash
lsusb
ls -l /dev/serial/by-id
rs-enumerate-devices
```

Fail if the D435i or PX4 board are not visible.

### 5. Build verification

```bash
cd ~/VINS-Fusion
./scripts/setup_wsl_native_noetic.sh build
```

Pass only if `catkin_make` exits with code 0.

### 6. Live launch verification

Start the live system and tee the log:

```bash
cd ~/VINS-Fusion
mkdir -p calibration/logs
RUN_RVIZ=false RUN_LOOP=false ./scripts/run_wsl_native_d435i_px4.sh 2>&1 | tee calibration/logs/wsl_native_live_$(date +%Y%m%d_%H%M%S).log
```

Inspect the log for:

- projector disabled message
- no missing topic/package errors
- `waiting for stereo+IMU init excitation`
- `Initialization finish!`

### 7. Short record verification

While the live launch is still running in another terminal:

```bash
cd ~/VINS-Fusion
DURATION=30 ./scripts/record_vins_debug.sh
ls -lh calibration/bags | tail
```

Pass only if a new `.bag` file exists and is not stuck as `.bag.active`.

## Final report format

Write a concise report with these sections:

1. `Environment`
2. `Build`
3. `Devices`
4. `Launch`
5. `Runtime stability`
6. `Blockers`

For each section, include:

- the exact command used
- the observed result
- pass/fail

Do not say the deployment is successful unless every success criterion above is backed by command output.
