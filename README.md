# Xiaomi Pad 8 Pro (`piano`) kernel build

GitHub Actions builder for the HyperOS OS4.0.5.0 kernel on Xiaomi Pad 8 Pro.
It compiles the `seventeen` ALXP kernel with the MizuSU kernel driver
(`helloxujia/mizusu`, tag `v4.1.3`), and enables the namespace, SysV IPC,
devtmpfs, cgroup, and networking options needed by Droidspaces 7.1. NTSync
is already present in this source tree and remains available as `ntsync.ko`.

The workflow downloads only public source code. Device firmware, boot
headers, signing keys, and other proprietary images are not committed.

Run **Build piano kernel** manually from the Actions tab. The uploaded suite
contains:

- `Image`
- `dtb/`
- `dtbo.img`
- `modules/vendor_boot/dlkm.cpio`
- `modules/vendor_dlkm/`
- `modules/system_dlkm/`
- `kernel-headers/`

The generated modules are signed with a fresh build key. The kernel embeds
`com.zayu.mizu` as the manager package, so it is paired with the MizuSU
manager rather than KernelSU-Next. Package and flash
the complete suite together; do not mix its kernel with stock modules.

The included build helper comes from
[`xiaomi-pad-8-pro-development/auto`](https://github.com/xiaomi-pad-8-pro-development/auto)
and retains its GPL-3.0 license.
