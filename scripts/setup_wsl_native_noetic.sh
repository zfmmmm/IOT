#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-install}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROS_DISTRO="${ROS_DISTRO:-noetic}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:-focal}"
WS_DIR="${WS_DIR:-$HOME/vins_ws}"
INSTALL_PX4_DEPS="${INSTALL_PX4_DEPS:-false}"
BUILD_WORKSPACE="${BUILD_WORKSPACE:-true}"
BUILD_PX4="${BUILD_PX4:-false}"
SKIP_APT_UPGRADE="${SKIP_APT_UPGRADE:-true}"
APT_GET="sudo apt-get"

usage() {
  cat <<'EOF'
Usage:
  scripts/setup_wsl_native_noetic.sh install
  scripts/setup_wsl_native_noetic.sh build
  scripts/setup_wsl_native_noetic.sh check

Environment:
  WS_DIR=$HOME/vins_ws          Native catkin workspace path.
  INSTALL_PX4_DEPS=false       Install PX4 host-side build dependencies too.
  BUILD_WORKSPACE=true         Build the VINS catkin workspace during install.
  BUILD_PX4=false              Build PX4 with make hkust_nxt-dual_default during install.
  SKIP_APT_UPGRADE=true        Keep apt upgrade off by default for faster setup.

Notes:
  1. Run this inside Ubuntu 20.04 on WSL2.
  2. Clone the repo first, then run this script from the repo root.
  3. If PX4-Autopilot is empty, run:
       git submodule update --init --recursive
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 1
  }
}

ensure_ros_repo() {
  if [[ ! -f /etc/apt/sources.list.d/ros1-latest.list ]]; then
    sudo sh -c "echo 'deb http://packages.ros.org/ros/ubuntu ${UBUNTU_CODENAME} main' > /etc/apt/sources.list.d/ros1-latest.list"
  fi
  if ! apt-key list 2>/dev/null | grep -q "Open Robotics"; then
    curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | sudo apt-key add -
  fi
}

install_ros_and_system_deps() {
  ensure_ros_repo
  ${APT_GET} update
  if [[ "${SKIP_APT_UPGRADE}" != "true" ]]; then
    ${APT_GET} upgrade -y
  fi

  ${APT_GET} install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    python3-pip \
    python3-rosdep \
    python3-rosinstall \
    python3-rosinstall-generator \
    python3-vcstool \
    python3-catkin-tools \
    python3-wstool \
    libeigen3-dev \
    libgoogle-glog-dev \
    libgflags-dev \
    libsuitesparse-dev \
    libceres-dev \
    libopencv-dev \
    "ros-${ROS_DISTRO}-desktop-full" \
    "ros-${ROS_DISTRO}-cv-bridge" \
    "ros-${ROS_DISTRO}-tf" \
    "ros-${ROS_DISTRO}-image-transport" \
    "ros-${ROS_DISTRO}-camera-info-manager" \
    "ros-${ROS_DISTRO}-dynamic-reconfigure" \
    "ros-${ROS_DISTRO}-topic-tools" \
    "ros-${ROS_DISTRO}-image-view" \
    "ros-${ROS_DISTRO}-mavros" \
    "ros-${ROS_DISTRO}-mavros-extras" \
    "ros-${ROS_DISTRO}-realsense2-camera" \
    "ros-${ROS_DISTRO}-ddynamic-reconfigure" \
    "ros-${ROS_DISTRO}-rviz" \
    geographiclib-tools

  sudo /opt/ros/"${ROS_DISTRO}"/lib/mavros/install_geographiclib_datasets.sh || true

  if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    sudo rosdep init
  fi
  rosdep update
}

install_librealsense_repo() {
  if [[ ! -f /etc/apt/sources.list.d/librealsense.list ]]; then
    curl -fsSL https://librealsense.intel.com/Debian/librealsense.pgp | sudo apt-key add -
    sudo sh -c "echo 'deb https://librealsense.intel.com/Debian/apt-repo ${UBUNTU_CODENAME} main' > /etc/apt/sources.list.d/librealsense.list"
    ${APT_GET} update
  fi

  ${APT_GET} install -y --no-install-recommends \
    librealsense2-dkms \
    librealsense2-utils \
    librealsense2-dev \
    librealsense2-dbg
}

prepare_workspace() {
  mkdir -p "${WS_DIR}/src"
  ln -sfn "${REPO_DIR}/camera_models" "${WS_DIR}/src/camera_models"
  ln -sfn "${REPO_DIR}/vins_estimator" "${WS_DIR}/src/vins_estimator"
  ln -sfn "${REPO_DIR}/loop_fusion" "${WS_DIR}/src/loop_fusion"
  ln -sfn "${REPO_DIR}/global_fusion" "${WS_DIR}/src/global_fusion"
}

build_workspace() {
  prepare_workspace
  # shellcheck disable=SC1090
  source /opt/ros/"${ROS_DISTRO}"/setup.bash
  cd "${WS_DIR}"
  catkin_make -DCMAKE_BUILD_TYPE=Release
}

install_px4_deps() {
  [[ -d "${REPO_DIR}/PX4-Autopilot" ]] || {
    echo "WARN: PX4-Autopilot directory is missing; skipping PX4 dependency install." >&2
    return
  }
  sudo bash "${REPO_DIR}/PX4-Autopilot/Tools/setup/ubuntu.sh" --no-sim-tools
}

build_px4() {
  [[ -d "${REPO_DIR}/PX4-Autopilot" ]] || {
    echo "ERROR: PX4-Autopilot directory is missing." >&2
    exit 1
  }
  cd "${REPO_DIR}/PX4-Autopilot"
  make hkust_nxt-dual_default
}

check_install() {
  need_cmd roscore
  need_cmd rospack
  need_cmd catkin_make
  need_cmd rs-enumerate-devices
  need_cmd lsusb

  # shellcheck disable=SC1090
  source /opt/ros/"${ROS_DISTRO}"/setup.bash
  rospack find mavros >/dev/null
  rospack find realsense2_camera >/dev/null
  rospack find rviz >/dev/null

  if [[ -f "${WS_DIR}/devel/setup.bash" ]]; then
    # shellcheck disable=SC1090
    source "${WS_DIR}/devel/setup.bash"
    rospack find vins >/dev/null
    rospack find loop_fusion >/dev/null
  else
    echo "WARN: ${WS_DIR}/devel/setup.bash not found yet; run build mode." >&2
  fi

  echo
  echo "USB overview:"
  lsusb | grep -E 'Intel|RealSense|Matek|HKUST|PX4' || true
  echo
  echo "RealSense devices:"
  rs-enumerate-devices || true
  echo
  echo "Serial devices:"
  ls -l /dev/serial/by-id 2>/dev/null || echo "No /dev/serial/by-id yet"
}

case "${MODE}" in
  install)
    install_ros_and_system_deps
    install_librealsense_repo
    if [[ "${INSTALL_PX4_DEPS}" == "true" ]]; then
      install_px4_deps
    fi
    if [[ "${BUILD_WORKSPACE}" == "true" ]]; then
      build_workspace
    fi
    if [[ "${BUILD_PX4}" == "true" ]]; then
      build_px4
    fi
    check_install
    ;;
  build)
    build_workspace
    if [[ "${BUILD_PX4}" == "true" ]]; then
      build_px4
    fi
    ;;
  check)
    check_install
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "ERROR: unknown mode: ${MODE}" >&2
    usage
    exit 1
    ;;
esac
