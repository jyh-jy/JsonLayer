; ============================================================
;  JsonLayer — Inno Setup 安装脚本
; ------------------------------------------------------------
;  通常不要手动改版本号，由 tool/build_windows_installer.ps1
;  读取 pubspec.yaml 并通过 /DMyAppVersion= 命令行参数注入。
;
;  手动编译示例：
;    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ^
;        /DMyAppVersion=1.0.5 installer\json_layer.iss
; ============================================================

#define MyAppName      "JsonLayer"
#define MyAppPublisher "JsonLayer"
#define MyAppUrl       "https://github.com/"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.5"
#endif
#ifndef MyAppUpdatesUrl
  #define MyAppUpdatesUrl MyAppUrl
#endif
#define MyAppExeName   "json_layer.exe"

; 固定 AppId（升级检测基于此，请勿修改）
#define MyAppId        "{{B8E0F3A2-4D7B-4F0C-9E8A-2C6D5E1A3B71}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppUrl}
AppSupportURL={#MyAppUrl}
AppUpdatesURL={#MyAppUpdatesUrl}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; 允许输出版本号差异而升级时保留目录
DisableDirPage=auto
DisableProgramGroupPage=yes
; 安装包图标（使用 Windows 资源里的 ICO）
SetupIconFile={#SourcePath}\..\windows\runner\resources\app_icon.ico
; 卸载程序图标
UninstallDisplayIcon={app}\{#MyAppExeName}
; 输出目录
OutputDir={#SourcePath}\..\dist\inno_setup
OutputBaseFilename={#MyAppName}-{#MyAppVersion}-windows-x64-setup
; 压缩
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64
; 单实例
SetupMutex=json_layer_setup_mutex
CloseApplications=force
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english";     MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "openjson"; Description: "将 .json 文件与 JsonLayer 关联"; GroupDescription: "文件关联:"; Flags: unchecked

[Files]
; 主程序目录（递归复制 Flutter Release 产物）
Source: "{#SourcePath}\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}";           Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}";     Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{group}\卸载 {#MyAppName}";      Filename: "{uninstallexe}"

[Registry]
; --- .json 文件关联（Tasks: openjson）---
Root: HKCU; Subkey: "Software\Classes\.json";              ValueType: string; ValueName: "";          ValueData: "JsonLayer.json";    Flags: uninsdeletevalue; Tasks: openjson
Root: HKCU; Subkey: "Software\Classes\JsonLayer.json";    ValueType: string; ValueName: "";          ValueData: "JSON File";         Flags: uninsdeletekey;   Tasks: openjson
Root: HKCU; Subkey: "Software\Classes\JsonLayer.json";    ValueType: string; ValueName: "FriendlyTypeName"; ValueData: "JSON File";    Flags: uninsdeletevalue; Tasks: openjson
Root: HKCU; Subkey: "Software\Classes\JsonLayer.json\DefaultIcon"; ValueType: string; ValueName: "";  ValueData: "{app}\{#MyAppExeName},0"; Flags: uninsdeletekey; Tasks: openjson
Root: HKCU; Subkey: "Software\Classes\JsonLayer.json\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey; Tasks: openjson

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
