#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROS_DISTRO="${ROS_DISTRO:-noetic}"
WS_DIR="${WS_DIR:-$HOME/vins_ws}"
CONFIG_FILE="${CONFIG_FILE:-${REPO_DIR}/config/realsense_d435i/realsense_stereo_px4_imu_config.yaml}"
DEFAULT_FCU_DEV="/dev/serial/by-id/usb-Matek_HKUST_UAV_NxtPX4_0-if00"

if [[ -e "${DEFAULT_FCU_DEV}" ]]; then
  DEFAULT_FCU_URL="${DEFAULT_FCU_DEV}:921600"
else
  DEFAULT_FCU_URL="/dev/ttyACM0:921600"
fi

FCU_URL="${FCU_URL:-${DEFAULT_FCU_URL}}"
RUN_CAMERA="${RUN_CAMERA:-true}"
RUN_MAVROS="${RUN_MAVROS:-true}"
RUN_RVIZ="${RUN_RVIZ:-true}"
RUN_LOOP="${RUN_LOOP:-false}"
INITIAL_RESET="${INITIAL_RESET:-true}"

[[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]] || {
  echo "ERROR: ROS ${ROS_DISTRO} is not installed." >&2
  exit 1
}

[[ -f "${WS_DIR}/devel/setup.bash" ]] || {
  echo "ERROR: ${WS_DIR}/devel/setup.bash is missing. Run scripts/setup_wsl_native_noetic.sh build first." >&2
  exit 1
}

# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# shellcheck disable=SC1090
source "${WS_DIR}/devel/setup.bash"

mkdir -p /tmp/vins_output/pose_graph

exec roslaunch vins d435i_px4_vins.launch \
  config_file:="${CONFIG_FILE}" \
  fcu_url:="${FCU_URL}" \
  run_camera:="${RUN_CAMERA}" \
  run_mavros:="${RUN_MAVROS}" \
  run_rviz:="${RUN_RVIZ}" \
  run_loop:="${RUN_LOOP}" \
  initial_reset:="${INITIAL_RESET}"
