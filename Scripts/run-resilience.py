#!/usr/bin/env python3
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import statistics
import subprocess
import sys
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
FOCUSED_TESTS = (
    "RecordingResilienceTests|TakeRecordingRuntimeTests|AudioSampleFileWriterStartupTests|"
    "AudioClockNormalizerTests|RemoteCameraTransferManagerTests|SystemAudioRecorderStartupTests|"
    "RecordingLifecycleTests.testCaptureSourceRun"
)
WORKLOAD_TESTS = {
    "benchmark": "RecordingWorkloadTests/testBenchmarks",
    "soak": "RecordingWorkloadTests/testSustainedSyntheticRecording",
    "disk": "RecordingWorkloadTests/testFullDiskPreservesRecoveryFiles",
}


def output(command):
    return subprocess.check_output(command, text=True, cwd=ROOT, stderr=subprocess.STDOUT).strip()


def stop(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()


def run_tests(request):
    with request["log"].open("w") as log:
        process = subprocess.Popen(
            request["command"], cwd=ROOT, env=request["environment"],
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        try:
            return process.wait(timeout=request["timeout"])
        finally:
            stop(process)


def compare(request):
    current, baseline = request["current"], request["baseline"]
    if baseline.get("status") != "passed" or baseline.get("mode") != "benchmark":
        raise ValueError("Baseline must be a successful benchmark report")
    if current["machine"] != baseline["machine"]:
        raise ValueError("Baseline hardware, OS, or Swift version differs")
    if current["metrics"]["fixture_version"] != baseline["metrics"]["fixture_version"]:
        raise ValueError("Baseline fixture version differs")
    groups = []
    for report in [current, baseline]:
        grouped = {}
        for sample in report["metrics"]["samples"]:
            grouped.setdefault(sample["fixture"], []).append(sample)
        groups.append(grouped)
    if groups[0].keys() != groups[1].keys():
        raise ValueError("Baseline fixtures differ")
    failures = []
    for fixture, samples in groups[0].items():
        if len(samples) < 3 or len(groups[1][fixture]) < 3:
            raise ValueError("At least three measured iterations per fixture are required")
        for metric in ["editor_load_ms", "unchanged_layout_us", "export_seconds"]:
            actual = statistics.median(sample[metric] for sample in samples)
            previous = statistics.median(sample[metric] for sample in groups[1][fixture])
            if actual > previous * (1 + request["regression_percent"] / 100):
                failures.append(f"{fixture}: {metric} {actual:.3f} exceeds baseline {previous:.3f}")
    return failures


def main():
    parser = argparse.ArgumentParser(
        description="Run isolated macOS resilience checks. Outputs logs, JUnit XML, metrics, and a JSON report."
    )
    parser.add_argument("mode", choices=["quick", "thread", "address", "benchmark", "soak", "disk"])
    parser.add_argument("--seconds", type=int, default=60, help="Synthetic real-time soak duration, 10–10800 seconds")
    parser.add_argument("--jobs", type=int, default=4, help="Swift compiler jobs")
    parser.add_argument("--baseline", type=Path, help="Successful report.json from the same benchmark machine")
    parser.add_argument("--max-regression-percent", type=float, default=20)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("macOS is required")
    if not 10 <= args.seconds <= 10_800 or not 1 <= args.jobs <= 16:
        parser.error("Seconds must be 10–10800 and jobs must be 1–16")
    if not 0 <= args.max_regression_percent <= 100:
        parser.error("Regression percent must be 0–100")
    if args.baseline and args.mode != "benchmark":
        parser.error("--baseline requires benchmark mode")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    directory = ROOT / "build" / "resilience" / f"{stamp}-{args.mode}-{uuid.uuid4().hex[:6]}"
    directory.mkdir(parents=True)
    print(f"Results: {directory}", flush=True)
    environment = os.environ.copy()
    for key in list(environment):
        if key.startswith("BLITZRECORDER_WORKLOAD") or key in [
            "BLITZRECORDER_SOAK_SECONDS", "BLITZRECORDER_TEST_VOLUME", "BLITZRECORDER_RESULT_DIRECTORY"
        ]:
            environment.pop(key)
    environment["BLITZRECORDER_RESULT_DIRECTORY"] = str(directory)
    environment["BLITZRECORDER_DISABLE_IDLE_CAPTURE"] = "1"
    environment["DIRECT_DISTRIBUTION"] = "0"
    command = [
        "swift", "test", "-j", str(args.jobs), "--parallel", "--num-workers", "1",
        "--xunit-output", str(directory / "tests.xml"),
    ]
    if args.mode in ["thread", "address"]:
        command += ["--sanitize", args.mode]
        environment["TSAN_OPTIONS"] = "halt_on_error=1"
        environment["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
    command += ["--filter", WORKLOAD_TESTS.get(args.mode, FOCUSED_TESTS)]
    if args.mode in WORKLOAD_TESTS:
        environment["BLITZRECORDER_WORKLOAD"] = args.mode
    environment["BLITZRECORDER_SOAK_SECONDS"] = str(args.seconds)
    report = {
        "mode": args.mode, "status": "failed", "command": command,
        "revision": output(["git", "rev-parse", "HEAD"]),
        "dirty": bool(output(["git", "status", "--porcelain"])),
        "source_digest": hashlib.sha256(b"".join(
            path.relative_to(ROOT).as_posix().encode() + b"\0" + path.read_bytes()
            for path in sorted((ROOT / "Sources").rglob("*.swift"))
        )).hexdigest(),
        "machine": {
            "architecture": platform.machine(), "cpu": output(["sysctl", "-n", "machdep.cpu.brand_string"]),
            "memory_bytes": output(["sysctl", "-n", "hw.memsize"]),
            "os_build": output(["sw_vers", "-buildVersion"]),
            "swift": output(["swift", "--version"]),
            "configuration": "debug",
        },
    }
    started = time.monotonic()
    failures = []
    try:
        with tempfile.TemporaryDirectory(prefix="blitzrecorder-resilience-") as temporary:
            mount = Path(temporary) / "volume"
            attached = False
            try:
                if args.mode == "disk":
                    disk = Path(temporary) / "test.dmg"
                    subprocess.run(
                        ["hdiutil", "create", "-size", "64m", "-fs", "HFS+", "-type", "UDIF",
                         "-volname", "BlitzRecorderResilience", str(disk)],
                        check=True, capture_output=True, timeout=60,
                    )
                    mount.mkdir()
                    subprocess.run(
                        ["hdiutil", "attach", str(disk), "-nobrowse", "-mountpoint", str(mount)],
                        check=True, capture_output=True, timeout=60,
                    )
                    attached = True
                    (mount / ".resilience-volume").write_text("isolated-test-volume")
                    environment["BLITZRECORDER_TEST_VOLUME"] = str(mount)
                code = run_tests({
                    "command": command, "environment": environment, "log": directory / "tests.log",
                    "timeout": 2_400 + (args.seconds if args.mode == "soak" else 0),
                })
                report["exit_code"] = code
                if code:
                    failures.append(f"Swift tests exited with {code}; see tests.log")
                xml = ET.parse(directory / "tests.xml")
                cases = list(xml.iter("testcase"))
                if not cases or any(case.find("skipped") is not None for case in cases):
                    failures.append("Selected checks must execute without skips")
                if any(case.find("failure") is not None or case.find("error") is not None for case in cases):
                    failures.append("JUnit contains failing tests")
                report["test_count"] = len(cases)
                if args.mode in WORKLOAD_TESTS:
                    report["metrics"] = json.loads((directory / "metrics.json").read_text())
                if not failures and args.baseline:
                    failures += compare({
                        "current": report, "baseline": json.loads(args.baseline.read_text()),
                        "regression_percent": args.max_regression_percent,
                    })
            finally:
                if attached:
                    subprocess.run(["hdiutil", "detach", str(mount)], check=True, capture_output=True, timeout=30)
    except (Exception, KeyboardInterrupt) as error:
        detail = error.stderr.decode(errors="replace") if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        failures.append(f"{type(error).__name__}: {detail}")
    report["elapsed_seconds"] = time.monotonic() - started
    report["failures"] = failures
    report["status"] = "failed" if failures else "passed"
    (directory / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{report['status']}: {directory / 'report.json'}", flush=True)
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


def interrupted(*_):
    raise KeyboardInterrupt


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, interrupted)
    raise SystemExit(main())
