const bridge = window.chrome?.webview;
const send = (message) => bridge?.postMessage(message);
const $ = (id) => document.getElementById(id);
let state = {
  targets: [],
  takes: [],
  recording: false,
  playing: false,
  paused: false,
};
let view = "record";

function setView(next) {
  view = next;
  $("record-workspace").classList.toggle("hidden", next !== "record");
  $("library-workspace").classList.toggle("hidden", next !== "library");
  send(`view|${next}`);
  if (next === "record") requestBounds();
}

function requestBounds() {
  if (view !== "record") return;
  const rect = $("preview-frame").getBoundingClientRect();
  const scale = window.devicePixelRatio || 1;
  send(
    `bounds|${Math.round(rect.left * scale)}|${Math.round(rect.top * scale)}|${Math.round(rect.width * scale)}|${Math.round(rect.height * scale)}`,
  );
}

function render() {
  const busy = state.recording || state.starting;
  $("status-text").textContent = state.status || "Ready to record";
  $("status-dot").classList.toggle("recording", state.recording);
  $("record-button").disabled = !!state.starting;
  $("record-button").classList.toggle("active", !!state.recording);
  $("record-label").textContent = state.recording
    ? "Stop recording"
    : state.starting
      ? "Starting…"
      : "Start recording";
  $("play-button").disabled = !state.playing;
  $("play-button").textContent = state.paused ? "Resume" : "Pause";
  $("export-button").disabled = busy || !state.lastTake;
  $("open-button").disabled = busy;
  for (const [key, element] of [
    ["microphone", "microphone-switch"],
    ["systemAudio", "system-switch"],
    ["camera", "camera-switch"],
  ]) {
    $(element).classList.toggle("on", !!state[key]);
  }
  const selectedTarget =
    state.targets[state.selected] || "Choose a screen or window";
  $("screen-detail").textContent = selectedTarget;
  $("target-note").textContent = selectedTarget;
  const select = $("target-select");
  const targetNames = state.targets.join("\u001f");
  if (select.dataset.names !== targetNames) {
    select.replaceChildren(
      ...state.targets.map((label, index) => new Option(label, String(index))),
    );
    select.dataset.names = targetNames;
  }
  select.value = String(state.selected);
  select.disabled = busy;
  $("last-take").textContent = state.lastTake
    ? state.lastTake.split(/[\\/]/).pop()
    : "Record a take to preview and export it here.";
  $("scene-title").textContent = state.camera
    ? "Camera overlay"
    : "Screen focus";
  $("scene-description").textContent = state.camera
    ? "Screen with camera picture in picture"
    : "Screen only";
  $("stage-title").textContent = state.recording
    ? "Recording in progress"
    : state.playing
      ? "Take preview"
      : "Your recording canvas";
  $("stage-subtitle").textContent = state.recording
    ? "Press Stop to finish the take."
    : state.playing
      ? "Playback is running in this canvas."
      : "Choose a screen or window, then start recording.";
  $("stage-callout-text").textContent = state.recording
    ? "Capturing the selected source and enabled audio."
    : state.playing
      ? "Review your take, then export it."
      : "Access is checked when recording starts.";
  $("stage-label-text").textContent = state.recording
    ? "RECORDING"
    : state.playing
      ? "TAKE PREVIEW"
      : "LIVE CANVAS";
  const list = $("take-list");
  if (state.takes.length) {
    list.replaceChildren(
      ...state.takes.map((name, index) => {
        const card = document.createElement("button");
        card.className = "take-card";
        const title = document.createElement("strong");
        title.textContent = name;
        const detail = document.createElement("small");
        detail.textContent = "Open take for playback";
        card.append(title, detail);
        card.addEventListener("click", () => {
          send(`take|${index}`);
          setView("record");
        });
        return card;
      }),
    );
  } else {
    const empty = document.createElement("div");
    empty.className = "empty-library";
    empty.textContent =
      "Your recordings will appear here after you finish a take.";
    list.replaceChildren(empty);
  }
  requestBounds();
}

bridge?.addEventListener("message", ({ data }) => {
  if (data?.kind === "state") {
    state = data;
    render();
  }
});
$("library-button").addEventListener("click", () => {
  send("refresh");
  setView("library");
});
$("back-button").addEventListener("click", () => setView("record"));
$("refresh-button").addEventListener("click", () => send("refresh"));
$("camera-row").addEventListener("click", () => send("audio|camera"));
$("microphone-row").addEventListener("click", () => send("audio|microphone"));
$("system-row").addEventListener("click", () => send("audio|system"));
$("screen-row").addEventListener("click", () => $("target-select").focus());
$("record-button").addEventListener("click", () =>
  send(state.recording ? "stop" : "start"),
);
$("open-button").addEventListener("click", () => send("open"));
$("play-button").addEventListener("click", () => send("pause"));
$("export-button").addEventListener("click", () => send("export"));
$("target-select").addEventListener("change", (event) =>
  send(`target|${event.target.value}`),
);
new ResizeObserver(requestBounds).observe($("preview-frame"));
window.addEventListener("resize", requestBounds);
window.addEventListener("keydown", (event) => {
  if (
    event.code === "Space" &&
    event.target.tagName !== "SELECT" &&
    event.target.tagName !== "BUTTON"
  ) {
    event.preventDefault();
    if (state.recording) send("stop");
    else if (state.playing) send("pause");
    else send("start");
  }
  if (event.code === "Escape" && state.recording) send("stop");
});
send("ready");
