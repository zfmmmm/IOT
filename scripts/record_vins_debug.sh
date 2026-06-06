#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-vins-noetic-d435i-px4:latest}"
BAG_DIR="${BAG_DIR:-${REPO_DIR}/calibration/bags}"
LOG_DIR="${LOG_DIR:-${REPO_DIR}/calibration/logs}"
DURATION="${DURATION:-60}"
BAG_NAME="${BAG_NAME:-vins_move_debug_$(date +%Y%m%d_%H%M%S)}"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
MODE="${MODE:-auto}"
ROS_DISTRO="${ROS_DISTRO:-noetic}"
TOPICS=(
  /camera/infra1/image_rect_raw
  /camera/infra2/image_rect_raw
  /camera/infra1/camera_info
  /camera/infra2/camera_info
  /mavros/imu/data_raw
  /mavros/timesync_status
  /vins_estimator/odometry
  /vins_estimator/path
  /tf
  /tf_static
)

usage() {
  cat <<'USAGE'
Usage:
  scripts/record_vins_debug.sh

Run this in a second terminal while docker/run_d435i_px4.sh is already running.

Environment overrides:
  DURATION=60        Recording seconds. Use DURATION=0 to record until Ctrl-C.
  BAG_NAME=...      Output name without .bag.
  MODE=auto         auto/native/docker. Native is preferred on WSL.
  IMAGE=...         Docker image, default vins-noetic-d435i-px4:latest.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "${BAG_DIR}" "${LOG_DIR}"

LOCK_FILE="${BAG_DIR}/.vins_debug_record.lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "ERROR: another VINS debug recorder is already running." >&2
  exit 1
fi

DOCKER_TTY_ARGS=()
if [[ -t 0 ]]; then
  DOCKER_TTY_ARGS=(-it)
fi

echo "Recording VINS debug bag: ${BAG_DIR}/${BAG_NAME}.bag"
echo "Duration: ${DURATION}s"
echo "Stop with Ctrl-C if DURATION=0."

run_native() {
  # shellcheck disable=SC1090
  source "/opt/ros/${ROS_DISTRO}/setup.bash"

  if ! timeout 5s rostopic list >/dev/null 2>&1; then
    echo "ERROR: ROS master is not reachable. Start scripts/run_wsl_native_d435i_px4.sh first." >&2
    exit 2
  fi

  local bag="${BAG_DIR}/${BAG_NAME}.bag"
  local log="${LOG_DIR}/${BAG_NAME}_record.log"

  if [[ "${DURATION}" == "0" ]]; then
    rosbag record --buffsize=2048 --chunksize=768 -O "${bag}" "${TOPICS[@]}" 2>&1 | tee "${log}"
  else
    set +e
    timeout --signal=INT "${DURATION}" rosbag record --buffsize=2048 --chunksize=768 -O "${bag}" "${TOPICS[@]}" 2>&1 | tee "${log}"
    local code=${PIPESTATUS[0]}
    set -e
    if [[ "${code}" != "0" && "${code}" != "124" && "${code}" != "130" ]]; then
      exit "${code}"
    fi
  fi
}

run_docker() {
  if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "ERROR: missing Docker image: ${IMAGE}" >&2
    exit 1
  fi

  docker run --rm "${DOCKER_TTY_ARGS[@]}" \
    --net=host \
    -e BAG_NAME="${BAG_NAME}" \
    -e DURATION="${DURATION}" \
    -v "${REPO_DIR}:/repo:rw" \
    "${IMAGE}" \
    bash -lc '
      set -euo pipefail
      source /opt/ros/noetic/setup.bash

      if ! timeout 5s rostopic list >/dev/null 2>&1; then
        echo "ERROR: ROS master is not reachable. Start docker/run_d435i_px4.sh first." >&2
        exit 2
      fi

      BAG="/repo/calibration/bags/${BAG_NAME}.bag"
      LOG="/repo/calibration/logs/${BAG_NAME}_record.log"
      TOPICS=(
        /camera/infra1/image_rect_raw
        /camera/infra2/image_rect_raw
        /camera/infra1/camera_info
        /camera/infra2/camera_info
        /mavros/imu/data_raw
        /mavros/timesync_status
        /vins_estimator/odometry
        /vins_estimator/path
        /tf
        /tf_static
      )

      if [[ "${DURATION}" == "0" ]]; then
        rosbag record --buffsize=2048 --chunksize=768 -O "${BAG}" "${TOPICS[@]}" 2>&1 | tee "${LOG}"
      else
        set +e
        timeout --signal=INT "${DURATION}" rosbag record --buffsize=2048 --chunksize=768 -O "${BAG}" "${TOPICS[@]}" 2>&1 | tee "${LOG}"
        code=${PIPESTATUS[0]}
        set -e
        if [[ "${code}" != "0" && "${code}" != "124" && "${code}" != "130" ]]; then
          exit "${code}"
        fi
      fi
    '

  docker run --rm \
    -v "${REPO_DIR}:/repo:rw" \
    --entrypoint /bin/bash \
    "${IMAGE}" \
    -lc "chown ${HOST_UID}:${HOST_GID} /repo/calibration/bags/${BAG_NAME}.bag* /repo/calibration/logs/${BAG_NAME}_record.log 2>/dev/null || true" \
    >/dev/null 2>&1 || true
}

case "${MODE}" in
  auto)
    if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
      run_native
    else
      run_docker
    fi
    ;;
  native)
    run_native
    ;;
  docker)
    run_docker
    ;;
  *)
    echo "ERROR: unknown MODE=${MODE}; expected auto/native/docker." >&2
    exit 1
    ;;
esac

if [[ -f "${BAG_DIR}/${BAG_NAME}.bag" ]]; then
  echo "Recorded: ${BAG_DIR}/${BAG_NAME}.bag"
elif [[ -f "${BAG_DIR}/${BAG_NAME}.bag.active" ]]; then
  echo "WARN: bag is still active/unindexed: ${BAG_DIR}/${BAG_NAME}.bag.active" >&2
  echo "Run: rosbag reindex ${BAG_DIR}/${BAG_NAME}.bag.active" >&2
else
  echo "ERROR: rosbag did not create an output bag." >&2
  exit 3
fi
