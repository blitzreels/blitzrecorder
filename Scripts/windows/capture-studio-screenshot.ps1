param(
    [string]$StageDir = "build\windows-stage",
    [string]$OutputPath = "build\windows-store\Studio-Screenshot.png"
)

$ErrorActionPreference = "Stop"
$exe = (Resolve-Path (Join-Path $StageDir "BlitzRecorderWindows.exe")).Path
$output = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputPath))
New-Item (Split-Path $output) -ItemType Directory -Force | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class BlitzWindowCapture {
    [StructLayout(LayoutKind.Sequential)]
    public struct WindowRect {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr handle);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr handle, StringBuilder text, int capacity);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr handle, int command);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr GetProp(IntPtr handle, string name);
    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr handle, int attribute, out WindowRect value, int size);
}
"@

$previousScreenshotMode = $env:BLITZRECORDER_STORE_SCREENSHOT
$env:BLITZRECORDER_STORE_SCREENSHOT = "1"
$process = Start-Process $exe -PassThru
try {
    $window = [IntPtr]::Zero
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 250
        $process.Refresh()
        if ($process.HasExited) { throw "Windows Studio exited before its window appeared" }
        $window = $process.MainWindowHandle
        if ($window -ne [IntPtr]::Zero) { break }
    }
    if ($window -eq [IntPtr]::Zero) { throw "Windows Studio did not open a desktop window" }
    $title = New-Object System.Text.StringBuilder 256
    [BlitzWindowCapture]::GetWindowText($window, $title, $title.Capacity) | Out-Null
    if ($title.ToString() -ne "BlitzRecorder") { throw "Unexpected Windows Studio window: $title" }
    [BlitzWindowCapture]::ShowWindow($window, 9) | Out-Null
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    [BlitzWindowCapture]::SetWindowPos($window, [IntPtr](-1), $bounds.Left, $bounds.Top, $bounds.Width, $bounds.Height, 0x0040) | Out-Null
    [BlitzWindowCapture]::SetForegroundWindow($window) | Out-Null
    $workspaceReady = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ([BlitzWindowCapture]::GetProp($window, "BlitzWorkspaceReady") -ne [IntPtr]::Zero) {
            $workspaceReady = $true
            break
        }
        if ($process.HasExited) { throw "Windows Studio exited before the workspace loaded" }
        Start-Sleep -Milliseconds 500
    }
    if (-not $workspaceReady) { throw "Windows workspace did not load within 20 seconds" }
    Start-Sleep -Seconds 1
    $visible = New-Object BlitzWindowCapture+WindowRect
    $rectSize = [System.Runtime.InteropServices.Marshal]::SizeOf($visible)
    $dwmResult = [BlitzWindowCapture]::DwmGetWindowAttribute($window, 9, [ref]$visible, $rectSize)
    if ($dwmResult -ne 0) { throw "Could not read visible Windows Studio bounds: $dwmResult" }
    $captureWidth = $visible.Right - $visible.Left
    $captureHeight = $visible.Bottom - $visible.Top
    if ($captureWidth -lt 800 -or $captureHeight -lt 600) {
        throw "Windows Studio bounds too small: ${captureWidth}x${captureHeight}"
    }
    $bitmap = New-Object System.Drawing.Bitmap($captureWidth, $captureHeight)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $origin = [System.Drawing.Point]::new($visible.Left, $visible.Top)
        $size = [System.Drawing.Size]::new($captureWidth, $captureHeight)
        $graphics.CopyFromScreen($origin, [System.Drawing.Point]::Empty, $size)
        $bitmap.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    Write-Host "Windows Studio screenshot: $output (${captureWidth}x${captureHeight})"
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    $env:BLITZRECORDER_STORE_SCREENSHOT = $previousScreenshotMode
}
