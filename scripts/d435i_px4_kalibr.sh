#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${DATA_DIR:-${REPO_DIR}/calibration}"
BAG_DIR="${DATA_DIR}/bags"
RESULT_DIR="${DATA_DIR}/results"
LOG_DIR="${DATA_DIR}/logs"

ROS_IMAGE="${ROS_IMAGE:-vins-noetic-d435i-px4:latest}"
KALIBR_IMAGE="${KALIBR_IMAGE:-kalibr:latest}"
TARGET_YAML="${TARGET_YAML:-${REPO_DIR}/aprilgrid_6x6.yaml}"
IMU_YAML="${IMU_YAML:-${REPO_DIR}/config/realsense_d435i/px4_imu_bmi088.yaml}"

DEFAULT_FCU_DEV="/dev/serial/by-id/usb-Matek_HKUST_UAV_NxtPX4_0-if00"
if [ -e "${DEFAULT_FCU_DEV}" ]; then
  DEFAULT_FCU_URL="${DEFAULT_FCU_DEV}:921600"
else
  DEFAULT_FCU_URL="/dev/ttyACM0:921600"
fi
FCU_URL="${FCU_URL:-${DEFAULT_FCU_URL}}"

CAM_RATE="${CAM_RATE:-10}"
BAG_FREQ="${BAG_FREQ:-4}"
DURATION="${DURATION:-150}"
COUNTDOWN="${COUNTDOWN:-10}"
PREVIEW="${PREVIEW:-true}"
BAG_NAME="${BAG_NAME:-d435i_px4_$(date +%Y%m%d_%H%M%S)}"
CAM_MODELS="${CAM_MODELS:-pinhole-radtan pinhole-radtan}"
APPROX_SYNC="${APPROX_SYNC:-0.03}"
KALIBR_EXTRA_ARGS="${KALIBR_EXTRA_ARGS:-}"
KALIBR_IMU_EXTRA_ARGS="${KALIBR_IMU_EXTRA_ARGS:-}"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
DOCKER_TTY_ARGS=()
if [ -t 0 ]; then
  DOCKER_TTY_ARGS=(-it)
fi

usage() {
  cat <<'USAGE'
Usage:
  scripts/d435i_px4_kalibr.sh check
  scripts/d435i_px4_kalibr.sh record
  scripts/d435i_px4_kalibr.sh calibrate-cam <bag>
  scripts/d435i_px4_kalibr.sh calibrate-imu <bag> [camchain.yaml]
  scripts/d435i_px4_kalibr.sh pack <bag>

Environment overrides:
  DURATION=150         Recording seconds. Use DURATION=0 to record until Ctrl-C.
  PREVIEW=true         Show live left/right infrared preview windows.
  CAM_RATE=10          Throttle camera topics for Kalibr.
  BAG_FREQ=4           Frame extraction frequency used by Kalibr.
  FCU_URL=...          MAVROS serial URL, default is NxtPX4 by-id at 921600.
  BAG_NAME=...         Output bag name without .bag.
  CAM_MODELS="pinhole-radtan pinhole-radtan"

Calibration motion:
  1. Keep the rig still for the first 5-10 seconds after recording starts.
  2. Keep the AprilGrid visible in both preview windows.
  3. Move slowly through yaw, pitch, roll, left/right, up/down, forward/back.
  4. Put the target near image center, corners, edges, close and far.
  5. Avoid blur, reflections, and losing the board for long stretches.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

mkdirs() {
  mkdir -p "${BAG_DIR}" "${RESULT_DIR}/cam" "${RESULT_DIR}/imu" "${LOG_DIR}"
}

abs_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "$(pwd)/${path}"
  fi
}

to_data_path() {
  local path
  path="$(abs_path "$1")"
  [[ -e "${path}" ]] || die "file does not exist: ${path}"
  case "${path}" in
    "${DATA_DIR}"/*) printf '/data/%s\n' "${path#"${DATA_DIR}/"}" ;;
    *) die "file must be under ${DATA_DIR}: ${path}" ;;
  esac
}

to_repo_path() {
  local path
  path="$(abs_path "$1")"
  [[ -e "${path}" ]] || die "file does not exist: ${path}"
  case "${path}" in
    "${REPO_DIR}"/*) printf '/repo/%s\n' "${path#"${REPO_DIR}/"}" ;;
    *) die "file must be under ${REPO_DIR}: ${path}" ;;
  esac
}

latest_camchain() {
  find "${RESULT_DIR}/cam" "${BAG_DIR}" -type f \( -name 'camchain-*.yaml' -o -name '*-camchain.yaml' \) -printf '%T@ %p\n' 2>/dev/null \
    | sort -n | tail -1 | cut -d' ' -f2-
}

collect_bag_outputs() {
  local base="$1"
  local dest="$2"
  mkdir -p "${dest}"
  find "${BAG_DIR}" -maxdepth 1 -type f -name "${base}-*" ! -name '*.bag' -exec cp -f {} "${dest}/" \;
}

fix_data_ownership() {
  local base="$1"
  docker run --rm \
    -v "${DATA_DIR}:/data:rw" \
    --entrypoint /bin/bash \
    "${ROS_IMAGE}" \
    -lc "chown -R ${HOST_UID}:${HOST_GID} /data/results /data/bags/${base}-* 2>/dev/null || true" \
    >/dev/null 2>&1 || true
}

print_target() {
  echo "AprilGrid target:"
  sed -n '1,20p' "${TARGET_YAML}"
  echo
}

check() {
  mkdirs
  echo "[host] repo: ${REPO_DIR}"
  echo "[host] data: ${DATA_DIR}"
  echo "[host] fcu_url: ${FCU_URL}"
  print_target

  docker image inspect "${ROS_IMAGE}" >/dev/null 2>&1 \
    || die "missing Docker image: ${ROS_IMAGE}"
  docker image inspect "${KALIBR_IMAGE}" >/dev/null 2>&1 \
    || die "missing Docker image: ${KALIBR_IMAGE}"

  echo "[host] USB devices:"
  if ! lsusb | grep -E 'RealSense|Intel|HKUST|NxtPX4|Matek|Altium'; then
    echo "WARN: D435i/PX4 USB device was not detected by this host session."
  fi
  echo
  echo "[host] serial devices:"
  if ! ls -l /dev/serial/by-id 2>/dev/null; then
    echo "WARN: /dev/serial/by-id is not available; FCU_URL will fall back to /dev/ttyACM0:921600."
  fi
  echo

  echo "[docker:${ROS_IMAGE}] ROS packages:"
  docker run --rm --entrypoint /bin/bash "${ROS_IMAGE}" -lc \
    'set -e; source /opt/ros/noetic/setup.bash; rospack find realsense2_camera; rospack find mavros; rospack find image_view; rospack find topic_tools'

  echo
  echo "[docker:${KALIBR_IMAGE}] Kalibr commands:"
  docker run --rm --entrypoint /bin/bash "${KALIBR_IMAGE}" -lc \
    'set -e; source /catkin_ws/devel/setup.bash; KALIBR_DIR="$(rospack find kalibr)"; echo "${KALIBR_DIR}"; test -x "${KALIBR_DIR}/python/kalibr_calibrate_cameras"; test -x "${KALIBR_DIR}/python/kalibr_calibrate_imu_camera"; echo OK'

  echo
  echo "Check passed. Next: scripts/d435i_px4_kalibr.sh record"
}

record() {
  mkdirs
  [[ -f "${TARGET_YAML}" ]] || die "missing target yaml: ${TARGET_YAML}"

  if [[ "${PREVIEW}" = "true" && -z "${DISPLAY:-}" ]]; then
    echo "WARN: DISPLAY is empty; preview windows probably cannot open." >&2
  fi

  xhost +local:docker >/dev/null 2>&1 || true

  docker run --rm "${DOCKER_TTY_ARGS[@]}" \
    --net=host \
    --privileged \
    -e DISPLAY="${DISPLAY:-}" \
    -e QT_X11_NO_MITSHM=1 \
    -e FCU_URL="${FCU_URL}" \
    -e CAM_RATE="${CAM_RATE}" \
    -e DURATION="${DURATION}" \
    -e COUNTDOWN="${COUNTDOWN}" \
    -e PREVIEW="${PREVIEW}" \
    -e BAG_NAME="${BAG_NAME}" \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v /dev:/dev \
    -v "${REPO_DIR}:/repo:rw" \
    -v "${DATA_DIR}:/data:rw" \
    "${ROS_IMAGE}" \
    bash -lc '
      set -euo pipefail
      source /opt/ros/noetic/setup.bash
      mkdir -p /data/bags /data/logs
      export ROS_LOG_DIR=/data/logs/ros_record_${BAG_NAME}

      pids=()
      cleanup() {
        set +e
        for pid in "${pids[@]:-}"; do
          kill "${pid}" >/dev/null 2>&1 || true
        done
        sleep 1
        for pid in "${pids[@]:-}"; do
          kill -9 "${pid}" >/dev/null 2>&1 || true
        done
      }
      trap cleanup EXIT INT TERM

      roscore >/data/logs/roscore_${BAG_NAME}.log 2>&1 &
      pids+=("$!")
      until rostopic list >/dev/null 2>&1; do sleep 0.2; done

      roslaunch realsense2_camera rs_camera.launch \
        enable_fisheye:=false \
        enable_depth:=false \
        enable_confidence:=false \
        enable_color:=false \
        enable_gyro:=false \
        enable_accel:=false \
        enable_infra1:=true \
        enable_infra2:=true \
        infra_width:=640 \
        infra_height:=480 \
        infra_fps:=30 \
        enable_sync:=true \
        align_depth:=false \
        initial_reset:=true \
        >/data/logs/realsense_${BAG_NAME}.log 2>&1 &
      pids+=("$!")

      roslaunch mavros px4.launch fcu_url:="${FCU_URL}" gcs_url:="" \
        >/data/logs/mavros_${BAG_NAME}.log 2>&1 &
      pids+=("$!")

      wait_msg() {
        local topic="$1"
        local seconds="$2"
        echo "Waiting for ${topic} ..."
        timeout "${seconds}" bash -lc "rostopic echo -n 1 ${topic} >/dev/null" \
          || { echo "Timed out waiting for ${topic}" >&2; return 1; }
      }

      wait_msg /camera/infra1/image_rect_raw 40
      wait_msg /camera/infra2/image_rect_raw 40
      wait_msg /mavros/imu/data_raw 40

      echo "Disabling D435i infrared projector ..."
      rosrun dynamic_reconfigure dynparam get /camera/stereo_module \
        >/data/logs/realsense_projector_${BAG_NAME}.log 2>&1 || true
      rosrun dynamic_reconfigure dynparam set /camera/stereo_module emitter_enabled 0 \
        >>/data/logs/realsense_projector_${BAG_NAME}.log 2>&1 || true
      rosrun dynamic_reconfigure dynparam set /camera/stereo_module laser_power 0 \
        >>/data/logs/realsense_projector_${BAG_NAME}.log 2>&1 || true
      rosrun dynamic_reconfigure dynparam get /camera/stereo_module \
        >>/data/logs/realsense_projector_${BAG_NAME}.log 2>&1 || true

      python3 /repo/scripts/kalibr_stereo_throttle.py _rate:="${CAM_RATE}" _slop:=0.005 \
        >/data/logs/stereo_throttle_${BAG_NAME}.log 2>&1 &
      pids+=("$!")

      wait_msg /kalibr/cam0/image_raw 20
      wait_msg /kalibr/cam1/image_raw 20

      if [[ "${PREVIEW}" = "true" ]]; then
        rosrun image_view image_view __name:=kalibr_preview_left image:=/kalibr/cam0/image_raw _autosize:=true \
          >/data/logs/preview_left_${BAG_NAME}.log 2>&1 &
        pids+=("$!")
        rosrun image_view image_view __name:=kalibr_preview_right image:=/kalibr/cam1/image_raw _autosize:=true \
          >/data/logs/preview_right_${BAG_NAME}.log 2>&1 &
        pids+=("$!")
      fi

      echo
      if [[ "${PREVIEW}" = "true" ]]; then
        echo "Preview is running if your desktop allows X11 windows."
      else
        echo "Preview disabled."
      fi
      echo "Recording starts after countdown. First 5-10 seconds: keep the rig still."
      for n in $(seq "${COUNTDOWN}" -1 1); do
        printf "\rStarting rosbag in %2d s ..." "${n}"
        sleep 1
      done
      printf "\n"

      BAG="/data/bags/${BAG_NAME}.bag"
      TOPICS="
        /kalibr/cam0/image_raw
        /kalibr/cam1/image_raw
        /mavros/imu/data_raw
        /mavros/timesync_status
        /camera/infra1/camera_info
        /camera/infra2/camera_info
      "

      echo "Recording ${BAG}"
      if [[ "${DURATION}" = "0" ]]; then
        rosbag record --buffsize=2048 --chunksize=768 -O "${BAG}" ${TOPICS}
      else
        timeout --signal=INT "${DURATION}" rosbag record --buffsize=2048 --chunksize=768 -O "${BAG}" ${TOPICS} || code="$?"
        if [[ "${code:-0}" != "124" && "${code:-0}" != "0" ]]; then
          exit "${code}"
        fi
      fi

      echo
      echo "Bag written:"
      rosbag info "${BAG}"
    '

  echo
  echo "Recorded bag: ${BAG_DIR}/${BAG_NAME}.bag"
  echo "Next: scripts/d435i_px4_kalibr.sh calibrate-cam ${BAG_DIR}/${BAG_NAME}.bag"
}

kalibr_docker() {
  docker run --rm "${DOCKER_TTY_ARGS[@]}" \
    --net=host \
    -e DISPLAY="${DISPLAY:-}" \
    -e QT_X11_NO_MITSHM=1 \
    -e KALIBR_MANUAL_FOCAL_LENGTH_INIT=1 \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v "${REPO_DIR}:/repo:rw" \
    -v "${DATA_DIR}:/data:rw" \
    --entrypoint /bin/bash \
    "${KALIBR_IMAGE}" \
    -lc "$1"
}

calibrate_cam() {
  mkdirs
  local bag="${1:-}"
  [[ -n "${bag}" ]] || die "missing bag path"
  local bag_data target_repo base out_dir
  bag_data="$(to_data_path "${bag}")"
  target_repo="$(to_repo_path "${TARGET_YAML}")"
  base="$(basename "${bag}")"
  base="${base%.bag}"
  out_dir="/data/results/cam/${base}_cam"

  echo "Running camera calibration:"
  echo "  bag: ${bag_data}"
  echo "  target: ${target_repo}"
  echo "  output: ${out_dir}"
  echo "  models: ${CAM_MODELS}"

  kalibr_docker "
    set -euo pipefail
    set +u
    source /catkin_ws/devel/setup.bash
    set -u
    mkdir -p '${out_dir}'
    cd '${out_dir}'
    rosrun kalibr kalibr_calibrate_cameras \
      --bag '${bag_data}' \
      --target '${target_repo}' \
      --models ${CAM_MODELS} \
      --topics /kalibr/cam0/image_raw /kalibr/cam1/image_raw \
      --approx-sync '${APPROX_SYNC}' \
      --bag-freq '${BAG_FREQ}' \
      ${KALIBR_EXTRA_ARGS}
  "

  fix_data_ownership "${base}"
  collect_bag_outputs "${base}" "${RESULT_DIR}/cam/${base}_cam"

  echo
  echo "Camera calibration outputs:"
  find "${RESULT_DIR}/cam/${base}_cam" -maxdepth 1 -type f | sort
  echo
  echo "Next: scripts/d435i_px4_kalibr.sh calibrate-imu ${bag} \$(find ${RESULT_DIR}/cam/${base}_cam -name '*camchain*.yaml' | head -1)"
}

calibrate_imu() {
  mkdirs
  local bag="${1:-}"
  local camchain="${2:-}"
  [[ -n "${bag}" ]] || die "missing bag path"
  if [[ -z "${camchain}" ]]; then
    camchain="$(latest_camchain)"
  fi
  [[ -n "${camchain}" ]] || die "missing camchain yaml; pass it explicitly"

  local bag_data cam_repo_or_data target_repo imu_repo base out_dir
  bag_data="$(to_data_path "${bag}")"
  target_repo="$(to_repo_path "${TARGET_YAML}")"
  imu_repo="$(to_repo_path "${IMU_YAML}")"
  base="$(basename "${bag}")"
  base="${base%.bag}"
  out_dir="/data/results/imu/${base}_imu"

  camchain="$(abs_path "${camchain}")"
  if [[ "${camchain}" == "${REPO_DIR}"/* ]]; then
    cam_repo_or_data="/repo/${camchain#"${REPO_DIR}/"}"
  elif [[ "${camchain}" == "${DATA_DIR}"/* ]]; then
    cam_repo_or_data="/data/${camchain#"${DATA_DIR}/"}"
  else
    die "camchain must be under ${REPO_DIR} or ${DATA_DIR}: ${camchain}"
  fi

  echo "Running camera-IMU calibration:"
  echo "  bag: ${bag_data}"
  echo "  camchain: ${cam_repo_or_data}"
  echo "  imu: ${imu_repo}"
  echo "  target: ${target_repo}"
  echo "  output: ${out_dir}"

  kalibr_docker "
    set -euo pipefail
    set +u
    source /catkin_ws/devel/setup.bash
    set -u
    mkdir -p '${out_dir}'
    cd '${out_dir}'
    rosrun kalibr kalibr_calibrate_imu_camera \
      --bag '${bag_data}' \
      --cams '${cam_repo_or_data}' \
      --imu '${imu_repo}' \
      --target '${target_repo}' \
      --bag-freq '${BAG_FREQ}' \
      ${KALIBR_IMU_EXTRA_ARGS}
  "

  fix_data_ownership "${base}"
  collect_bag_outputs "${base}" "${RESULT_DIR}/imu/${base}_imu"

  echo
  echo "Camera-IMU calibration outputs:"
  find "${RESULT_DIR}/imu/${base}_imu" -maxdepth 1 -type f | sort
  echo
  echo "Send me the camchain and imu result YAML/PDF, then I will write the VINS config conversion."
}

pack() {
  mkdirs
  local bag="${1:-}"
  [[ -n "${bag}" ]] || die "missing bag path"
  local bag_abs base archive
  bag_abs="$(abs_path "${bag}")"
  [[ -f "${bag_abs}" ]] || die "missing bag: ${bag_abs}"
  base="$(basename "${bag_abs}")"
  base="${base%.bag}"
  archive="${DATA_DIR}/${base}_kalibr_package.tar.gz"
  tar -C "${REPO_DIR}" -czf "${archive}" \
    aprilgrid_6x6.yaml \
    config/realsense_d435i/px4_imu_bmi088.yaml \
    -C "${DATA_DIR}" \
    "bags/${base}.bag" \
    results
  echo "Package written: ${archive}"
}

cmd="${1:-help}"
shift || true
case "${cmd}" in
  help|-h|--help) usage ;;
  check) check "$@" ;;
  record) record "$@" ;;
  calibrate-cam) calibrate_cam "$@" ;;
  calibrate-imu) calibrate_imu "$@" ;;
  pack) pack "$@" ;;
  *) usage; die "unknown command: ${cmd}" ;;
esac
