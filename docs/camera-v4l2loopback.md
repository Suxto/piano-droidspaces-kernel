# SukiSU GKI: V4L2 camera bridge candidate

This change targets only `.github/workflows/gcross-sukisu.yml`, based on
successful run `40700202646` at `da83923`. The old piano/MizuSU workflow
and the Official KernelSU workflow are unchanged.

## What is built

- The existing Android 15 / 6.6.118 GKI, SukiSU, KPM, SUSFS, Droidspaces
  and NTSync configuration remains in place.
- v4l2loopback **0.15.4**, pinned to
  `0f9ee86760b7f2bea174b7e3e7a1d38845da0ab4`, is built into the Image with
  `CONFIG_VIDEO_V4L2LOOPBACK=y` and depends on `CONFIG_VIDEO_DEV=y`.
- The upstream SukiSU hook is kept as readable shell rather than base64.
- The driver defaults to **zero initial video devices**. It registers its
  control interface but does not open any physical camera. A userspace
  administrator can create a virtual video device after Android's vendor
  devices have registered. This avoids changing their boot-time V4L2 minor
  allocation by automatically claiming a video node first.
- The artifact records the driver commit, zero-device default and
  `boot_validation=not-tested`. It is a build candidate, not a proven
  boot-compatible release. No automatic device installation is added.

The existing upstream builder relaxes KMI/protected-export checks. This
change does not alter that policy, and a successful build must not be used
as evidence that stock vendor modules, camera HAL or the device will boot.

## What is NOT implemented by this build

Building a virtual V4L2 driver does not start Android Camera2, feed camera
frames, configure permissions, or provide an on-demand camera service.
The present Anland camera compatibility script converts a PipeWire source
from NV21 to YUY2. That conversion remains a userspace responsibility.

There is no camera feeder installed or enabled by this change. In
particular, it does **not** add an always-running Camera2/GStreamer capture
pipeline or turn off Android camera privacy indicators.

## Contract for the later userspace bridge

The pinned driver has `V4L2_EVENT_PRI_CLIENT_USAGE`, with event type
`V4L2_EVENT_PRIVATE_START + 0x08E00000 + 1`. Its first payload field is a
native `uint32_t` named `count`. In this release the value is **0 or 1**,
meaning whether a capture stream is active, not a global count of all
camera users.

A later bridge should:

1. Create a verified loopback device at an unused number, e.g. video60,
   after vendor devices exist. Do not replace video0/video1: on piano they
   are Qualcomm camera request/synchronization interfaces, not webcams.
2. Initialize a supported, fixed video format and capability state without
   opening the physical camera. With exclusive capabilities, capture is
   advertised only when an output stream is active or `keep_format` is
   enabled; merely loading the driver is not sufficient for enumeration.
3. Subscribe with `V4L2_EVENT_SUB_FL_SEND_INITIAL`. Start this bridge's
   Anland/PipeWire camera subscription only when capture becomes active.
   Device enumeration/open/QUERYCAP alone must not trigger Camera2.
4. On capture stop, `REQBUFS(0)` or fd close, drop the bridge's real camera
   subscription and clear retained image data/serve a blank frame. The
   driver's read() path also starts a capture stream, so it needs the same
   handling as STREAMON. Software probing with a real capture stream can
   legitimately activate the camera briefly.
5. On exit, disconnect, invalid state or permission denial, release this
   bridge's camera resources. Keep one owner of the subscription, and
   resynchronize from the initial event on restart rather than retaining
   stale active state. Do not close another Anland window's or Android
   app's camera ownership.
6. Preserve Android's permission/privacy controls and limit the virtual
   node to the intended container user/group. Do not use global chmod 666
   or disable SELinux. Android may retain its privacy indicator briefly
   after the camera is released; do not hide the indicator to emulate stop.

This contract needs implementation and device validation before claiming
that the virtual camera is ready for normal applications. No camera
frames were captured while preparing this change.

## Checks and rollout

Run the integration checks with:

```sh
bash -n ci/sukisu_features.sh
python3 -m unittest discover -s tests -p test_v4l2loopback.py -v
```

The workflow verifies the resulting configuration contains the camera
option along with the existing root/container features, then publishes a
separately named candidate artifact and source manifest.

A full CI build, an independently authorized device boot test, native
Android camera regression checks, and an independently authorized
on-demand camera test are still required. Do not flash this candidate
without renewed authorization and the preserved stock rescue route.

To revert the build change, revert this camera integration commit. No
existing workflow, camera permissions, container service or device state
is migrated by this code.
