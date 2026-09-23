# Merge vcvars into the current process. Do not replace PATH wholesale —
# setup-swift lives on PATH and must survive.

function Get-VsWhere {
    @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Enter-MsvcDevCmd([string]$vsArch) {
    if ($env:VSCMD_ARG_TGT_ARCH -eq $vsArch -and $env:INCLUDE -and $env:LIB -and (Get-Command cl -ErrorAction SilentlyContinue)) {
        return $true
    }
    $vswhere = Get-VsWhere
    if (-not $vswhere) { return $false }
    $vsPath = & $vswhere -latest -products * -property installationPath
    if (-not $vsPath) { return $false }
    $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
    if (-not (Test-Path $vcvars)) { return $false }
    Write-Host "vcvarsall $vsArch ($vsPath) (merge INCLUDE/LIB; keep Swift PATH)"
    $map = @{}
    cmd /c "`"$vcvars`" $vsArch >nul && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $map[$Matches[1]] = $Matches[2]
        }
    }
    if ($map.Count -eq 0) { return $false }
    foreach ($key in @(
        "INCLUDE", "LIB", "LIBPATH",
        "WindowsSdkDir", "WindowsSDKVersion", "WindowsSDKLibVersion",
        "VCINSTALLDIR", "VCToolsInstallDir", "VCToolsVersion",
        "UniversalCRTSdkDir", "UCRTVersion",
        "DevEnvDir", "VSINSTALLDIR",
        "WindowsLibPath", "ExtensionSdkDir", "VSCMD_ARG_TGT_ARCH"
    )) {
        if ($map.ContainsKey($key) -and $map[$key]) {
            Set-Item -Path "Env:$key" -Value $map[$key]
        }
    }
    $vcPath = $null
    if ($map.ContainsKey("Path")) { $vcPath = $map["Path"] }
    elseif ($map.ContainsKey("PATH")) { $vcPath = $map["PATH"] }
    if ($vcPath) {
        $env:PATH = "$vcPath;$env:PATH"
    }
    return [bool](Get-Command cl -ErrorAction SilentlyContinue)
}
