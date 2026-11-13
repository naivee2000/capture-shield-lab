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
              "source_commit": output(["git", "rev-parse", "HEAD"], cwd=ROOT)}
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
    RUNS.mkdir(parents=True, exist_ok=True)
    if (ROOT / "artifacts").is_symlink() or RUNS.is_symlink():
        raise ValueError("Refusing redirected run registry.")
    base = RUNS / run_id
    base.mkdir()
    image = fs.get("FilesystemType", "").lower() not in ("apfs", "hfs")
    data = {"schema": 1, "owner": OWNER, "run_id": run_id, "image": image,
            "bundle_prefix": "dev.naivee2000.captureshield.uitest." + run_id,
            "state": "prepared", "summary_saved": False}
    write_json(base / "manifest.json", data)
    work = work_path(base, data)
    if image:
        subprocess.run(["hdiutil", "create", "-size", "80g", "-type", "SPARSEBUNDLE",
                        "-fs", "APFS", "-volname", work.name, str(base / "work.sparsebundle")], check=True)
        subprocess.run(["hdiutil", "attach", "-nobrowse", "-owners", "on",
                        "-mountpoint", str(work), str(base / "work.sparsebundle")], check=True)
    else:
        work.mkdir()
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
    if not all(isinstance(v, int) and v >= 0 for v in (passed, failed, skipped)):
        raise ValueError("Unrecognized xcresult counts.")
    return {"passed": passed, "failed": failed, "skipped": skipped}

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
        binary = app / "Contents/MacOS/CaptureShieldLab"
        report["application_sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
        report["stage"] = "ui-build"
        project = ROOT / "UITests/CaptureShieldUITests.xcodeproj"
        common = ["xcodebuild", "-project", str(project), "-scheme", "CaptureShieldUITests",
                  "-destination", "platform=macOS", "-derivedDataPath", str(work / "DerivedData"),
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
                              "-destination", "platform=macOS", "-parallel-testing-enabled", "NO",
                              "-resultBundlePath", str(result)], log, env, timeout=480)
            try:
                raw = output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)])
                counts = result_counts(json.loads(raw))
            except (subprocess.CalledProcessError, ValueError):
                counts = {"passed": 0, "failed": 0, "skipped": 0}
            report["rounds"].append({"round": index, "exit_code": rc, **counts})
            if rc or not counts["passed"] or counts["failed"] or counts["skipped"]:
                text = log.read_text(errors="replace").lower()
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
    finally:
        write_json(base / "summary.json", report)
        manifest["state"] = "finished"
        manifest["summary_saved"] = True
        write_json(base / "manifest.json", manifest)
        print(json.dumps(report, indent=2), flush=True)
        print("Raw evidence retained until review. Cleanup run:", run_id, flush=True)

def clean(args):
    ids = [args.run_id] if args.run_id else sorted(p.name for p in RUNS.glob("ui*") if p.is_dir())
    for run_id in ids:
        base, data = load_run(run_id)
        work = work_path(base, data)
        if not data.get("summary_saved") or data.get("state") != "finished":
            print(run_id + ": retain (unfinished or summary missing)")
            continue
        # Never interrupt applications to permit deletion.
        paths = [base]
        if data["image"]: paths.append(work)
        busy = any(subprocess.run(["/usr/sbin/lsof", "-t", "+D", str(p)],
                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout for p in paths if p.exists())
        if busy:
            print(run_id + ": retain (open files/processes)")
            continue
        if args.dry_run:
            print(run_id + ": eligible; raw evidence/workspace will be removed; summary retained")
            continue
        if not args.run_id:
            raise ValueError("Execute cleanup with one explicit --run-id.")
        if data["image"] and work.exists():
            info = plistlib.loads(subprocess.check_output(["hdiutil", "info", "-plist"]))
            expected = str(base / "work.sparsebundle")
            matches = [i for i in info.get("images", []) if i.get("image-path") == expected]
            if len(matches) != 1 or not any(e.get("mount-point") == str(work) for e in matches[0].get("system-entities", [])):
                raise ValueError("Mounted image identity does not match this run.")
            subprocess.run(["hdiutil", "detach", str(work)], check=True)
        for child in base.iterdir():
            if child.name in ("manifest.json", "summary.json"): continue
            if child.is_symlink():
                raise ValueError("Refusing redirected generated artifact.")
            if child.is_dir(): shutil.rmtree(child)
            else: child.unlink()
        # Only the per-run preview defaults; never the real application domain.
        domain = data["bundle_prefix"] + ".lab.preview"
        subprocess.run(["defaults", "delete", domain], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        data["state"] = "cleaned"
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

