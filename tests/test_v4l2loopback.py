"""Run with python3 -m unittest discover -s tests -p test_v4l2loopback.py."""

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "camera_builder", ROOT / "ci/install_v4l2loopback.py"
)
assert spec is not None and spec.loader is not None
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class CameraBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.common = Path(self.temp.name) / "common"
        self.source = Path(self.temp.name) / "source"
        self.source.mkdir()
        (self.common / "drivers/media").mkdir(parents=True)
        configs = self.common / "arch/arm64/configs"
        configs.mkdir(parents=True)
        (configs / "gki_defconfig").write_text("CONFIG_KPM=y\nCONFIG_SYSVIPC=y\n")
        (self.common / "drivers/media/Kconfig").write_text("# existing media config\n")
        (self.common / "drivers/media/Makefile").write_text("# existing media build\n")
        for name in builder.SOURCE_FILES:
            text = "static int devices = -1;\n" if name.endswith(".c") else "/* header */\n"
            (self.source / name).write_text(text)
        self.head = mock.patch.object(
            builder.subprocess, "check_output", return_value=builder.COMMIT + "\n"
        ).start()
        self.addCleanup(mock.patch.stopall)
        self.diff = mock.patch.object(builder.subprocess, "run").start()

    def test_builtin_wiring_and_no_initial_video_nodes(self):
        builder.install(self.common, self.source)
        driver = self.common / "drivers/media/v4l2loopback"
        self.assertIn("static int devices = 0;", (driver / "v4l2loopback.c").read_text())
        self.assertIn('source "drivers/media/v4l2loopback/Kconfig"',
                      (self.common / "drivers/media/Kconfig").read_text())
        self.assertIn("obj-$(CONFIG_VIDEO_V4L2LOOPBACK) += v4l2loopback/",
                      (self.common / "drivers/media/Makefile").read_text())
        config = (self.common / "arch/arm64/configs/gki_defconfig").read_text()
        self.assertEqual(config, "CONFIG_KPM=y\nCONFIG_SYSVIPC=y\n" + builder.CONFIG + "\n")
        self.assertIn("boot_validation=not-tested", (driver / "SOURCE.txt").read_text())
        self.assertIn("camera_feeder=not-installed", (driver / "SOURCE.txt").read_text())
        self.assertIn("depends on VIDEO_DEV", (driver / "Kconfig").read_text())
        self.assertEqual((self.source / "v4l2loopback.c").read_text(),
                         "static int devices = -1;\n")

    def test_wrong_commit_does_not_modify_kernel(self):
        self.head.return_value = "wrong-commit\n"
        with self.assertRaises(ValueError):
            builder.install(self.common, self.source)
        self.assertFalse((self.common / "drivers/media/v4l2loopback").exists())
        self.diff.assert_not_called()

    def test_modified_release_source_does_not_modify_kernel(self):
        self.diff.side_effect = subprocess.CalledProcessError(1, "git diff")
        with self.assertRaises(subprocess.CalledProcessError):
            builder.install(self.common, self.source)
        self.assertFalse((self.common / "drivers/media/v4l2loopback").exists())

    def test_repeated_install_is_rejected_without_more_config(self):
        builder.install(self.common, self.source)
        config = self.common / "arch/arm64/configs/gki_defconfig"
        original = config.read_text()
        with self.assertRaises(ValueError):
            builder.install(self.common, self.source)
        self.assertEqual(config.read_text(), original)

    def test_unexpected_initial_device_code_is_rejected(self):
        (self.source / "v4l2loopback.c").write_text("static int devices = 2;\n")
        with self.assertRaises(ValueError):
            builder.install(self.common, self.source)
        self.assertFalse((self.common / "drivers/media/v4l2loopback").exists())

    def test_workflow_keeps_sukisu_profile_and_verifies_camera_config(self):
        workflow = (ROOT / ".github/workflows/gcross-sukisu.yml").read_text()
        hook = (ROOT / "ci/sukisu_features.sh").read_text()
        self.assertIn(builder.COMMIT, workflow)
        self.assertIn("CONFIG_VIDEO_V4L2LOOPBACK", workflow)
        self.assertIn("DROIDSPACES=\"678\"", workflow)
        self.assertIn("USE_KPM=\"enabled\"", workflow)
        self.assertIn("b59170724cdc05bf5dee8d8a8b182c5f1ddd60e3", hook)
        self.assertIn("0606e19afae93ffc88e53883dbf3cfced62a7b59", hook)
        self.assertIn("CONFIG_KSU_SUSFS=y", hook)
        self.assertIn("install_v4l2loopback.py", hook)


if __name__ == "__main__":
    unittest.main()
