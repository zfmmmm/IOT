#!/usr/bin/env python3
import rospy
from sensor_msgs.msg import Image
import message_filters


class StereoThrottle:
    def __init__(self):
        self.rate = float(rospy.get_param("~rate", 10.0))
        self.slop = float(rospy.get_param("~slop", 0.005))
        self.in0 = rospy.get_param("~in0", "/camera/infra1/image_rect_raw")
        self.in1 = rospy.get_param("~in1", "/camera/infra2/image_rect_raw")
        self.out0 = rospy.get_param("~out0", "/kalibr/cam0/image_raw")
        self.out1 = rospy.get_param("~out1", "/kalibr/cam1/image_raw")
        self.period = rospy.Duration(1.0 / self.rate)
        self.last_stamp = None

        self.pub0 = rospy.Publisher(self.out0, Image, queue_size=5)
        self.pub1 = rospy.Publisher(self.out1, Image, queue_size=5)
        sub0 = message_filters.Subscriber(self.in0, Image)
        sub1 = message_filters.Subscriber(self.in1, Image)
        sync = message_filters.ApproximateTimeSynchronizer(
            [sub0, sub1], queue_size=20, slop=self.slop, allow_headerless=False
        )
        sync.registerCallback(self.callback)
        self.sync = sync

        rospy.loginfo(
            "StereoThrottle %s + %s -> %s + %s at %.2f Hz, slop %.4f s",
            self.in0,
            self.in1,
            self.out0,
            self.out1,
            self.rate,
            self.slop,
        )

    def callback(self, img0, img1):
        stamp = img0.header.stamp
        if self.last_stamp is not None and stamp - self.last_stamp < self.period:
            return
        self.last_stamp = stamp
        self.pub0.publish(img0)
        self.pub1.publish(img1)


if __name__ == "__main__":
    rospy.init_node("kalibr_stereo_throttle")
    StereoThrottle()
    rospy.spin()
