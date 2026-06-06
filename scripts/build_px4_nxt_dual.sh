#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PX4_DIR="${PX4_DIR:-${REPO_DIR}/PX4-Autopilot}"
TARGET="${TARGET:-hkust_nxt-dual_default}"

[[ -d "${PX4_DIR}" ]] || {
  echo "ERROR: PX4 directory not found: ${PX4_DIR}" >&2
  exit 1
}

cd "${PX4_DIR}"
exec make "${TARGET}"
