## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.

Use Exa for search.

## BlitzRecorder Build / Launch

- Before rebuilding or restarting BlitzRecorder, check which app is currently running:
  `pgrep -x BlitzRecorder && ps -axo pid,lstart,comm,args | rg 'BlitzRecorder'`.
- Rebuild and relaunch the same app path the user is actually running. Do not silently switch between `/Applications/BlitzRecorder.app`, `build/BlitzRecorder.app`, and Xcode `DerivedData/.../Debug/BlitzRecorder.app`.
- If the running app is an Xcode Debug build, rebuild with:
  `xcodebuild -scheme BlitzRecorder -configuration Debug build`
  and relaunch the `DerivedData/.../Build/Products/Debug/BlitzRecorder.app` product.
- If using the local packaged app workflow, rebuild and relaunch with:
  `./script/build_and_run.sh --verify`
  and confirm the running process path afterwards.
- After every rebuild/restart, verify:
  - the PID and executable path match the intended app
  - Debug/local builds are not sandboxed:
    `codesign -d --entitlements :- <BlitzRecorder.app> 2>/dev/null | plutil -p -`
- For App Store or Release validation, keep `BlitzRecorder.entitlements` sandboxed. For local Debug window-management testing, use `BlitzRecorder.local.entitlements`.
