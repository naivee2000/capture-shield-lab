#!/usr/bin/env python3
"""Build/test the real application. No permission changes, account data or retries."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "artifacts" / "ui-runs"
OWNER = "CaptureShield UI tests"

def output(command, **kwargs):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT, **kwargs).strip()

def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")

def environment():
    result = {"architecture": platform.machine(), "system": platform.mac_ver()[0],
              "source_commit": output(["git", "rev-parse", "HEAD"], cwd=ROOT),
              "source_dirty": bool(output(["git", "status", "--porcelain"], cwd=ROOT))}
    for key, command in [
        ("system_build", ["sw_vers", "-buildVersion"]),
        ("swift", ["xcrun", "swift", "--version"]),
        ("sdk", ["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
        ("xcode", ["xcodebuild", "-version"])]:
        try: result[key] = output(command).splitlines()[0]
        except subprocess.CalledProcessError: result[key] = "unavailable"
    return result

def preflight():
    env = environment()
    problems = []
    version = tuple(int(n) for n in (env["system"].split(".") + ["0"] * 3)[:3]) if env["system"] else (0,)
    if env["architecture"] != "arm64" or not (version >= (15, 8, 2) and version[0] <= 27):
        problems.append("UI validation targets Apple Silicon macOS 15.8.2 through 27.x.")
    if env["xcode"] == "unavailable":
        problems.append("Full Xcode is required for XCTest UI tests. Set DEVELOPER_DIR to its Contents/Developer; CLT alone can still build the app.")
    if not Path("/dev/console").exists() or Path("/dev/console").stat().st_uid == 0:
        problems.append("An unlocked graphical login session is required.")
    processes = output(["ps", "-axo", "comm="])
    if any(line.rstrip().endswith("/CaptureShieldLab.app/Contents/MacOS/CaptureShieldLab") for line in processes.splitlines()):
        problems.append("Another CaptureShield instance is running. Use a clean test session for global shortcuts; this script will not close it.")
    if env["system"] and env["architecture"] == "arm64":
        display = subprocess.run(["xcrun", "swift", str(ROOT / "scripts/ui-display.swift"), "--check"],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try: env["display"] = json.loads(display.stdout)
        except ValueError: env["display"] = {"ready": False}
        if display.returncode or not env["display"].get("ready"):
            problems.append("UI tests need a primary visible display area of at least 1200x850 logical points. This preflight will not change display settings.")
    return {"status": "not-tested" if problems else "ready", "environment": env,
            "reasons": problems, "ui_authorization": "not attested until XCTest launches; never modified by this script"}

def run_command(command, log, env=None, timeout=600):
    with log.open("w") as stream:
        try:
            return subprocess.run(command, cwd=ROOT, env=env, stdout=stream,
                                  stderr=subprocess.STDOUT, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            stream.write("\nCaptureShield command deadline exceeded; no retry.\n")
            return 124

def validate_id(value):
    if not re.fullmatch(r"ui[a-zA-Z0-9-]{1,64}", value):
        raise ValueError("Invalid run ID; use an ID printed by test-ui.sh.")
    return value

def load_run(run_id):
    base = RUNS / validate_id(run_id)
    if (ROOT / "artifacts").is_symlink() or RUNS.is_symlink() or base.is_symlink() or base.resolve().parent != RUNS.resolve():
        raise ValueError("Refusing redirected run directory.")
    manifest = base / "manifest.json"
    if manifest.is_symlink():
        raise ValueError("Refusing redirected manifest.")
    data = json.loads(manifest.read_text())
    if data.get("owner") != OWNER or data.get("run_id") != run_id or data.get("schema") != 1:
        raise ValueError("Run ownership does not match.")
    if type(data.get("image")) is not bool or data.get("bundle_prefix") != "dev.naivee2000.captureshield.uitest." + run_id:
        raise ValueError("Run identity does not match its isolated application.")
    return base, data

def work_path(base, data):
    if data["image"]:
        return Path("/Volumes") / ("CaptureShieldUI-" + data["run_id"])
    return base / "work"

def prepare(run_id):
    validate_id(run_id)
    mount = ROOT
    while not os.path.ismount(mount):
        mount = mount.parent
    fs = plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", str(mount)]))
    if (ROOT / "artifacts").is_symlink() or RUNS.is_symlink():
        raise ValueError("Refusing redirected run registry.")
    RUNS.mkdir(parents=True, exist_ok=True)
    base = RUNS / run_id
    base.mkdir()
    image = fs.get("FilesystemType", "").lower() not in ("apfs", "hfs")
    data = {"schema": 1, "owner": OWNER, "run_id": run_id, "image": image,
            "bundle_prefix": "dev.naivee2000.captureshield.uitest." + run_id,
            "state": "prepared", "summary_saved": False}
    write_json(base / "manifest.json", data)
    work = work_path(base, data)
    try:
        if image:
            subprocess.run(["hdiutil", "create", "-size", "80g", "-type", "SPARSEBUNDLE",
                            "-fs", "APFS", "-volname", work.name, str(base / "work.sparsebundle")], check=True)
            subprocess.run(["hdiutil", "attach", "-nobrowse", "-owners", "on",
                            "-mountpoint", str(work), str(base / "work.sparsebundle")], check=True)
        else:
            work.mkdir()
    except (OSError, subprocess.SubprocessError) as error:
        write_json(base / "summary.json", {"schema": 1, "run_id": run_id, "status": "fail",
                   "stage": "prepare-storage", "error_type": type(error).__name__})
        data.update(state="finished", summary_saved=True)
        write_json(base / "manifest.json", data)
        raise
    return base, data, work

def targets(document):
    # Xcode 26/27 xctestrun format 2; legacy single-target format is also accepted.
    if "TestConfigurations" in document:
        for config in document["TestConfigurations"]:
            yield from config.get("TestTargets", [])
    else:
        for key, value in document.items():
            if key != "__xctestrun_metadata__" and isinstance(value, dict):
                yield value

def result_counts(result):
    passed = result.get("passedTests", 0)
    failed = result.get("failedTests", 0)
    skipped = result.get("skippedTests", 0)
    if not all(type(v) is int and v >= 0 for v in (passed, failed, skipped)):
        raise ValueError("Unrecognized xcresult counts.")
    return {"passed": passed, "failed": failed, "skipped": skipped}

def result_passed(code, counts, expected=7):
    return code == 0 and counts == {"passed": expected, "failed": 0, "skipped": 0}

def validate_application(app, prefix):
    if app.is_symlink() or not app.is_dir():
        raise ValueError("Packaged application is missing or redirected.")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != prefix + ".lab":
        raise ValueError("Unexpected application identity; personal applications are not test targets.")
    if not (app / "Contents/MacOS/CaptureShieldLab").is_file():
        raise ValueError("Packaged application executable is missing.")
    return {"version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
            "build_commit": info.get("CaptureShieldBuildCommit", "unknown"),
            "minimum_system": info["LSMinimumSystemVersion"]}

def execute(args):
    check = preflight()
    if args.preflight:
        print(json.dumps(check, indent=2))
        return 2 if check["reasons"] else 0
    if check["reasons"]:
        print(json.dumps(check, indent=2))
        return 2
    run_id = args.run_id or ("ui" + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:6])
    base, manifest, work = prepare(run_id)
    report = {"schema": 1, "run_id": run_id, "environment": check["environment"],
              "status": "fail", "stage": "build", "rounds": [],
              "real_capture": "not-tested", "real_speech": "not-tested",
              "real_chatgpt": "not-tested", "receiver": "not-tested"}
    print("UI run:", run_id, flush=True)
    env = os.environ.copy()
    env.update(CAPTURESHIELD_APP_ROOT=str(work / "Apps"),
               CAPTURESHIELD_BUNDLE_PREFIX=manifest["bundle_prefix"])
    try:
        rc = run_command(["bash", "scripts/build.sh", "--scratch-path", str(work / "swift-build")], base / "build.log", env)
        if rc: return 1
        app = work / "Apps" / "CaptureShieldLab.app"
        report["stage"] = "package-identity"
        report["application"] = validate_application(app, manifest["bundle_prefix"])
        binary = app / "Contents/MacOS/CaptureShieldLab"
        report["application_sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
        report["stage"] = "ui-build"
        project = ROOT / "UITests/CaptureShieldUITests.xcodeproj"
        common = ["xcodebuild", "-project", str(project), "-scheme", "CaptureShieldUITests",
                  "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", str(work / "DerivedData"),
                  "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES",
                  "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES", "DEVELOPMENT_TEAM="]
        rc = run_command(common + ["build-for-testing"], base / "ui-build.log", env)
        if rc: return 1
        specs = list((work / "DerivedData/Build/Products").glob("*.xctestrun"))
        if len(specs) != 1:
            raise ValueError("Expected one xctestrun specification.")
        spec = plistlib.loads(specs[0].read_bytes())
        suites = list(targets(spec))
        if not suites: raise ValueError("No UI targets in xctestrun.")
        for item in suites:
            item.setdefault("EnvironmentVariables", {}).update(
                CAPTURESHIELD_UI_APP=str(app), CAPTURESHIELD_UI_RUN=str(work),
                CAPTURESHIELD_UI_NEGATIVE="1" if args.negative else "0")
        specs[0].write_bytes(plistlib.dumps(spec))
        report["stage"] = "ui-execution"
        for index in range(1, args.repeat + 1):
            result = work / ("round-" + str(index) + ".xcresult")
            log = base / ("round-" + str(index) + ".log")
            rc = run_command(["xcodebuild", "test-without-building", "-xctestrun", str(specs[0]),
                              "-destination", "platform=macOS,arch=arm64", "-parallel-testing-enabled", "NO",
                              "-resultBundlePath", str(result)] +
                             (["-only-testing:CaptureShieldUITests/AppUITests/testLaunchTypeAndRestart"] if args.negative else []),
                             log, env, timeout=480)
            try:
                raw = output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)])
                counts = result_counts(json.loads(raw))
            except (subprocess.CalledProcessError, ValueError):
                counts = {"passed": 0, "failed": 0, "skipped": 0}
            log_text = log.read_text(errors="replace")
            failures = re.findall(r"AppUITests\.swift:\d+: error: [^\n]+", log_text)
            report["rounds"].append({"round": index, "exit_code": rc, **counts, "failures": failures[:20]})
            if not result_passed(rc, counts):
                text = log.read_text(errors="replace").lower()
                report["negative_control_expected_failure"] = bool(args.negative and counts["failed"] == 1
                    and counts["passed"] == 0 and "negative control must fail" in text)
                if any(s in text for s in ("does not have permission to use accessibility",
                                          "not authorized for ui testing",
                                          "failed to get authorization")):
                    report["status"] = "not-tested"
                    report["stage"] = "ui-authorization"
                    return 2
                return 1
        if args.negative:
            report["stage"] = "negative-control-unexpected-pass"
            return 1
        report["status"] = "pass"
        report["stage"] = "complete"
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report["error_type"] = type(error).__name__
        # Exception text can contain machine-specific paths. Raw local logs remain local.
        return 1
    finally:
        write_json(base / "summary.json", report)
        manifest["state"] = "finished"
        manifest["summary_saved"] = True
        write_json(base / "manifest.json", manifest)
        print(json.dumps(report, indent=2), flush=True)
        print("Raw evidence retained until review. Cleanup run:", run_id, flush=True)

def inspect_tree(path):
    """Do not traverse links or nested mounts during accounting/deletion."""
    if path.is_symlink():
        raise ValueError("Refusing redirected generated artifact.")
    if not path.exists(): return 0
    total = 0
    for root, dirs, files in os.walk(path, followlinks=False):
        for name in dirs + files:
            child = Path(root) / name
            if child.is_symlink():
                # SwiftPM/Xcode generate links inside build products. Account for
                # the link itself; os.walk/rmtree never follow it into its target.
                total += child.lstat().st_blocks * 512
                continue
            if os.path.ismount(child):
                raise ValueError("Refusing nested mount; retain for inspection.")
            if child.is_file(): total += child.stat().st_blocks * 512
    return total

def open_files(path):
    result = subprocess.run(["/usr/sbin/lsof", "-t"] + (["+D", str(path)] if path.is_dir() else [str(path)]),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.stderr or result.returncode not in (0, 1):
        raise ValueError("Cannot reliably inspect resource use; retain files.")
    return bool(result.stdout)

def cleanup_candidates(base, data):
    if not data.get("summary_saved") or data.get("state") != "finished":
        return [], "unfinished or summary missing"
    summary = base / "summary.json"
    if summary.is_symlink() or not summary.is_file():
        raise ValueError("A retained technical summary is required before cleanup.")
    report = json.loads(summary.read_text())
    if report.get("run_id") != data["run_id"] or report.get("status") not in ("pass", "fail", "not-tested"):
        raise ValueError("Summary identity or verdict is invalid.")
    return [p for p in base.iterdir() if p.name not in ("manifest.json", "summary.json")], ""

def verified_image_mount(base, work):
    # Inspect the image even when the expected mountpoint is absent: the same
    # sparsebundle may still be mounted elsewhere and must not be deleted.
    info = plistlib.loads(subprocess.check_output(["hdiutil", "info", "-plist"]))
    expected = str(base / "work.sparsebundle")
    matches = [i for i in info.get("images", []) if i.get("image-path") == expected]
    if not matches:
        if work.exists(): raise ValueError("Unexpected workspace at the image mountpoint; retain it.")
        return False
    mounts = [e["mount-point"] for i in matches for e in i.get("system-entities", []) if "mount-point" in e]
    if len(matches) != 1 or mounts != [str(work)] or not os.path.ismount(work):
        raise ValueError("Mounted image identity or location does not match this run; retain it.")
    return True

def cleanup_applications(work, prefix):
    apps = [(work / "Apps/CaptureShieldLab.app", prefix + ".lab"),
            (work / "Apps/CaptureProbe.app", prefix + ".probe"),
            (work / "DerivedData/Build/Products/Debug/CaptureShieldUITests-Runner.app",
             "dev.naivee2000.captureshield.uitest.runner.xctrunner")]
    for app, identifier in apps:
        if not app.exists(): continue
        info = app / "Contents/Info.plist"
        parents = list(app.parents)[:list(app.parents).index(work)]
        if any(p.is_symlink() for p in [app, *parents, app / "Contents", info]):
            raise ValueError("Refusing redirected test application identity.")
        # An interrupted build may have no plist and was never registered.
        # If one exists, require the actual identity before any mutation.
        if info.exists() and plistlib.loads(info.read_bytes()).get("CFBundleIdentifier") != identifier:
            raise ValueError("Test application identity changed; retain workspace for inspection.")
    return [app for app, _ in apps if app.exists()]

def clean(args):
    ids = [args.run_id] if args.run_id else sorted(p.name for p in RUNS.glob("ui*") if p.is_dir())
    for run_id in ids:
        base, data = load_run(run_id)
        work = work_path(base, data)
        candidates, reason = cleanup_candidates(base, data)
        if reason:
            print(run_id + ": retain (" + reason + ")")
            continue
        # Never interrupt applications to permit deletion.
        paths = [p for p in candidates if p.name != "work.sparsebundle"]
        if data["image"]: paths.append(work)
        attachment = Path(tempfile.gettempdir()) / "CaptureShieldAttachments" / (data["bundle_prefix"] + ".lab")
        if attachment.parent.is_symlink(): raise ValueError("Refusing redirected attachment root.")
        paths.append(attachment)
        # Inspect complete trees before any mutation, including all siblings.
        if any(p.is_symlink() or os.path.ismount(p) for p in candidates):
            raise ValueError("Refusing redirected run artifact or nested mount.")
        mounted = verified_image_mount(base, work) if data["image"] else False
        if mounted: inspect_tree(work)
        test_apps = cleanup_applications(work, data["bundle_prefix"])
        estimated = sum(inspect_tree(p) if p.is_dir() else p.lstat().st_blocks * 512 for p in candidates)
        inspect_tree(attachment)
        busy = any(open_files(p) for p in paths if p.exists())
        if busy:
            print(run_id + ": retain (open files/processes)")
            continue
        if args.dry_run:
            print(run_id + ": eligible; allocated bytes=" + str(estimated) + "; summary retained")
            continue
        if not args.run_id:
            raise ValueError("Execute cleanup with one explicit --run-id.")
        # Unregister only these now-unused test bundles after verifying ownership.
        register = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        for app in test_apps:
            result = subprocess.run([register, "-u", str(app)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            # An incomplete test runner was never registered when compilation
            # failed. LaunchServices explicitly reports ApplicationNotFound.
            if result.returncode and not re.search(r": -10814(?:\r?\n|$)", result.stdout):
                raise ValueError("Test application unregister failed; retain workspace for inspection.")
        if mounted:
            subprocess.run(["hdiutil", "detach", str(work)], check=True)
        for child in candidates:
            # exFAT may remove an AppleDouble companion automatically when its
            # original is deleted. Accept only that already-absent pair.
            if child.name.startswith("._") and not child.exists() and not child.with_name(child.name[2:]).exists():
                continue
            if child.is_dir(): shutil.rmtree(child)
            else: child.unlink()
        if attachment.exists(): shutil.rmtree(attachment)
        # Only per-run domains, including AppKit's own toolbar/frame preferences.
        for suffix in (".lab.preview", ".lab", ".probe"):
            subprocess.run(["defaults", "delete", data["bundle_prefix"] + suffix],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        data["state"] = "cleaned"
        data["reclaimed_allocated_bytes"] = estimated
        write_json(base / "manifest.json", data)
        print(run_id + ": cleaned (technical summary and ownership manifest retained)")
    return 0

def main():
    if sys.argv[1:2] == ["cleanup"]:
        parser = argparse.ArgumentParser()
        parser.add_argument("--dry-run", action="store_true")
        parser.add_argument("--run-id")
        args = parser.parse_args(sys.argv[2:])
        if not args.dry_run and not args.run_id: parser.error("Use --dry-run or --run-id ID.")
        return clean(args)
    parser = argparse.ArgumentParser()
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--run-id")
    parser.add_argument("--repeat", type=int, choices=range(1, 4), default=3)
    parser.add_argument("--negative", action="store_true", help="Deliberately require an absent UI marker; must fail.")
    return execute(parser.parse_args())

if __name__ == "__main__":
    try: sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("UI validation stopped:", error, file=sys.stderr)
        sys.exit(1)
