; Dark Crown Browser — установщик (Inno Setup 6)
; Собирается скриптом make-installer.ps1 после подготовки папки stage\.

#define AppName "Dark Crown Browser"
#define AppVersion "1.4.0"

[Setup]
AppId={{B7D2C8E4-3F1A-4C59-9A61-5D0E7C2B8F13}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Dark Crown
DefaultDirName={code:GetDefaultDir}
DefaultGroupName=Dark Crown
SetupIconFile=icon.ico
UninstallDisplayIcon={app}\icon.ico
OutputDir=dist
OutputBaseFilename=DarkCrown-Setup
Compression=lzma2/fast
SolidCompression=no
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "accent_gold"; Description: "Золотой"; GroupDescription: "Цвет темы:"; Flags: exclusive
Name: "accent_purple"; Description: "Фиолетовый"; GroupDescription: "Цвет темы:"; Flags: exclusive unchecked
Name: "accent_red"; Description: "Красный"; GroupDescription: "Цвет темы:"; Flags: exclusive unchecked
Name: "accent_green"; Description: "Зелёный"; GroupDescription: "Цвет темы:"; Flags: exclusive unchecked
Name: "accent_black"; Description: "Чёрный"; GroupDescription: "Цвет темы:"; Flags: exclusive unchecked
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"

[Files]
Source: "stage\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "icon.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "crowntools.xpi"; DestDir: "{app}"; Flags: ignoreversion
Source: "userChrome.css"; DestDir: "{userappdata}\DarkCrown\Profile\chrome"; Flags: ignoreversion
Source: "userContent.css"; DestDir: "{userappdata}\DarkCrown\Profile\chrome"; Flags: ignoreversion
Source: "logo.css"; DestDir: "{userappdata}\DarkCrown\Profile\chrome"; Flags: ignoreversion
Source: "themes\gold.css"; DestDir: "{userappdata}\DarkCrown\Profile\chrome"; DestName: "accent.css"; Flags: ignoreversion; Tasks: accent_gold
Source: "themes\purple.css"; DestDir: "{userappdata}\DarkCrown\Profile\chrome"; DestName: "accent.css"; Flags: ignoreversion; Tasks: accent_purple
Source: "themes\red.css"; DestDir: "{userappdata}\DarkCrown\Profile\chrome"; DestName: "accent.css"; Flags: ignoreversion; Tasks: accent_red
Source: "themes\green.css"; DestDir: "{userappdata}\DarkCrown\Profile\chrome"; DestName: "accent.css"; Flags: ignoreversion; Tasks: accent_green
Source: "themes\black.css"; DestDir: "{userappdata}\DarkCrown\Profile\chrome"; DestName: "accent.css"; Flags: ignoreversion; Tasks: accent_black

[Icons]
Name: "{group}\Dark Crown"; Filename: "{app}\librewolf.exe"; Parameters: "-profile ""{userappdata}\DarkCrown\Profile"" -no-remote"; IconFilename: "{app}\icon.ico"
Name: "{autodesktop}\Dark Crown"; Filename: "{app}\librewolf.exe"; Parameters: "-profile ""{userappdata}\DarkCrown\Profile"" -no-remote"; IconFilename: "{app}\icon.ico"; Tasks: desktopicon

[Run]
Filename: "{sys}\icacls.exe"; Parameters: """{app}"" /inheritance:r /grant:r *S-1-5-18:(OI)(CI)F *S-1-5-32-544:(OI)(CI)F *S-1-5-32-545:(OI)(CI)RX"; Flags: runhidden waituntilterminated; StatusMsg: "Защита папки программы..."
Filename: "{app}\librewolf.exe"; Parameters: "-profile ""{userappdata}\DarkCrown\Profile"" -no-remote"; Description: "Запустить Dark Crown"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; При удалении стираем профиль и всё, что браузер сохранял
Type: filesandordirs; Name: "{userappdata}\DarkCrown"
Type: filesandordirs; Name: "{localappdata}\DarkCrown"

[Code]
// Диск с наибольшим свободным местом (только жёсткие диски, не флешки и не сеть)
function GetDriveType(lpRootPathName: String): Cardinal;
  external 'GetDriveTypeW@kernel32.dll stdcall';

function GetDefaultDir(Param: String): String;
var
  i: Integer;
  Root, Best, PfDrive: String;
  Free, Total, BestFree: Int64;
begin
  Best := '';
  BestFree := 0;
  for i := Ord('C') to Ord('Z') do
  begin
    Root := Chr(i) + ':\';
    if GetDriveType(Root) = 3 then   // 3 = жёсткий диск
      if GetSpaceOnDisk64(Root, Free, Total) then
        if Free > BestFree then
        begin
          BestFree := Free;
          Best := Root;
        end;
  end;
  PfDrive := ExtractFileDrive(ExpandConstant('{autopf}')) + '\';
  if (Best = '') or (CompareText(Best, PfDrive) = 0) then
    Result := ExpandConstant('{autopf}\Dark Crown')
  else
    Result := Best + 'Dark Crown';
end;
// Подставляем реальную папку установки в policies.json (для расширения Crown Tools)
procedure CurStepChanged(CurStep: TSetupStep);
var
  PolFile: String;
  Raw: AnsiString;
  Txt: String;
  AppUrl: String;
begin
  if CurStep = ssPostInstall then
  begin
    PolFile := ExpandConstant('{app}\distribution\policies.json');
    if LoadStringFromFile(PolFile, Raw) then
    begin
      Txt := String(Raw);
      AppUrl := ExpandConstant('{app}');
      StringChangeEx(AppUrl, '\', '/', True);
      StringChangeEx(AppUrl, ' ', '%20', True);
      StringChangeEx(Txt, '@@APP@@', AppUrl, True);
      SaveStringToFile(PolFile, AnsiString(Txt), False);
    end;
  end;
end;
