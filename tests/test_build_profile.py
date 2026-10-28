import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class BuildProfileTests(unittest.TestCase):
    def test_features_remain_enabled_without_overriding_platform_profile(self):
        fragment = (ROOT / "config/piano-mizu.config").read_text()
        required = (
            "CONFIG_KSU=y", "CONFIG_KSU_MANUAL_SU=y", "CONFIG_NTSYNC=m",
            "CONFIG_SYSVIPC=y", "CONFIG_POSIX_MQUEUE=y", "CONFIG_IPC_NS=y",
            "CONFIG_PID_NS=y", "CONFIG_USER_NS=y", "CONFIG_DEVTMPFS=y",
            "CONFIG_CGROUP_DEVICE=y", "CONFIG_CGROUP_PIDS=y",
            "CONFIG_CGROUP_FREEZER=y", "CONFIG_CFS_BANDWIDTH=y",
        )
        for option in required:
            self.assertIn(option, fragment.splitlines())
        for line in fragment.splitlines():
            self.assertFalse(any(name in line for name in (
                "CONFIG_LTO_", "CONFIG_CFI_", "CONFIG_KASAN", "CONFIG_DEBUG_INFO",
            )), line)

    def test_mte_patch_is_valid_and_changes_only_two_asm_statements(self):
        patch = ROOT / "patches/mte-volatile.patch"
        result = subprocess.run(
            ["git", "apply", "--numstat", str(patch)],
            cwd=ROOT, capture_output=True, text=True, check=True,
        )
        self.assertEqual(result.stdout.strip(), "2\t2\tarch/arm64/include/asm/mte-kasan.h")
        additions = [line for line in patch.read_text().splitlines()
                     if line.startswith("+") and not line.startswith("+++")]
        self.assertEqual(len(additions), 2)
        self.assertTrue(all("asm volatile" in line for line in additions))

    def test_shell_scripts_parse(self):
        subprocess.run(["bash", "-n", str(ROOT / "build.sh")], check=True)
        subprocess.run(["bash", "-n", str(ROOT / "build-action.sh")], check=True)


if __name__ == "__main__":
    unittest.main()
