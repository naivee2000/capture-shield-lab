"""Resource ownership and false-green controls; no macOS permissions or apps used."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("ui_run", Path(__file__).resolve().parents[2] / "scripts/ui_run.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
completion_spec = importlib.util.spec_from_file_location("verify_output", Path(__file__).resolve().parents[2] / "scripts/verify-test-output.py")
completion = importlib.util.module_from_spec(completion_spec)
completion_spec.loader.exec_module(completion)


class VerdictTests(unittest.TestCase):
    def test_native_zero_or_incomplete_execution_is_not_a_pass(self):
        for text in ("", "Build complete!", "◇ Test run started.\n", "◇ Test run started.\n✔ Test run with 0 tests passed after 0.1 seconds.\n"):
            self.assertFalse(completion.completed(text))

    def test_each_native_test_process_needs_its_own_completion(self):
        good = "◇ Test run started.\n✔ Test run with 69 tests in 12 suites passed after 2.0 seconds.\n"
        self.assertTrue(completion.completed(good))
        self.assertTrue(completion.completed(good + good))
        self.assertFalse(completion.completed(good + "◇ Test run started.\n"))
    def test_zero_skipped_partial_and_failed_are_not_success(self):
        for code, counts in [(0, {}), (0, {"passedTests": 0}), (0, {"passedTests": 5}),
                             (0, {"passedTests": 7, "skippedTests": 1}),
                             (0, {"passedTests": 7, "failedTests": 1}), (65, {"passedTests": 7})]:
            self.assertFalse(runner.result_passed(code, runner.result_counts(counts)))
        self.assertTrue(runner.result_passed(0, runner.result_counts({"passedTests": 7})))
        for bad in (-1, True, "6"):
            with self.assertRaises(ValueError): runner.result_counts({"passedTests": bad})

    def test_missing_or_wrong_application_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Wrong.app"
            with self.assertRaises(ValueError): runner.validate_application(app, "test.id")
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "personal.app"}))
            with self.assertRaises(ValueError): runner.validate_application(app, "test.id")

    def test_xctestrun_target_formats(self):
        self.assertEqual(list(runner.targets({"TestConfigurations": [{"TestTargets": [{"Name": "UI"}]}]})), [{"Name": "UI"}])
        self.assertEqual(list(runner.targets({"UI": {"Name": "UI"}, "__xctestrun_metadata__": {}})), [{"Name": "UI"}])


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.runs = self.root / "artifacts/ui-runs"
        self.base = self.runs / "ui-unit"
        self.base.mkdir(parents=True)
        self.data = {"schema": 1, "owner": runner.OWNER, "run_id": "ui-unit", "image": False,
                     "bundle_prefix": "dev.naivee2000.captureshield.uitest.ui-unit",
                     "state": "finished", "summary_saved": True}
        runner.write_json(self.base / "manifest.json", self.data)
        runner.write_json(self.base / "summary.json", {"run_id": "ui-unit", "status": "pass"})
        (self.base / "work").mkdir()
        (self.base / "work/file").write_text("synthetic")
        self.root_patch = patch.object(runner, "ROOT", self.root)
        self.runs_patch = patch.object(runner, "RUNS", self.runs)
        self.temp_patch = patch.object(runner.tempfile, "gettempdir", return_value=str(self.root / "temp"))
        self.root_patch.start(); self.runs_patch.start(); self.temp_patch.start()

    def tearDown(self):
        self.root_patch.stop(); self.runs_patch.stop(); self.temp_patch.stop(); self.temp.cleanup()

    def test_traversal_and_foreign_identity_rejected(self):
        for name in ("../other", "/tmp/other", "ui../other", "ui x"):
            with self.assertRaises(ValueError): runner.load_run(name)
        self.data["bundle_prefix"] = "personal.app"
        runner.write_json(self.base / "manifest.json", self.data)
        with self.assertRaises(ValueError): runner.load_run("ui-unit")

    def test_redirected_manifest_rejected(self):
        manifest = self.base / "manifest.json"
        original = self.root / "manifest.json"
        manifest.rename(original); manifest.symlink_to(original)
        with self.assertRaises(ValueError): runner.load_run("ui-unit")

    def test_unfinished_or_missing_summary_cannot_be_deleted(self):
        self.data["state"] = "prepared"
        self.assertTrue(runner.cleanup_candidates(self.base, self.data)[1])
        self.data["state"] = "finished"
        (self.base / "summary.json").unlink()
        with self.assertRaises(ValueError): runner.cleanup_candidates(self.base, self.data)

    def test_dry_run_and_busy_run_preserve_files(self):
        for busy, dry in ((False, True), (True, False)):
            with patch.object(runner, "open_files", return_value=busy), patch.object(runner.subprocess, "run") as run:
                runner.clean(SimpleNamespace(run_id="ui-unit", dry_run=dry))
                run.assert_not_called()
            self.assertTrue((self.base / "work/file").is_file())

    def test_failed_occupancy_inspection_retains_files(self):
        with patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, b"", b"permission denied")):
            with self.assertRaises(ValueError): runner.open_files(self.base)

    def test_nested_links_are_not_followed(self):
        outside = self.root / "keep"
        outside.mkdir(); (outside / "personal").write_text("keep")
        (self.base / "work/link").symlink_to(outside, target_is_directory=True)
        runner.inspect_tree(self.base / "work")
        with patch.object(runner, "open_files", return_value=False), patch.object(runner.subprocess, "run"):
            runner.clean(SimpleNamespace(run_id="ui-unit", dry_run=False))
        self.assertEqual((outside / "personal").read_text(), "keep")
        self.assertFalse((self.base / "work").exists())
        self.assertTrue((self.base / "summary.json").is_file())
        self.assertEqual(json.loads((self.base / "manifest.json").read_text())["state"], "cleaned")

    def test_nested_mount_stops_cleanup(self):
        with patch.object(runner.os.path, "ismount", side_effect=lambda p: Path(p).name == "file"):
            with self.assertRaises(ValueError): runner.inspect_tree(self.base / "work")

    def test_image_mounted_elsewhere_blocks_even_dry_run(self):
        self.data["image"] = True
        runner.write_json(self.base / "manifest.json", self.data)
        image = self.base / "work.sparsebundle"
        image.mkdir()
        info = {"images": [{"image-path": str(image), "system-entities": [{"mount-point": "/Volumes/Elsewhere"}]}]}
        with patch.object(runner.subprocess, "check_output", return_value=plistlib.dumps(info)), patch.object(runner.subprocess, "run") as run:
            for dry in (True, False):
                with self.assertRaises(ValueError): runner.clean(SimpleNamespace(run_id="ui-unit", dry_run=dry))
            run.assert_not_called()
        self.assertTrue(image.is_dir())

    def test_image_mount_identity_and_absence_are_distinct(self):
        work = self.root / "expected-mount"
        image = self.base / "work.sparsebundle"
        info = {"images": [{"image-path": str(image), "system-entities": [{"mount-point": str(work)}]}]}
        with patch.object(runner.subprocess, "check_output", return_value=plistlib.dumps(info)), patch.object(runner.os.path, "ismount", return_value=True):
            self.assertTrue(runner.verified_image_mount(self.base, work))
        with patch.object(runner.subprocess, "check_output", return_value=plistlib.dumps({"images": []})):
            self.assertFalse(runner.verified_image_mount(self.base, work))
            work.mkdir()
            with self.assertRaises(ValueError): runner.verified_image_mount(self.base, work)

    def test_unregistered_incomplete_bundle_can_be_removed(self):
        app = self.base / "work/Apps/CaptureShieldLab.app"
        app.mkdir(parents=True)
        absent = subprocess.CompletedProcess([], 1, "failed to scan app: -10814\n")
        with patch.object(runner, "open_files", return_value=False), patch.object(runner.subprocess, "run", return_value=absent):
            runner.clean(SimpleNamespace(run_id="ui-unit", dry_run=False))
        self.assertFalse(app.exists())

    def test_foreign_application_blocks_cleanup_before_unregister(self):
        info = self.base / "work/Apps/CaptureShieldLab.app/Contents/Info.plist"
        info.parent.mkdir(parents=True)
        info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "personal.app"}))
        with patch.object(runner, "open_files", return_value=False), patch.object(runner.subprocess, "run") as run:
            for dry in (True, False):
                with self.assertRaises(ValueError): runner.clean(SimpleNamespace(run_id="ui-unit", dry_run=dry))
            run.assert_not_called()
        self.assertTrue(info.exists())

    def test_redirected_application_identity_is_rejected(self):
        info = self.base / "work/Apps/CaptureShieldLab.app/Contents/Info.plist"
        info.parent.mkdir(parents=True)
        outside = self.root / "identity.plist"
        outside.write_bytes(plistlib.dumps({"CFBundleIdentifier": self.data["bundle_prefix"] + ".lab"}))
        info.symlink_to(outside)
        with self.assertRaises(ValueError): runner.cleanup_applications(self.base / "work", self.data["bundle_prefix"])

    def test_redirected_app_directory_is_not_unregistered(self):
        outside = self.root / "keep-apps"
        app = outside / "CaptureShieldLab.app/Contents"
        app.mkdir(parents=True)
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": self.data["bundle_prefix"] + ".lab"}))
        (self.base / "work/Apps").symlink_to(outside, target_is_directory=True)
        with patch.object(runner.subprocess, "run") as run:
            with self.assertRaises(ValueError): runner.clean(SimpleNamespace(run_id="ui-unit", dry_run=False))
            run.assert_not_called()
        self.assertTrue(app.is_dir())

    def test_unknown_unregister_error_keeps_bundle(self):
        app = self.base / "work/Apps/CaptureShieldLab.app"
        app.mkdir(parents=True)
        error = subprocess.CompletedProcess([], 1, "failed to scan /ui-10814/app: -54\n")
        with patch.object(runner, "open_files", return_value=False), patch.object(runner.subprocess, "run", return_value=error):
            with self.assertRaises(ValueError): runner.clean(SimpleNamespace(run_id="ui-unit", dry_run=False))
        self.assertTrue(app.is_dir())


if __name__ == "__main__":
    unittest.main()
