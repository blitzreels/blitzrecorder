#!/usr/bin/env bash
# End-to-end check of the iPhone camera against the running BlitzRecorder Dev app, on a real iPhone:
# relaunch the phone app, wait for the Mac to see it, check the live view, record a take, verify the clip.
#
#   Scripts/iphone-e2e.sh            10-second take
#   Scripts/iphone-e2e.sh 30         30-second take
#   IPHONE_E2E_RELAUNCH=0 ...        keep the phone app as is (e.g. launched from Xcode for its console)
#   IPHONE_E2E_DROP=10,25 ...        drop the connection 10 s into the take for 25 s, like a Wi-Fi loss
#
# Needs: BlitzRecorder Dev running (./script/build_and_run.sh), BlitzRecorder Camera installed on a USB/Wi-Fi
# paired iPhone that already trusts this Mac. Reports land in build/iphone-e2e/.
set -euo pipefail
cd "$(dirname "$0")/.."

seconds="${1:-10}"
bundle="dev.blitzreels.blitzrecorder.camera"
device="$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone/ && /connected/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i}' | head -1)"
[[ -n "$device" ]] || { echo "No connected physical iPhone." >&2; exit 2; }

if [[ "${IPHONE_E2E_RELAUNCH:-1}" == 1 ]]; then
  echo "Relaunching BlitzRecorder Camera on $device"
  xcrun devicectl device process launch --device "$device" --terminate-existing "$bundle" >/dev/null
fi

mkdir -p build/iphone-e2e
report="build/iphone-e2e/$(date +%Y%m%d-%H%M%S).json"

python3 - "$seconds" "$report" "${IPHONE_E2E_DROP:-}" <<'PY'
import json, sys, time, urllib.request

seconds, report_path = float(sys.argv[1]), sys.argv[2]
drop = [float(x) for x in sys.argv[3].split(",")] if len(sys.argv) > 3 and sys.argv[3] else None
url = "http://127.0.0.1:18473/mcp"
session = None
request_id = 0

def rpc(method, params=None, notify=False):
    global session, request_id
    body = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        body["params"] = params
    if not notify:
        request_id += 1
        body["id"] = request_id
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={
        "Content-Type": "application/json", "Accept": "application/json, text/event-stream",
        **({"Mcp-Session-Id": session} if session else {}),
    })
    with urllib.request.urlopen(req, timeout=1000) as response:
        session = response.headers.get("Mcp-Session-Id") or session
        raw = response.read().decode()
    if notify or not raw.strip():
        return None
    if raw.lstrip().startswith("event:") or raw.lstrip().startswith("data:"):
        raw = next(line[5:] for line in raw.splitlines() if line.startswith("data:"))
    message = json.loads(raw)
    if "error" in message:
        raise RuntimeError(message["error"])
    return message["result"]

def tool(name, arguments=None):
    result = rpc("tools/call", {"name": name, "arguments": arguments or {}})
    text = result["content"][0]["text"]
    if result.get("isError"):
        raise RuntimeError(f"{name}: {text}")
    return json.loads(text)

def wait(step, timeout, condition):
    deadline = time.monotonic() + timeout
    while True:
        status = tool("debug_iphone_status")
        if condition(status):
            return status
        if time.monotonic() > deadline:
            raise RuntimeError(f"Timed out {step}. Last status: {json.dumps(status)}")
        time.sleep(0.5)

checks, report = [], {"seconds": seconds}
def check(name, ok, detail):
    checks.append({"name": name, "ok": bool(ok), "detail": detail})
    print(("PASS " if ok else "FAIL ") + name + " · " + detail)

try:
    rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                       "clientInfo": {"name": "iphone-e2e", "version": "1"}})
    rpc("notifications/initialized", notify=True)

    t0 = time.monotonic()
    visible = wait("waiting for the Mac to see the iPhone", 45, lambda s: s["devices"])
    check("iPhone visible", True, f"{time.monotonic() - t0:.1f}s after launch")

    if not visible["isRemoteCameraSelected"]:
        tool("debug_iphone_select")
    connected = wait("waiting for the iPhone to connect", 45, lambda s: s["connectionState"] == "connected")
    check("Connected", True, f"{time.monotonic() - t0:.1f}s after launch")

    start = tool("debug_iphone_status")["previewFramesReceived"]
    live = wait("waiting for live view", 30, lambda s: s["previewFramesReceived"] > start)
    first_frame = time.monotonic() - t0
    time.sleep(5)
    sample = tool("debug_iphone_status")
    fps = (sample["previewFramesReceived"] - live["previewFramesReceived"]) / 5
    report["preview"] = sample
    check("Live view", fps >= 15, f"first frame {first_frame:.1f}s after launch, {fps:.1f} fps received on the Mac")
    if sample.get("captureWarning"):
        print("NOTE iPhone warning · " + sample["captureWarning"])

    take_args = {"seconds": seconds}
    if drop:
        take_args.update(dropAfterSeconds=drop[0], offlineSeconds=drop[1])
        print(f"NOTE dropping the connection {drop[0]:.0f}s into the take for {drop[1]:.0f}s")
    take = tool("debug_record_take", take_args)
    report["take"] = take
    camera = next((s for s in take["sources"] if s["role"] == "camera"), None)
    if drop and camera and not camera["exists"]:
        import os
        deadline = time.monotonic() + 120
        while not os.path.exists(camera["path"]) and time.monotonic() < deadline:
            time.sleep(1)
        print(f"NOTE clip recovered after reconnect: {os.path.exists(camera['path'])}")
        camera = dict(camera, exists=os.path.exists(camera["path"]),
                      bytes=os.path.getsize(camera["path"]) if os.path.exists(camera["path"]) else 0)
    check("Take saved", camera is not None and camera["exists"], take["projectPath"])
    if camera:
        duration = camera.get("durationSeconds") or 0
        check("iPhone clip length", abs(duration - take["recordedSeconds"]) <= 1.5,
              f"{duration:.2f}s clip for {take['recordedSeconds']:.2f}s take")
        size_mb = (camera.get("bytes") or 0) / 1_000_000
        check("iPhone clip imported", size_mb > 0,
              f"{size_mb:.1f} MB, {camera.get('videoCodec')} {camera.get('width')}x{camera.get('height')}, "
              f"stop to done {take['stopToIdleSeconds']:.1f}s ({take.get('importMegabytesPerSecond') or 0:.1f} MB/s)")
    before = tool("debug_iphone_status")["previewFramesReceived"]
    wait("waiting for live view after the take", 20, lambda s: s["previewFramesReceived"] > before + 10)
    check("Live view after take", True, "frames arriving again")
except Exception as error:
    check("Run", False, str(error))

report["checks"] = checks
open(report_path, "w").write(json.dumps(report, indent=2))
failed = [c for c in checks if not c["ok"]]
print(f"\n{len(checks) - len(failed)}/{len(checks)} checks passed · {report_path}")
sys.exit(1 if failed else 0)
PY
