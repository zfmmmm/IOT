#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_SCRIPT="${REPO_DIR}/docker/run_d435i_px4.sh"
POSE_NODE="${REPO_DIR}/vins_estimator/scripts/print_vins_pose_on_key.py"

grep -q '/vins_estimator/print_pose' "${POSE_NODE}"
grep -q 'rostopic pub -1 /vins_estimator/print_pose std_msgs/Empty' "${DOCKER_SCRIPT}"
