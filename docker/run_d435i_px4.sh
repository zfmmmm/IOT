# #!/usr/bin/env bash
# set -euo pipefail

# REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# IMAGE="${IMAGE:-vins-noetic-d435i-px4:latest}"
# DEFAULT_FCU_DEV="/dev/serial/by-id/usb-Matek_HKUST_UAV_NxtPX4_0-if00"
# if [ -e "${DEFAULT_FCU_DEV}" ]; then
#   DEFAULT_FCU_URL="${DEFAULT_FCU_DEV}:921600"
# else
#   DEFAULT_FCU_URL="/dev/ttyACM0:921600"
# fi
# FCU_URL="${FCU_URL:-${DEFAULT_FCU_URL}}"
# RUN_CAMERA="${RUN_CAMERA:-true}"
# RUN_MAVROS="${RUN_MAVROS:-true}"
# RUN_RVIZ="${RUN_RVIZ:-false}"
# RUN_LOOP="${RUN_LOOP:-false}"
# RUN_POSE_PRINTER="${RUN_POSE_PRINTER:-true}"
# INITIAL_RESET="${INITIAL_RESET:-true}"

# if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
#   docker build -f "${REPO_DIR}/docker/Dockerfile.noetic-d435i-px4" -t "${IMAGE}" "${REPO_DIR}"
# fi

# mkdir -p /tmp/vins_output/pose_graph
# xhost +local:docker >/dev/null 2>&1 || true

# docker run --rm -it \
#   --net=host \
#   --privileged \
#   -e DISPLAY="${DISPLAY:-}" \
#   -e QT_X11_NO_MITSHM=1 \
#   -e FCU_URL="${FCU_URL}" \
#   -e RUN_CAMERA="${RUN_CAMERA}" \
#   -e RUN_MAVROS="${RUN_MAVROS}" \
#   -e RUN_RVIZ="${RUN_RVIZ}" \
#   -e RUN_LOOP="${RUN_LOOP}" \
#   -e RUN_POSE_PRINTER="${RUN_POSE_PRINTER}" \
#   -e INITIAL_RESET="${INITIAL_RESET}" \
#   -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
#   -v /tmp/vins_output:/tmp/vins_output:rw \
#   -v /dev:/dev \
#   -v "${REPO_DIR}:/repo:rw" \
#   "${IMAGE}" \
#   bash -lc '
#     set -euo pipefail
#     source /opt/ros/noetic/setup.bash
#     mkdir -p /root/vins_ws/src /tmp/vins_output/pose_graph
#     ln -sfn /repo/camera_models /root/vins_ws/src/camera_models
#     ln -sfn /repo/vins_estimator /root/vins_ws/src/vins_estimator
#     ln -sfn /repo/loop_fusion /root/vins_ws/src/loop_fusion
#     ln -sfn /repo/global_fusion /root/vins_ws/src/global_fusion
#     cd /root/vins_ws
#     catkin_make -DCMAKE_BUILD_TYPE=Release
#     source devel/setup.bash
#     exec roslaunch vins d435i_px4_vins.launch \
#       config_file:=/repo/config/realsense_d435i/realsense_stereo_px4_imu_config.yaml \
#       fcu_url:="${FCU_URL}" \
#       run_camera:="${RUN_CAMERA}" \
#       run_mavros:="${RUN_MAVROS}" \
#       run_rviz:="${RUN_RVIZ}" \
#       run_loop:="${RUN_LOOP}" \
#       run_pose_printer:="${RUN_POSE_PRINTER}" \
#       initial_reset:="${INITIAL_RESET}"
#   '
#!/usr/bin/env bash
# 开启严格模式：-e 遇到错误退出，-u 遇到未定义变量退出，-o pipefail 管道中任意命令失败则整个管道失败
set -euo pipefail

# 获取当前脚本所在目录的上一级目录，作为仓库的根目录绝对路径
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 定义默认的 Docker 镜像名称，支持通过环境变量 IMAGE 覆盖
IMAGE="${IMAGE:-vins-noetic-d435i-px4:latest}"

# 自动检测默认的飞控（FCU）串口设备路径（以 Matek/PX4 的特定 USB ID 为优先）
DEFAULT_FCU_DEV="/dev/serial/by-id/usb-Matek_HKUST_UAV_NxtPX4_0-if00"
if [ -e "${DEFAULT_FCU_DEV}" ]; then
  # 如果特定的飞控设备存在，设置对应的波特率为 921600
  DEFAULT_FCU_URL="${DEFAULT_FCU_DEV}:921600"
else
  # 如果找不到特定设备，降级使用通用的 /dev/ttyACM0 接口
  DEFAULT_FCU_URL="/dev/ttyACM0:921600"
fi

# 最终传递给 MAVROS 的飞控连接 URL，支持环境变量覆盖
FCU_URL="${FCU_URL:-${DEFAULT_FCU_URL}}"

# 各种功能组件的开关变量，默认开启相机、MAVROS 和位姿打印，关闭 Rviz 和回环检测
RUN_CAMERA="${RUN_CAMERA:-true}"
RUN_MAVROS="${RUN_MAVROS:-true}"
RUN_RVIZ="${RUN_RVIZ:-false}"
RUN_LOOP="${RUN_LOOP:-false}"
RUN_POSE_PRINTER="${RUN_POSE_PRINTER:-true}"
INITIAL_RESET="${INITIAL_RESET:-true}"

# 检查本地是否存在指定的 Docker 镜像，若不存在则现场触发 docker build 构建
if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  docker build -f "${REPO_DIR}/docker/Dockerfile.noetic-d435i-px4" -t "${IMAGE}" "${REPO_DIR}"
fi

# 创建用于持久化存储 VINS 编译产物（build, devel）以及位姿图输出的目录
# 这样即便容器被 --rm 销毁，编译好的二进制文件和中间件依然存在于宿主机上（实现增量编译）
CACHE_DIR="/tmp/vins_ws_cache"
mkdir -p "${CACHE_DIR}/build" "${CACHE_DIR}/devel" /tmp/vins_output/pose_graph

# 允许本地所有用户（包括 Docker 容器内的 root 用户）访问宿主机的 X11 显示服务，供 Rviz 绘图
xhost +local:docker >/dev/null 2>&1 || true

# 提示：为了保证 Bash 正确解析续行符，以下 docker run 命令块参数之间严禁插入任何 # 注释
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
  -v "${CACHE_DIR}/build:/root/vins_ws/build:rw" \
  -v "${CACHE_DIR}/devel:/root/vins_ws/devel:rw" \
  "${IMAGE}" \
  bash -lc '
    # 容器内部执行的脚本，同样开启严格错误检查
    set -euo pipefail
    
    # 环境变量注入：引入 ROS Noetic 的官方核心环境变量
    source /opt/ros/noetic/setup.bash
    
    # 确保容器内的目标路径结构完整
    mkdir -p /root/vins_ws/src /tmp/vins_output/pose_graph
    
    # 将挂载进容器的物理源码目录（/repo）通过软链接形式接入到 ROS 工作空间的 src 下
    ln -sfn /repo/camera_models /root/vins_ws/src/camera_models
    ln -sfn /repo/vins_estimator /root/vins_ws/src/vins_estimator
    ln -sfn /repo/loop_fusion /root/vins_ws/src/loop_fusion
    ln -sfn /repo/global_fusion /root/vins_ws/src/global_fusion
    
    # 切换到工作空间根目录
    cd /root/vins_ws
    
    # 执行编译。由于 build 和 devel 被挂载到了宿主机，第二次启动时 CMake 会自动识别已有符号进行增量编译。
    # 如果检测到源码没有任何修改，此步将耗时不到 1 秒，直接跳过全量构建过程。
    catkin_make -DCMAKE_BUILD_TYPE=Release
    
    # 引入刚刚编译/更新完毕的本工作空间的 ROS 环境变量（包含编译出的 VINS 各个节点）
    source devel/setup.bash
    
    cleanup() {
      trap - EXIT INT TERM
      if [[ -n "${LAUNCH_PID:-}" ]] && kill -0 "${LAUNCH_PID}" 2>/dev/null; then
        kill "${LAUNCH_PID}" 2>/dev/null || true
        wait "${LAUNCH_PID}" || true
      fi
    }

    trap cleanup EXIT INT TERM

    roslaunch vins d435i_px4_vins.launch \
      config_file:=/repo/config/realsense_d435i/realsense_stereo_px4_imu_config.yaml \
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
  '
