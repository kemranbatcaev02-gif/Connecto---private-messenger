; Connecto for Windows installer (Inno Setup 6: https://jrsoftware.org/isdl.php)
; 1) flutter build windows --release
; 2) open this file in Inno Setup and press Compile (Ctrl+F9)
; Result: app\build\installer\Connecto-Setup.exe

#define MyAppName "Connecto"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppExeName "Connecto.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{8E2F6A51-3C1D-4B7A-9E55-6A2C0B7D4F11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Connecto
DefaultDirName={localappdata}\Programs\Connecto
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=Connecto-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Visual C++ runtime (64-bit) next to the exe, so it starts on any PC.
; build_all.ps1 copies it from the real System32 into build\vcrt: the Inno Setup compiler
; is a 32-bit program and would get the 32-bit DLLs from C:\Windows\System32 (error 0xc000007b).
Source: "..\build\vcrt\*.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "Connecto.Messenger.Desktop"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
