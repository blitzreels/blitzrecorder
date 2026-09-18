#define MyAppName "BlitzRecorder"
#ifndef AppVersion
#define AppVersion "0.20.0"
#endif
#ifndef VersionInfoVersion
#define VersionInfoVersion "0.20.0.0"
#endif

[Setup]
AppId={{A7B2C4D1-8E5F-4A91-9C33-6F1E2A8B4C7D}
AppName={#MyAppName}
AppVersion={#AppVersion}
VersionInfoVersion={#VersionInfoVersion}
AppPublisher=BlitzReels
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputBaseFilename=BlitzRecorder-Windows
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UsePreviousAppDir=no
WizardStyle=modern
SetupIconFile=..\..\Apps\WindowsStudio\BlitzRecorder.ico
UninstallDisplayIcon={app}\BlitzRecorder.ico
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows-stage\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
#if Ver >= 0x06020000
Name: "{group}\{#MyAppName}"; Filename: "{app}\BlitzRecorderWindows.exe"; IconFilename: "{app}\BlitzRecorder.ico"; AppUserModelID: "BlitzReels.BlitzRecorder"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\BlitzRecorderWindows.exe"; IconFilename: "{app}\BlitzRecorder.ico"; AppUserModelID: "BlitzReels.BlitzRecorder"; Tasks: desktopicon
#else
Name: "{group}\{#MyAppName}"; Filename: "{app}\BlitzRecorderWindows.exe"; IconFilename: "{app}\BlitzRecorder.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\BlitzRecorderWindows.exe"; IconFilename: "{app}\BlitzRecorder.ico"; Tasks: desktopicon
#endif

[Run]
Filename: "{app}\BlitzRecorderWindows.exe"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
