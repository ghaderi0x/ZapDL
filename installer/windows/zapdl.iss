; Inno Setup script for ZapDL (https://jrsoftware.org/isinfo.php)
; Build:  iscc /DAppVersion=1.2.3 installer\windows\zapdl.iss
; Input:  build\windows\x64\runner\Release  (flutter build windows --release)
; Output: dist\ZapDL-<version>-windows-x64-setup.exe
;
; The updater runs this installer with /SILENT /CLOSEAPPLICATIONS
; /RESTARTAPPLICATIONS, so keep AppId stable: it is what makes a new setup
; upgrade the existing installation in place.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{7C1D2B84-5E0A-4B35-9F47-3A9D6E21B0C5}
AppName=ZapDL
UninstallDisplayName=ZapDL
AppVersion={#AppVersion}
AppPublisher=ZapDL contributors
AppPublisherURL=https://github.com/ghaderi0x/ZapDL
AppSupportURL=https://github.com/ghaderi0x/ZapDL/issues
DefaultDirName={autopf}\ZapDL
DefaultGroupName=ZapDL
UninstallDisplayIcon={app}\zapdl.exe
OutputDir=..\..\dist
OutputBaseFilename=ZapDL-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
; Per-user install by default: no administrator prompt, so silent updates work.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=yes
WizardStyle=modern

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\ZapDL"; Filename: "{app}\zapdl.exe"
Name: "{autodesktop}\ZapDL"; Filename: "{app}\zapdl.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\zapdl.exe"; Description: "Launch ZapDL"; Flags: nowait postinstall skipifsilent
