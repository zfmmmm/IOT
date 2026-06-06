#!/usr/bin/env python3
import rospy
from dynamic_reconfigure.client import Client


def main():
    rospy.init_node("disable_realsense_projector")
    stereo_module = rospy.get_param("~stereo_module", "/camera/stereo_module")
    timeout = rospy.get_param("~timeout", 20.0)

    deadline = rospy.Time.now() + rospy.Duration(timeout)
    client = None
    while not rospy.is_shutdown() and rospy.Time.now() < deadline:
        try:
            client = Client(stereo_module, timeout=2.0)
            break
        except Exception as exc:
            rospy.logwarn_throttle(2.0, "Waiting for %s dynamic reconfigure: %s", stereo_module, exc)
            rospy.sleep(0.5)

    if client is None:
        rospy.logerr("Could not connect to %s; D435i projector was not changed", stereo_module)
        return

    try:
        client.update_configuration({"emitter_enabled": 0, "laser_power": 0.0})
        rospy.loginfo("D435i infrared projector disabled on %s", stereo_module)
    except Exception as exc:
        rospy.logerr("Failed to disable D435i projector on %s: %s", stereo_module, exc)


if __name__ == "__main__":
    main()
