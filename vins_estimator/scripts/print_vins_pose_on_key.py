#!/usr/bin/env python3
import math
import time

import rospy
from nav_msgs.msg import Odometry
from std_msgs.msg import Empty


class PoseKeyPrinter:
    def __init__(self):
        self.odom_topic = rospy.get_param("~odom_topic", "/vins_estimator/odometry")
        self.trigger_topic = rospy.get_param("~trigger_topic", "/vins_estimator/print_pose")
        self.latest = None
        self.first = None
        self.previous = None
        self.count = 0

        rospy.Subscriber(self.odom_topic, Odometry, self.odom_callback, queue_size=20)
        rospy.Subscriber(self.trigger_topic, Empty, self.trigger_callback, queue_size=20)

    def odom_callback(self, msg):
        self.latest = msg

    def trigger_callback(self, _msg):
        self.print_pose()

    @staticmethod
    def yaw_from_quaternion(q):
        siny_cosp = 2.0 * (q.w * q.z + q.x * q.y)
        cosy_cosp = 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
        return math.atan2(siny_cosp, cosy_cosp)

    @staticmethod
    def pose_tuple(msg):
        p = msg.pose.pose.position
        q = msg.pose.pose.orientation
        return (
            p.x,
            p.y,
            p.z,
            PoseKeyPrinter.yaw_from_quaternion(q),
            msg.header.stamp.to_sec(),
        )

    @staticmethod
    def delta(a, b):
        dx = a[0] - b[0]
        dy = a[1] - b[1]
        dz = a[2] - b[2]
        horizontal = math.hypot(dx, dy)
        distance_3d = math.sqrt(dx * dx + dy * dy + dz * dz)
        dyaw = math.atan2(math.sin(a[3] - b[3]), math.cos(a[3] - b[3]))
        return dx, dy, dz, horizontal, distance_3d, math.degrees(dyaw)

    def print_pose(self):
        if self.latest is None:
            print(
                "\n[VINS POSE] No odometry received yet from %s" % self.odom_topic,
                flush=True,
            )
            return

        current = self.pose_tuple(self.latest)
        if self.first is None:
            self.first = current

        self.count += 1
        stamp_text = time.strftime("%Y-%m-%d %H:%M:%S")
        x, y, z, yaw, ros_stamp = current

        print("\n" + "=" * 72, flush=True)
        print("[VINS POSE MARK #%d] %s" % (self.count, stamp_text), flush=True)
        print("ROS stamp: %.6f" % ros_stamp, flush=True)
        print("position: x=% .6f m, y=% .6f m, z=% .6f m" % (x, y, z), flush=True)
        print("yaw: % .3f deg" % math.degrees(yaw), flush=True)

        if self.count == 1:
            print("This is the reference mark. Return here and trigger another print.", flush=True)
        else:
            dx, dy, dz, horizontal, distance_3d, dyaw = self.delta(current, self.first)
            print(
                "delta from mark #1: dx=% .6f m, dy=% .6f m, dz=% .6f m, horizontal=% .6f m, 3d=% .6f m, dyaw=% .3f deg"
                % (dx, dy, dz, horizontal, distance_3d, dyaw),
                flush=True,
            )

        if self.previous is not None:
            dx, dy, dz, horizontal, distance_3d, dyaw = self.delta(
                current, self.previous
            )
            print(
                "delta from previous: dx=% .6f m, dy=% .6f m, dz=% .6f m, horizontal=% .6f m, 3d=% .6f m, dyaw=% .3f deg"
                % (dx, dy, dz, horizontal, distance_3d, dyaw),
                flush=True,
            )
        print("=" * 72, flush=True)
        self.previous = current

    def run(self):
        print("", flush=True)
        print(
            "[VINS POSE] Waiting for trigger messages on %s to print current VINS position."
            % self.trigger_topic,
            flush=True,
        )
        print(
            "[VINS POSE] First print is the reference mark; later prints show loop error from mark #1.",
            flush=True,
        )
        rospy.spin()


def main():
    rospy.init_node("print_vins_pose_on_key")
    PoseKeyPrinter().run()


if __name__ == "__main__":
    main()
