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
RUN_POSE_PRINTER="${RUN_POSE_PRINTER:-true}"
# RealSense device reset is helpful on native Ubuntu, but under WSL the USB
# device can disappear from the attached session and never come back.
INITIAL_RESET="${INITIAL_RESET:-false}"

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

cleanup() {
  trap - EXIT INT TERM
  if [[ -n "${LAUNCH_PID:-}" ]] && kill -0 "${LAUNCH_PID}" 2>/dev/null; then
    kill "${LAUNCH_PID}" 2>/dev/null || true
    wait "${LAUNCH_PID}" || true
  fi
}

trap cleanup EXIT INT TERM

roslaunch vins d435i_px4_vins.launch \
  config_file:="${CONFIG_FILE}" \
  fcu_url:="${FCU_URL}" \
  run_camera:="${RUN_CAMERA}" \
  run_mavros:="${RUN_MAVROS}" \
  run_rviz:="${RUN_RVIZ}" \
  run_loop:="${RUN_LOOP}" \
  run_pose_printer:="${RUN_POSE_PRINTER}" \
  initial_reset:="${INITIAL_RESET}" &
LAUNCH_PID=$!

if [[ "${RUN_POSE_PRINTER}" == "true" ]]; then
  if [[ -t 0 ]]; then
    echo "[VINS POSE] Press p or Enter in this terminal to print current VINS position."
    while kill -0 "${LAUNCH_PID}" 2>/dev/null; do
      if IFS= read -r -s -n1 -t 0.2 key; then
        if [[ -z "${key}" || "${key}" == "p" || "${key}" == "P" ]]; then
          rostopic pub -1 /vins_estimator/print_pose std_msgs/Empty "{}" >/dev/null
        fi
      fi
    done
  else
    echo "[VINS POSE] No interactive TTY detected; skipping keyboard listener."
  fi
fi

wait "${LAUNCH_PID}"
