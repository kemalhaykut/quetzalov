; Quetzalov kurulum betiği (Inno Setup 6)
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

[Setup]
AppId=Quetzalov.IPTV.Player
AppName=Quetzalov
AppVersion={#MyAppVersion}
AppPublisher=Quetzalov
DefaultDirName={autopf}\Quetzalov
DefaultGroupName=Quetzalov
DisableProgramGroupPage=yes
OutputDir=..
OutputBaseFilename=Quetzalov-Kurulum
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\quetzalov.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "Masaüstü kısayolu oluştur"; GroupDescription: "Ek kısayollar:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Quetzalov"; Filename: "{app}\quetzalov.exe"
Name: "{autodesktop}\Quetzalov"; Filename: "{app}\quetzalov.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\quetzalov.exe"; Description: "Quetzalov'u başlat"; Flags: nowait postinstall skipifsilent
