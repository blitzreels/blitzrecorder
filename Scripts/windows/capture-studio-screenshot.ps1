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
public static class BlitzWindowCapture {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr handle);
}
"@

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
    [BlitzWindowCapture]::SetForegroundWindow($window) | Out-Null
    Start-Sleep -Seconds 2
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    Write-Host "Windows Studio screenshot: $output ($($bounds.Width)x$($bounds.Height))"
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
}
