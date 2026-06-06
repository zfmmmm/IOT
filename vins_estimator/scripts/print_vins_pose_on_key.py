#!/usr/bin/env python3
import math
import os
import select
import sys
import termios
import time
import tty

import rospy
from nav_msgs.msg import Odometry


class PoseKeyPrinter:
    def __init__(self):
        self.odom_topic = rospy.get_param("~odom_topic", "/vins_estimator/odometry")
        self.print_key = rospy.get_param("~print_key", "p")
        self.latest = None
        self.first = None
        self.previous = None
        self.count = 0
        self.tty_fd = None
        self.old_tty = None

        rospy.Subscriber(self.odom_topic, Odometry, self.odom_callback, queue_size=20)

    def odom_callback(self, msg):
        self.latest = msg

    def open_tty(self):
        try:
            self.tty_fd = os.open("/dev/tty", os.O_RDONLY | os.O_NONBLOCK)
            self.old_tty = termios.tcgetattr(self.tty_fd)
            tty.setcbreak(self.tty_fd)
            return True
        except Exception as exc:
            rospy.logerr("Cannot read keyboard from /dev/tty: %s", exc)
            return False

    def restore_tty(self):
        if self.tty_fd is not None:
            try:
                if self.old_tty is not None:
                    termios.tcsetattr(self.tty_fd, termios.TCSADRAIN, self.old_tty)
                os.close(self.tty_fd)
            except Exception:
                pass

    @staticmethod
    def yaw_from_quaternion(q):
        siny_cosp = 2.0 * (q.w * q.z + q.x * q.y)
        cosy_cosp = 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
        return math.atan2(siny_cosp, cosy_cosp)

    @staticmethod
    def pose_tuple(msg):
        p = msg.pose.pose.position
        q = msg.pose.pose.orientation
        return (p.x, p.y, p.z, PoseKeyPrinter.yaw_from_quaternion(q), msg.header.stamp.to_sec())

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
            print("\n[VINS POSE] No odometry received yet from %s" % self.odom_topic, flush=True)
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
            print("This is the reference mark. Return here and press '%s' again." % self.print_key, flush=True)
        else:
            dx, dy, dz, horizontal, distance_3d, dyaw = self.delta(current, self.first)
            print(
                "delta from mark #1: dx=% .6f m, dy=% .6f m, dz=% .6f m, horizontal=% .6f m, 3d=% .6f m, dyaw=% .3f deg"
                % (dx, dy, dz, horizontal, distance_3d, dyaw),
                flush=True,
            )

        if self.previous is not None:
            dx, dy, dz, horizontal, distance_3d, dyaw = self.delta(current, self.previous)
            print(
                "delta from previous: dx=% .6f m, dy=% .6f m, dz=% .6f m, horizontal=% .6f m, 3d=% .6f m, dyaw=% .3f deg"
                % (dx, dy, dz, horizontal, distance_3d, dyaw),
                flush=True,
            )
        print("=" * 72, flush=True)
        self.previous = current

    def run(self):
        if not self.open_tty():
            return

        print("", flush=True)
        print("[VINS POSE] Press '%s' or Enter in this terminal to print current VINS position." % self.print_key, flush=True)
        print("[VINS POSE] First print is the reference mark; later prints show loop error from mark #1.", flush=True)

        rate = rospy.Rate(20)
        try:
            while not rospy.is_shutdown():
                ready, _, _ = select.select([self.tty_fd], [], [], 0.0)
                if ready:
                    try:
                        data = os.read(self.tty_fd, 16).decode("utf-8", errors="ignore")
                    except BlockingIOError:
                        data = ""
                    if self.print_key in data or "\n" in data or "\r" in data:
                        self.print_pose()
                rate.sleep()
        finally:
            self.restore_tty()


def main():
    rospy.init_node("print_vins_pose_on_key")
    PoseKeyPrinter().run()


if __name__ == "__main__":
    main()
