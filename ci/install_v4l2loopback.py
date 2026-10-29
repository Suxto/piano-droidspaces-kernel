#!/usr/bin/env python3
"""Add the pinned v4l2loopback release to one fresh GKI source tree."""

import argparse
from pathlib import Path
import subprocess

COMMIT = "0f9ee86760b7f2bea174b7e3e7a1d38845da0ab4"
CONFIG = "CONFIG_VIDEO_V4L2LOOPBACK=y"
SOURCE_FILES = ("v4l2loopback.c", "v4l2loopback.h", "v4l2loopback_formats.h")


def install(common: Path, source: Path) -> None:
    commit = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "HEAD"], text=True
    ).strip()
    if commit != COMMIT:
        raise ValueError("v4l2loopback source does not match the pinned release")
    subprocess.run(
        ["git", "-C", str(source), "diff", "--quiet", "HEAD", "--", *SOURCE_FILES],
        check=True,
    )
    media = common / "drivers/media"
    defconfig = common / "arch/arm64/configs/gki_defconfig"
    targets = (media / "Kconfig", media / "Makefile", defconfig)
    originals = [target.read_text() for target in targets]
    driver = media / "v4l2loopback"
    if driver.exists() or any("VIDEO_V4L2LOOPBACK" in text for text in originals):
        raise ValueError("v4l2loopback is already configured; use a fresh source tree")
    sources = {name: (source / name).read_text() for name in SOURCE_FILES}
    old = "static int devices = -1;"
    if sources["v4l2loopback.c"].count(old) != 1:
        raise ValueError("unexpected v4l2loopback initial-device configuration")
    sources["v4l2loopback.c"] = sources["v4l2loopback.c"].replace(
        old,
        "/* Do not allocate video nodes before Android's vendor drivers. */\n"
        "static int devices = 0;",
    )
    driver.mkdir()
    for name, text in sources.items():
        (driver / name).write_text(text)
    (driver / "Kconfig").write_text(
        'config VIDEO_V4L2LOOPBACK\n'
        '\tbool "V4L2 loopback camera bridge"\n'
        '\tdepends on VIDEO_DEV\n'
        '\thelp\n'
        '\t  Provide a virtual V4L2 device, not a physical camera driver.\n'
        '\t  Userspace must create the device and supply frames on demand.\n'
    )
    (driver / "Makefile").write_text(
        "obj-$(CONFIG_VIDEO_V4L2LOOPBACK) += v4l2loopback.o\n"
    )
    additions = (
        'source "drivers/media/v4l2loopback/Kconfig"',
        "obj-$(CONFIG_VIDEO_V4L2LOOPBACK) += v4l2loopback/",
        CONFIG,
    )
    for target, original, addition in zip(targets, originals, additions):
        target.write_text(original.rstrip("\n") + "\n" + addition + "\n")
    (driver / "SOURCE.txt").write_text(
        f"v4l2loopback_version=0.15.4\nv4l2loopback_commit={COMMIT}\n"
        "v4l2loopback_builtin=y\nv4l2loopback_initial_devices=0\n"
        "camera_feeder=not-installed\nboot_validation=not-tested\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("common", type=Path)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    install(args.common, args.source)
