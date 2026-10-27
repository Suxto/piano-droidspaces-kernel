#!/usr/bin/env bash
set -euo pipefail

KERNEL_URL="${KERNEL_URL:-https://github.com/xiaomi-pad-8-pro-development/android_kernel_xiaomi_piano.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-seventeen}"
KERNEL_COMMIT="${KERNEL_COMMIT:-}"
CLANG_URL="${CLANG_URL:-https://github.com/ag-sdc-ci/prebuilts_host_clang-r510928.git}"
CLANG_BRANCH="${CLANG_BRANCH:-universal}"
DTC_URL="${DTC_URL:-https://github.com/CodeLinaro-mirror/la_kernel_platform_external_dtc.git}"

ROOT_DIR="${ROOT_DIR:-${PWD}/.build}"
KERNEL_DIR="${KERNEL_DIR:-${ROOT_DIR}/android_kernel_xiaomi_piano}"
CLANG_ROOT="${CLANG_ROOT:-${ROOT_DIR}/clang-r510928}"
LLVM_DIR="${LLVM_DIR:-${CLANG_ROOT}/bin}"
ROM_DIR="${ROM_DIR:-${ROOT_DIR}/rom}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
PREBUILT_KERNEL_DIR="${PREBUILT_KERNEL_DIR:-${ROOT_DIR}/piano-kernel}"
KEY_DIR="${KEY_DIR:-${ROOT_DIR}/keys}"
MODULE_SIG_KEY="${MODULE_SIG_KEY:-${KEY_DIR}/piano-module-signing.pem}"

mkdir -p "${ROOT_DIR}" "${ROM_DIR}/prebuilts/kernel-build-tools/linux-x86/bin" \
    "${ROM_DIR}/system/libufdt/utils/src" "${PREBUILT_KERNEL_DIR}" "${KEY_DIR}"

echo "== System information =="
uname -a
nproc
free -h
df -h

if [ ! -d "${KERNEL_DIR}/.git" ]; then
    git clone --depth=1 --branch "${KERNEL_BRANCH}" \
        --recurse-submodules --shallow-submodules \
        "${KERNEL_URL}" "${KERNEL_DIR}"
fi

git -C "${KERNEL_DIR}" submodule update --init --recursive --depth 1

if [ -n "${KERNEL_COMMIT}" ]; then
    git -C "${KERNEL_DIR}" fetch --depth=1 origin "${KERNEL_COMMIT}"
    git -C "${KERNEL_DIR}" checkout --detach FETCH_HEAD
    git -C "${KERNEL_DIR}" submodule update --init --recursive --depth 1
fi

if [ ! -d "${CLANG_ROOT}/.git" ]; then
    git clone --depth=1 --branch "${CLANG_BRANCH}" "${CLANG_URL}" "${CLANG_ROOT}"
fi

# The tree already contains NTSync, including ntsync.ko in piano's stock
# vendor_dlkm module list. A config fragment is enough here; applying the
# generic NTSync patch would try to add the same driver a second time.
cat "${GITHUB_WORKSPACE}/config/piano-extra.config" \
    >> "${KERNEL_DIR}/arch/arm64/configs/piano_ksu.config"

ln -sfn "$(command -v pahole)" \
    "${ROM_DIR}/prebuilts/kernel-build-tools/linux-x86/bin/pahole"
curl -L --fail --retry 4 \
    "https://raw.githubusercontent.com/LineageOS/android_system_libufdt/lineage-24.0/utils/src/mkdtboimg.py" \
    -o "${ROM_DIR}/system/libufdt/utils/src/mkdtboimg.py"

openssl genrsa -out "${KEY_DIR}/private.pem" 4096
openssl req -new -x509 -key "${KEY_DIR}/private.pem" \
    -out "${KEY_DIR}/certificate.pem" -days 3650 -sha256 \
    -subj "/CN=piano-droidspaces-kernel"
cat "${KEY_DIR}/private.pem" "${KEY_DIR}/certificate.pem" > "${MODULE_SIG_KEY}"

export DTC_REPO="${DTC_URL}"
export ROOT_DIR KERNEL_DIR LLVM_DIR ROM_DIR OUT_DIR PREBUILT_KERNEL_DIR
export MODULE_SIG_KEY
export KSU=1
export COMMIT=0

"${GITHUB_WORKSPACE}/build.sh"

echo "== Verifying required kernel configuration =="
required_config=(
    "CONFIG_KSU=y"
    "CONFIG_KSU_SUSFS=y"
    "CONFIG_NTSYNC=m"
    "CONFIG_SYSVIPC=y"
    "CONFIG_POSIX_MQUEUE=y"
    "CONFIG_IPC_NS=y"
    "CONFIG_PID_NS=y"
    "CONFIG_USER_NS=y"
    "CONFIG_DEVTMPFS=y"
    "CONFIG_CGROUP_DEVICE=y"
    "CONFIG_CGROUP_PIDS=y"
    "CONFIG_TMPFS_XATTR=y"
)

for option in "${required_config[@]}"; do
    if ! grep -qx "${option}" "${OUT_DIR}/.config"; then
        echo "[error] missing required config: ${option}" >&2
        exit 1
    fi
done

test -s "${PREBUILT_KERNEL_DIR}/Image"
test -s "${PREBUILT_KERNEL_DIR}/dtbo.img"
test -s "${PREBUILT_KERNEL_DIR}/modules/vendor_boot/dlkm.cpio"
lz4 -dc "${PREBUILT_KERNEL_DIR}/modules/vendor_boot/dlkm.cpio" \
    | cpio -it --quiet 2>/dev/null \
    | grep -qx 'lib/modules/ntsync.ko'

KERNEL_HEAD="$(git -C "${KERNEL_DIR}" rev-parse HEAD)"
KERNEL_SHORT="$(git -C "${KERNEL_DIR}" rev-parse --short=12 HEAD)"
KERNEL_RELEASE="$(cat "${OUT_DIR}/include/config/kernel.release")"
ARTIFACT_NAME="piano-kernel-${KERNEL_SHORT}-droidspaces-ksu"

cat > "${ROOT_DIR}/manifest.txt" <<EOF
device=piano
kernel_source=${KERNEL_URL}
kernel_branch=${KERNEL_BRANCH}
kernel_commit=${KERNEL_HEAD}
kernel_release=${KERNEL_RELEASE}
variant=KernelSU-Next+SUSFS
ntsync=in-tree
droidspaces=7.1-compatible config
clang=$(git -C "${CLANG_ROOT}" rev-parse HEAD)
build_host=$(uname -a)
build_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

cp "${OUT_DIR}/.config" "${ROOT_DIR}/piano-kernel.config"
cp "${OUT_DIR}/System.map" "${ROOT_DIR}/piano-System.map"

tar --owner=0 --group=0 -C "${PREBUILT_KERNEL_DIR}" \
    -czf "${ROOT_DIR}/${ARTIFACT_NAME}.tar.gz" .

(
    cd "${ROOT_DIR}"
    sha256sum "${ARTIFACT_NAME}.tar.gz" manifest.txt piano-kernel.config \
        piano-System.map > SHA256SUMS
)

echo "ARTIFACT_NAME=${ARTIFACT_NAME}" >> "${GITHUB_ENV}"
echo "KERNEL_RELEASE=${KERNEL_RELEASE}" >> "${GITHUB_ENV}"
echo "== Build complete: ${ARTIFACT_NAME} (${KERNEL_RELEASE}) =="
