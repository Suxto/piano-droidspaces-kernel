#!/usr/bin/env bash
# This overrides only the pinned upstream SukiSU integration entrypoint.
apply_kernelsu() {
    local root="$1"
    cd "$root"
    curl -fLSs https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/b59170724cdc05bf5dee8d8a8b182c5f1ddd60e3/kernel/setup.sh -o /tmp/sukisu-setup.sh
    bash /tmp/sukisu-setup.sh b59170724cdc05bf5dee8d8a8b182c5f1ddd60e3
    python3 - <<'PY'
from pathlib import Path
p = Path('KernelSU/kernel/policy/allowlist.c')
s = p.read_text()
old = '        /* fall through */\n    case 3:'
assert s.count(old) == 1, 'Unexpected migration switch context'
p.write_text(s.replace(old, '        fallthrough;\n    case 3:'))
PY
    git clone https://github.com/ShirkNeko/susfs4ksu.git /home/runner/susfs4ksu
    git -C /home/runner/susfs4ksu checkout 0606e19afae93ffc88e53883dbf3cfced62a7b59
    curl -fLSs https://raw.githubusercontent.com/zzh20188/GKI_KernelSU_SUSFS/ed9ca42709dfb23eae6034d67482d1c35631b85e/scripts/susfs_fixes/apply.sh -o /tmp/apply-susfs.sh
    export ANDROID_VERSION=android15 KERNEL_VERSION=6.6 KSU_VARIANT=SukiSU OS_PATCH_LEVEL=2026-01 SUB_LEVEL=118
    export KERNEL_ROOT="$root" SUSFS4KSU=/home/runner/susfs4ksu KERNEL_PATCHES=/home/runner/unused LEGACY_SUKISU_CONFIG=""
    bash /tmp/apply-susfs.sh
    cd "$root"
    if find common -name '*.rej' -print -quit | grep -q .; then
        echo 'Unresolved patch rejects'; return 1
    fi
    cat >> common/arch/arm64/configs/gki_defconfig <<'CONFIG'
CONFIG_KPM=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG
    git -C KernelSU rev-parse HEAD > /home/runner/gki-source-manifest.txt
    git -C /home/runner/susfs4ksu rev-parse HEAD >> /home/runner/gki-source-manifest.txt
    python3 "$GITHUB_WORKSPACE/ci/install_v4l2loopback.py" "$root/common" "$GITHUB_WORKSPACE/v4l2loopback-source"
    cat common/drivers/media/v4l2loopback/SOURCE.txt >> /home/runner/gki-source-manifest.txt
}
