unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Windows, Registry, AniParser;

type
  { A simple record to keep track of each file and its assigned role }
  TCursorData = record
    FilePath: string;
    FileName: string;
    Role: string;
  end;

  { TForm1 }
  TForm1 = class(TForm)
    Bevel1: TBevel;
    Bevel2: TBevel;
    Bevel3: TBevel;
    Bevel5: TBevel;
    BtnBrowse: TButton;
    BtnApply: TButton;
    BtnReset: TButton;
    CmbRoles: TComboBox;
    Label2: TLabel;
    Label3: TLabel;
    ListBox1: TListBox;
    SelectDirDialog: TSelectDirectoryDialog;
    Label1: TLabel;
    MemoMetadata: TMemo;
    PnlPreview: TPanel;
    procedure Bevel2ChangeBounds(Sender: TObject);
    procedure BtnApplyClick(Sender: TObject);
    procedure BtnBrowseClick(Sender: TObject);
    procedure CmbRolesChange(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Label2Click(Sender: TObject);
    procedure ListBox1SelectionChange(Sender: TObject; User: boolean);
    procedure PnlPreviewPaint(Sender: TObject);
    procedure BtnResetClick(Sender: TObject);
  private
    CursorList: array of TCursorData;
    hCurrentPreview: HCURSOR; // Keeps track of the loaded cursor in Windows memory
    function GuessCursorRole(FileName: string): string;
    function GetRegistryKeyName(FriendlyName: string): string;
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

const
  // Windows API constants for instant cursor refreshing
  SPI_SETCURSORS = $0057;
  SPIF_UPDATEINIFILE = $01;
  SPIF_SENDCHANGE = $02;
  PREVIEW_CURSOR_ID = 1; // A custom ID for our hover animation

{ TForm1 }
// ==========================================
// REGISTRY DICTIONARY: FRIENDLY -> INTERNAL
// ==========================================
function TForm1.GetRegistryKeyName(FriendlyName: string): string;
begin
  if FriendlyName = 'Normal Select' then Result := 'Arrow'
  else if FriendlyName = 'Help Select' then Result := 'Help'
  else if FriendlyName = 'Working in Background' then Result := 'AppStarting'
  else if FriendlyName = 'Busy' then Result := 'Wait'
  else if FriendlyName = 'Precision Select' then Result := 'Crosshair'
  else if FriendlyName = 'Text Select' then Result := 'IBeam'
  else if FriendlyName = 'Handwriting' then Result := 'NWPen'
  else if FriendlyName = 'Unavailable' then Result := 'No'
  else if FriendlyName = 'Vertical Resize' then Result := 'SizeNS'
  else if FriendlyName = 'Horizontal Resize' then Result := 'SizeWE'
  else if FriendlyName = 'Diagonal Resize 1' then Result := 'SizeNWSE'
  else if FriendlyName = 'Diagonal Resize 2' then Result := 'SizeNESW'
  else if FriendlyName = 'Move' then Result := 'SizeAll'
  else if FriendlyName = 'Alternate Select' then Result := 'UpArrow'
  else if FriendlyName = 'Link Select' then Result := 'Hand'
  else if FriendlyName = 'Location Select' then Result := 'Pin'
  else if FriendlyName = 'Person Select' then Result := 'Person'
  else Result := 'Skip';
end;
/// ==========================================
// THE GUESSING ENGINE (EXPANDED FOR WIN 10)
// ==========================================
function TForm1.GuessCursorRole(FileName: string): string;
var
  LowerName: string;
begin
  LowerName := LowerCase(FileName);
  Result := 'Skip'; // Default

  if (Pos('arrow', LowerName) > 0) or (Pos('normal', LowerName) > 0) then Result := 'Normal Select'
  else if (Pos('help', LowerName) > 0) then Result := 'Help Select'
  else if (Pos('work', LowerName) > 0) or (Pos('start', LowerName) > 0) then Result := 'Working in Background'
  else if (Pos('wait', LowerName) > 0) or (Pos('busy', LowerName) > 0) then Result := 'Busy'
  else if (Pos('cross', LowerName) > 0) or (Pos('prec', LowerName) > 0) then Result := 'Precision Select'
  else if (Pos('text', LowerName) > 0) or (Pos('beam', LowerName) > 0) then Result := 'Text Select'
  else if (Pos('pen', LowerName) > 0) or (Pos('handwrit', LowerName) > 0) then Result := 'Handwriting'
  else if (Pos('no', LowerName) > 0) or (Pos('unavail', LowerName) > 0) then Result := 'Unavailable'
  else if (Pos('ns', LowerName) > 0) or (Pos('vert', LowerName) > 0) then Result := 'Vertical Resize'
  else if (Pos('we', LowerName) > 0) or (Pos('horz', LowerName) > 0) or (Pos('hori', LowerName) > 0) then Result := 'Horizontal Resize'
  else if (Pos('nwse', LowerName) > 0) or (Pos('diag1', LowerName) > 0) then Result := 'Diagonal Resize 1'
  else if (Pos('nesw', LowerName) > 0) or (Pos('diag2', LowerName) > 0) then Result := 'Diagonal Resize 2'
  else if (Pos('move', LowerName) > 0) or (Pos('sizeall', LowerName) > 0) then Result := 'Move'
  else if (Pos('up', LowerName) > 0) or (Pos('alt', LowerName) > 0) then Result := 'Alternate Select'
  else if (Pos('link', LowerName) > 0) or (Pos('hand', LowerName) > 0) then Result := 'Link Select'
  else if (Pos('pin', LowerName) > 0) or (Pos('loc', LowerName) > 0) then Result := 'Location Select'
  else if (Pos('person', LowerName) > 0) then Result := 'Person Select';
end;

// ==========================================
// BROWSE BUTTON: SCAN FOLDER
// ==========================================
procedure TForm1.BtnBrowseClick(Sender: TObject);
var
  SR: TSearchRec;
  i: Integer;
  GuessedRole: string;
begin
  if SelectDirDialog.Execute then
  begin
    ListBox1.Clear;
    SetLength(CursorList, 0);
    i := 0;

    // Scan the directory for .cur and .ani files
    if FindFirst(SelectDirDialog.FileName + '\*.*', faAnyFile, SR) = 0 then
    begin
      repeat
        if (ExtractFileExt(SR.Name) = '.cur') or (ExtractFileExt(SR.Name) = '.ani') then
        begin
          SetLength(CursorList, i + 1);
          CursorList[i].FilePath := SelectDirDialog.FileName + '\' + SR.Name;
          CursorList[i].FileName := SR.Name;

          GuessedRole := GuessCursorRole(SR.Name);
          CursorList[i].Role := GuessedRole;

          ListBox1.Items.Add(SR.Name);
          Inc(i);
        end;
      until FindNext(SR) <> 0;

      // Use SysUtils to avoid Windows API collision
      SysUtils.FindClose(SR);
    end;

    if i > 0 then ListBox1.ItemIndex := 0;
  end;
end;

// ==========================================
// LISTBOX CLICKED: LOAD & PARSE
// ==========================================
procedure TForm1.ListBox1SelectionChange(Sender: TObject; User: boolean);
var
  Idx: Integer;
  WidePath: UnicodeString;
  FileExt: string;
begin
  Idx := ListBox1.ItemIndex;
  if Idx >= 0 then
  begin
    CmbRoles.ItemIndex := CmbRoles.Items.IndexOf(CursorList[Idx].Role);

    // 1. USE THE NEW PARSER SUB-MODULE
    FileExt := LowerCase(ExtractFileExt(CursorList[Idx].FilePath));
    if FileExt = '.ani' then
    begin
      MemoMetadata.Text := ParseAniMetadata(CursorList[Idx].FilePath);
    end
    else
    begin
      MemoMetadata.Text := 'Static .cur file' + sLineBreak + 'Frames: 1';
    end;

    // 2. RENDER THE PREVIEW
    if hCurrentPreview <> 0 then DestroyCursor(hCurrentPreview);

    // Safely convert string to Windows WideChar
    WidePath := UTF8Decode(CursorList[Idx].FilePath);

    // LoadImageW handles standard formats better than LoadCursorFromFile
    hCurrentPreview := LoadImageW(0, PWideChar(WidePath), 2, 0, 0, $0010 or $0040);

    if hCurrentPreview = 0 then
    begin
      ShowMessage('Windows refused to load this file: ' + CursorList[Idx].FilePath);
    end
    else
    begin
      Screen.Cursors[PREVIEW_CURSOR_ID] := hCurrentPreview;
      PnlPreview.Cursor := PREVIEW_CURSOR_ID;

      // Force the Panel to draw right now
      PnlPreview.Repaint;
    end;
  end;
end;

// ==========================================
// PANEL DRAWING: DIRECT WIN-API INJECTION
// ==========================================
procedure TForm1.PnlPreviewPaint(Sender: TObject);
var
  cx, cy: Integer;
begin
  // 1. Draw the clean silver background
  PnlPreview.Canvas.Brush.Color := clSilver;
  PnlPreview.Canvas.FillRect(0, 0, PnlPreview.Width, PnlPreview.Height);

  if hCurrentPreview <> 0 then
  begin
    cx := (PnlPreview.Width - 32) div 2;
    cy := (PnlPreview.Height - 32) div 2;

    // 2. Command Windows to draw directly onto the Panel's physical screen handle!
    // This bypasses the Lazarus graphics engine entirely, avoiding the Alpha Trap.
    DrawIconEx(PnlPreview.Canvas.Handle, cx, cy, hCurrentPreview, 32, 32, 0, 0, $0003);
  end;
end;

// ==========================================
// COMBOBOX CHANGED (MANUAL OVERRIDE)
// ==========================================
procedure TForm1.CmbRolesChange(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := ListBox1.ItemIndex;
  if (Idx >= 0) and (CmbRoles.ItemIndex >= 0) then
  begin
    CursorList[Idx].Role := CmbRoles.Text;
  end;
end;

// ==========================================
// APPLY BUTTON: WRITE TO REGISTRY
// ==========================================
procedure TForm1.BtnApplyClick(Sender: TObject);
var
  Reg: TRegistry;
  i, AppliedCount: Integer;
begin
  AppliedCount := 0;
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('\Control Panel\Cursors', True) then
    begin
      for i := 0 to High(CursorList) do
      begin
        if CursorList[i].Role <> 'Skip' then
        begin
          Reg.WriteString(GetRegistryKeyName(CursorList[i].Role), CursorList[i].FilePath);
          Inc(AppliedCount);
        end;
      end;
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;

  if AppliedCount > 0 then
  begin
    // Broadcast to Windows to reload cursors natively
    SystemParametersInfo(SPI_SETCURSORS, 0, nil, SPIF_UPDATEINIFILE or SPIF_SENDCHANGE);
    ShowMessage('Successfully applied ' + IntToStr(AppliedCount) + ' cursors!');
  end
  else
    ShowMessage('No cursors were assigned to roles.');
end;

procedure TForm1.Bevel2ChangeBounds(Sender: TObject);
begin

end;

// ==========================================
// RESET BUTTON: RESTORE WINDOWS DEFAULTS
// ==========================================
procedure TForm1.BtnResetClick(Sender: TObject);
var
  Reg: TRegistry;
  RolesToReset: array of string;
  i: Integer;
begin
  // An array of every single registry codename we need to wipe clean
  RolesToReset := ['Arrow', 'Help', 'AppStarting', 'Wait', 'Crosshair',
                   'IBeam', 'NWPen', 'No', 'SizeNS', 'SizeWE', 'SizeNWSE',
                   'SizeNESW', 'SizeAll', 'UpArrow', 'Hand', 'Pin', 'Person'];

  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('\Control Panel\Cursors', True) then
    begin
      // Loop through and overwrite every custom path with a blank string
      for i := Low(RolesToReset) to High(RolesToReset) do
      begin
        Reg.WriteString(RolesToReset[i], '');
      end;

      // Clear the current "Scheme" name just in case
      Reg.WriteString('', '');

      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;

  // Broadcast to Windows to reload. Since the keys are blank, it loads the defaults!
  SystemParametersInfo(SPI_SETCURSORS, 0, nil, SPIF_UPDATEINIFILE or SPIF_SENDCHANGE);
  ShowMessage('Cursors have been successfully restored to Windows defaults!');
end;

// ==========================================
// CLEANUP MEMORY ON EXIT
// ==========================================
procedure TForm1.FormDestroy(Sender: TObject);
begin
  if hCurrentPreview <> 0 then DestroyCursor(hCurrentPreview);
end;

procedure TForm1.Label2Click(Sender: TObject);
begin

end;

end.
