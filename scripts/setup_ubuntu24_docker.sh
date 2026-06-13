#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROS_BASE_IMAGE="${ROS_BASE_IMAGE:-vins-noetic-d435i:latest}"
ROS_IMAGE="${ROS_IMAGE:-vins-noetic-d435i-px4:latest}"
KALIBR_IMAGE="${KALIBR_IMAGE:-kalibr:latest}"
SKIP_DOCKER_INSTALL="${SKIP_DOCKER_INSTALL:-false}"
BUILD_KALIBR="${BUILD_KALIBR:-auto}"
KALIBR_REPO="${KALIBR_REPO:-https://github.com/ethz-asl/kalibr.git}"
KALIBR_BUILD_DIR="${KALIBR_BUILD_DIR:-/tmp/kalibr-docker-build}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/setup_ubuntu24_docker.sh

Environment overrides:
  SKIP_DOCKER_INSTALL=true   Do not install Docker packages.
  BUILD_KALIBR=auto         auto/true/false. auto builds only if kalibr:latest is missing.
  ROS_BASE_IMAGE=...        Default: vins-noetic-d435i:latest.
  ROS_IMAGE=...             Default: vins-noetic-d435i-px4:latest.
  KALIBR_IMAGE=...          Default: kalibr:latest.

After setup, logout/login once if this script added your user to the docker group.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1; then
    return
  fi
  if [[ "${SKIP_DOCKER_INSTALL}" == "true" ]]; then
    echo "Docker is missing and SKIP_DOCKER_INSTALL=true." >&2
    exit 1
  fi

  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

ensure_docker_access() {
  sudo systemctl enable --now docker >/dev/null 2>&1 || sudo service docker start
  if ! groups "${USER}" | grep -qw docker; then
    sudo usermod -aG docker "${USER}"
    echo
    echo "Your user was added to the docker group."
    echo "Logout/login once, then rerun this script if docker still says permission denied."
    echo
  fi
}

build_vins_images() {
  docker build -f "${REPO_DIR}/docker/Dockerfile.noetic-d435i" \
    -t "${ROS_BASE_IMAGE}" \
    "${REPO_DIR}"

  docker build -f "${REPO_DIR}/docker/Dockerfile.noetic-d435i-px4" \
    --build-arg BASE_IMAGE="${ROS_BASE_IMAGE}" \
    -t "${ROS_IMAGE}" \
    "${REPO_DIR}"
}

build_kalibr_image_if_needed() {
  case "${BUILD_KALIBR}" in
    false)
      echo "Skipping Kalibr image build because BUILD_KALIBR=false."
      return
      ;;
    auto)
      if docker image inspect "${KALIBR_IMAGE}" >/dev/null 2>&1; then
        echo "Kalibr image already exists: ${KALIBR_IMAGE}"
        return
      fi
      ;;
    true)
      ;;
    *)
      echo "ERROR: BUILD_KALIBR must be auto, true, or false." >&2
      exit 1
      ;;
  esac

  rm -rf "${KALIBR_BUILD_DIR}"
  git clone --depth 1 "${KALIBR_REPO}" "${KALIBR_BUILD_DIR}"
  docker build -t "${KALIBR_IMAGE}" "${KALIBR_BUILD_DIR}"
}

check_images() {
  docker image inspect "${ROS_IMAGE}" >/dev/null
  if ! docker image inspect "${KALIBR_IMAGE}" >/dev/null 2>&1; then
    echo
    echo "WARN: ${KALIBR_IMAGE} is missing. VINS localization can run, but Kalibr commands need this image."
    echo "Build it later with: BUILD_KALIBR=true scripts/setup_ubuntu24_docker.sh"
  fi
}

install_docker_if_needed
ensure_docker_access
build_vins_images
build_kalibr_image_if_needed
check_images

cat <<EOF

Ubuntu 24.04 Docker setup finished.

Next:
  ./scripts/d435i_px4_kalibr.sh check
  RUN_RVIZ=true RUN_LOOP=false ./docker/run_d435i_px4.sh
EOF
