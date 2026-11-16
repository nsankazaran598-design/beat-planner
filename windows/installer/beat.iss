; Установщик beat для Windows (Inno Setup 6).
; Сборка: ISCC /DAppVersion=1.0.0 windows\installer\beat.iss
; Ожидает собранное приложение в build\windows\x64\runner\Release.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "beat"
#define AppExe "beat.exe"
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{8C4F7A2E-5B1D-4E7A-9F3C-2D6B8E1A4C90}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=beat
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Права администратора нужны для правила брандмауэра (синхронизация по Wi‑Fi).
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=beat-setup-x64
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Закрыть работающий beat (он может быть свёрнут в трей) перед обновлением.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "firewall"; Description: "Разрешить синхронизацию с телефоном по Wi‑Fi (брандмауэр, частная сеть)"; GroupDescription: "Синхронизация:"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Удалить {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall delete rule name=""beat"""; \
  Flags: runhidden; Tasks: firewall
Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall add rule name=""beat"" dir=in action=allow program=""{app}\{#AppExe}"" profile=private enable=yes"; \
  Flags: runhidden; Tasks: firewall
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""beat"""; \
  Flags: runhidden; RunOnceId: "RemoveFirewallRule"
; Автозапуск, если его включали в настройках beat.
Filename: "{sys}\reg.exe"; \
  Parameters: "delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v beat /f"; \
  Flags: runhidden; RunOnceId: "RemoveAutostart"
