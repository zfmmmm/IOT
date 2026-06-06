#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-vins-noetic-d435i-px4:latest}"
DEFAULT_FCU_DEV="/dev/serial/by-id/usb-Matek_HKUST_UAV_NxtPX4_0-if00"
if [ -e "${DEFAULT_FCU_DEV}" ]; then
  DEFAULT_FCU_URL="${DEFAULT_FCU_DEV}:921600"
else
  DEFAULT_FCU_URL="/dev/ttyACM0:921600"
fi
FCU_URL="${FCU_URL:-${DEFAULT_FCU_URL}}"
RUN_CAMERA="${RUN_CAMERA:-true}"
RUN_MAVROS="${RUN_MAVROS:-true}"
RUN_RVIZ="${RUN_RVIZ:-false}"
RUN_LOOP="${RUN_LOOP:-false}"
RUN_POSE_PRINTER="${RUN_POSE_PRINTER:-true}"
INITIAL_RESET="${INITIAL_RESET:-true}"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  docker build -f "${REPO_DIR}/docker/Dockerfile.noetic-d435i-px4" -t "${IMAGE}" "${REPO_DIR}"
fi

mkdir -p /tmp/vins_output/pose_graph
xhost +local:docker >/dev/null 2>&1 || true

docker run --rm -it \
  --net=host \
  --privileged \
  -e DISPLAY="${DISPLAY:-}" \
  -e QT_X11_NO_MITSHM=1 \
  -e FCU_URL="${FCU_URL}" \
  -e RUN_CAMERA="${RUN_CAMERA}" \
  -e RUN_MAVROS="${RUN_MAVROS}" \
  -e RUN_RVIZ="${RUN_RVIZ}" \
  -e RUN_LOOP="${RUN_LOOP}" \
  -e RUN_POSE_PRINTER="${RUN_POSE_PRINTER}" \
  -e INITIAL_RESET="${INITIAL_RESET}" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v /tmp/vins_output:/tmp/vins_output:rw \
  -v /dev:/dev \
  -v "${REPO_DIR}:/repo:rw" \
  "${IMAGE}" \
  bash -lc '
    set -euo pipefail
    source /opt/ros/noetic/setup.bash
    mkdir -p /root/vins_ws/src /tmp/vins_output/pose_graph
    ln -sfn /repo/camera_models /root/vins_ws/src/camera_models
    ln -sfn /repo/vins_estimator /root/vins_ws/src/vins_estimator
    ln -sfn /repo/loop_fusion /root/vins_ws/src/loop_fusion
    ln -sfn /repo/global_fusion /root/vins_ws/src/global_fusion
    cd /root/vins_ws
    catkin_make -DCMAKE_BUILD_TYPE=Release
    source devel/setup.bash
    exec roslaunch vins d435i_px4_vins.launch \
      config_file:=/repo/config/realsense_d435i/realsense_stereo_px4_imu_config.yaml \
      fcu_url:="${FCU_URL}" \
      run_camera:="${RUN_CAMERA}" \
      run_mavros:="${RUN_MAVROS}" \
      run_rviz:="${RUN_RVIZ}" \
      run_loop:="${RUN_LOOP}" \
      run_pose_printer:="${RUN_POSE_PRINTER}" \
      initial_reset:="${INITIAL_RESET}"
  '
