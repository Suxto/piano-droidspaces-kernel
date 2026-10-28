# Xiaomi Pad 8 Pro (`piano`) kernel build

Candidate GitHub Actions builder targeting HyperOS OS4.0.5.0 on Xiaomi Pad 8 Pro.
**The previous custom package failed to boot. Build success is not device boot
validation. Do not flash without a separately authorized test and a working
stock Fastboot recovery path.**

It compiles the pinned `seventeen` ALXP kernel with the MizuSU kernel driver
(`helloxujia/mizusu`, pinned revision), and enables the namespace, SysV IPC,
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

The generated modules are signed with a fresh build key. The public certificate
and real depmod metadata are included; private signing keys are never uploaded.
The platform Full LTO/CFI/KASAN profile is retained, with the upstream SLUB LTO
workaround and the MTE asm-volatile fix. The kernel embeds
`com.zayu.mizu` as the manager package, so it is paired with the MizuSU
manager rather than KernelSU-Next. Package and flash
the complete suite together; do not mix its kernel with stock modules. Stock
recovery/TWRP on this device has no independent kernel and is not a guaranteed
fallback after replacing boot.

The included build helper comes from
[`xiaomi-pad-8-pro-development/auto`](https://github.com/xiaomi-pad-8-pro-development/auto)
and retains its GPL-3.0 license.
