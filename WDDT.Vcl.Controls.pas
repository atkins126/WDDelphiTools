unit WDDT.Vcl.Controls;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Math,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.Dialogs,
  Vcl.Graphics;

procedure PerformCtrlBackspaceAction(CustomEdit: TCustomEdit);
function CursorRow(Memo: TMemo): Integer;
procedure UnSelect(TargetControl: TControl);
function GetControlsBoundBox(Parent: TWinControl): TRect;
procedure AddComboTextToMFU(ComboBox: TComboBox);
function CalcRequiredControlHeight(Parent: TWinControl): Integer;
function GetSystemMessageIcon(Value: TMsgDlgType): TIcon;
procedure SetGeneralMouseWheelHandler(TargetForm: TForm);

function HasFirstSiblingControlByClass(RefControl: TWinControl; RequestedClass: TControlClass;
  out FoundControl: TControl): Boolean;
function HasFirstSiblingEdit(RefControl: TWinControl; out EditControl: TEdit): Boolean;
function HasParentControlByClass(RefControl: TControl; RequestedParentClass: TWinControlClass;
  out FoundParentControl: TWinControl): Boolean; overload;
function HasParentControlByClass(RefControl: TControl;
  RequestedParentClass: TWinControlClass): Boolean; overload;
function HasChildFormByClass(RefForm: TCustomForm; RequestedFormClass: TCustomFormClass;
  out FoundChildForm: TCustomForm): Boolean;
function HasAssignedLabel(Control: TControl; out FoundLabel: TCustomLabel): Boolean;
procedure HandleCheckboxGroup(Sender: TObject; CheckboxGroup: array of TCheckBox);
procedure RouteLabelClick(Sender: TObject);

function HasScrollableScrollbar(Control: TControl; Kind: TScrollBarKind;
  out Scrollbar: TControlScrollBar): Boolean;
function HasControlMouseWheelSupport(AControl: TComponent;
  AdditionalAccepts: array of TComponentClass): Boolean;

implementation

// Implementiert das von Windows bekannte Verhalten in Eingabefeldern bei [STRG] + [Backspace]
//
// Einfachste Einbindung im OnKeyPress-Event der jeweiligen TEdit- oder TMemo-Instanz mit folgendem
// Code-Fragment:
//  if Key = #127 then
//  begin
//    PerformCtrlBackspaceAction(mleInhalt);
//    Key := #0;
//  end;
procedure PerformCtrlBackspaceAction(CustomEdit: TCustomEdit);
var
  LastStart: Integer;

  function LastWordPos(const Src: string; Start: Integer): Integer;
  const
    SpaceChar = #32;
  var
    Pos: Integer absolute Result;

    function IsNLRelated(TestChar: Char): Boolean;
    begin
      Result := CharInSet(TestChar, [#10, #13]);
    end;

    procedure RewindToSpace(IgnoreNL: Boolean);
    begin
      while (Pos > 0) and (Src[Pos] <> SpaceChar) and
        (IgnoreNL or (not IgnoreNL and not IsNLRelated(Src[Pos]))) do
        Dec(Pos);
    end;

    procedure RewindToNonSpace;
    begin
      while (Pos > 0) and (Src[Pos] = SpaceChar) do
        Dec(Pos);
    end;

  begin
    if Start > Length(Src) then
      Start := Length(Src);

    Pos := Start;

    if Start = 0 then
      Exit;

    if Src[Start] = SpaceChar then
      RewindToNonSpace;

    RewindToSpace(IsNLRelated(Src[Start]));
  end;

begin
  LastStart := CustomEdit.SelStart;
  CustomEdit.SelStart := LastWordPos(CustomEdit.Text, LastStart);
  CustomEdit.SelLength := LastStart - CustomEdit.SelStart;
  CustomEdit.SelText:='';
end;

// Ermittelt Zeilennummer [Index], der Zeile, in der der Cursor steht
function CursorRow(Memo: TMemo): Integer;
var
  iPos, iLine: Integer;
begin
  iPos := -1;
  iLine := -1;
  while iPos < Memo.SelStart do
  begin
    Inc(iLine);
    // CR+LF nicht vergessen, ist bei SelStart mit eingerechnet!
    Inc(iPos, Succ(Succ(Length(Memo.Lines[iLine]))));
  end;
  Result := iLine;
end;

// Deselektiert den Text in TEdit,TMemo,TComboBox
procedure UnSelect(TargetControl: TControl);
var
  CustomEdit: TCustomEdit absolute TargetControl;
begin
  if Assigned(TargetControl) and (TargetControl is TCustomEdit) then
  begin
    CustomEdit.SelStart := Length(CustomEdit.Text);
    CustomEdit.SelLength := 0;
  end;
end;

// Liefert die Bounding-Box, die alle Child-Controls des �bergebenen Parent-Controls ber�cksichtigt
//
// Wenn keine Child-Controls vorhanden sind, so wird ein Rect (0, 0, 0, 0) geliefert.
function GetControlsBoundBox(Parent: TWinControl): TRect;
var
  cc: Integer;
  TempCtrl: TControl;
begin
  Result := Rect(MAXWORD, MAXWORD, -MAXWORD, -MAXWORD);
  try
    if not Assigned(Parent) then
      Exit;

    for cc := 0 to Parent.ControlCount - 1 do
    begin
      if Assigned(Parent.Controls[cc]) then
      begin
        TempCtrl := Parent.Controls[cc];
        if TempCtrl.Left < Result.Left then
          Result.Left := TempCtrl.Left;
        if TempCtrl.Top < Result.Top then
          Result.Top := TempCtrl.Top;
        if (TempCtrl.Left + TempCtrl.Width) > Result.Right then
          Result.Right := TempCtrl.Left + TempCtrl.Width;
        if (TempCtrl.Top + TempCtrl.Height) > Result.Bottom then
          Result.Bottom := TempCtrl.Top + TempCtrl.Height;
      end;
    end;
  finally
    if (Result.Left > Result.Right) or (Result.Top > Result.Bottom) then
      Result := Rect(0, 0, 0, 0);
  end;
end;

// F�gt den aktuellen Text der Combobox zu seiner Liste hinzu, wenn er dort noch nicht existiert
// oder schiebt ihn um eine Position h�her, falls er sich bereits in der Liste befindet.
//
// MFU = Most Frequent Used
procedure AddComboTextToMFU(ComboBox: TComboBox);
var
  TextIndex: Integer;
  Text: string;
begin
  Text := ComboBox.Text;
  if Trim(Text) = '' then
    Exit;

  TextIndex := ComboBox.Items.IndexOf(Text);
  if TextIndex = -1 then
    ComboBox.Items.Add(Text)
  else if TextIndex > 0 then
  begin
    ComboBox.Items.Exchange(TextIndex, TextIndex - 1);
    // Nach dem Tausch muss der Text erneut gesetzt werden, da er aus der Liste verschwindet.
    ComboBox.Text := Text;
  end;
end;

// Ermittelt die H�he aller Controls, die die Ausrichtung (Align in [alTop, alBottom]) haben
//
// Hinweise:
// - Controls, die nicht ausgerichtet sind, werden bei dieser Berechnungsart nicht ber�cksichtigt.
function CalcRequiredControlHeight(Parent: TWinControl): Integer;
var
  cc: Integer;
  CurrentControl: TControl;

  function CalcControlHeight: Integer;
  begin
    Result := CurrentControl.Height;
    if CurrentControl.AlignWithMargins then
      Result := Result + CurrentControl.Margins.Top + CurrentControl.Margins.Bottom;
  end;

begin
  Result := 0;

  for cc := 0 to Parent.ControlCount - 1 do
  begin
    CurrentControl := Parent.Controls[cc];
    if CurrentControl.Visible and (CurrentControl.Align in [alTop, alBottom]) then
      Result := Result + CalcControlHeight;
  end;
end;

// Liefert die System-Icons, die in Message-Dialogs verwendet werden
//
// Hinweise:
// - Das gelieferte Icon muss au�erhalb freigegeben werden
// - Es kann auch der Wert nil geliefert werden
function GetSystemMessageIcon(Value: TMsgDlgType): TIcon;
const
  SysIcon: array [TMsgDlgType] of PChar = (
    IDI_WARNING, // mtWarning
    IDI_ERROR, // mtError
    IDI_INFORMATION, // mtInformation
    IDI_QUESTION, // mtConfirmation
    nil); // mtCustom
begin
  if Value = mtCustom then
  begin
    Result := nil;
    Exit;
  end;

  Result := TIcon.Create;
  try
    Result.Handle := LoadIcon(Result.Handle, PChar(SysIcon[Value]));
  except
    Result.Free;
    raise;
  end;
end;

type
  TFormMouseWheelMediator = class(TComponent)
  public
    FPrevOnMouseWheel: TMouseWheelEvent;

    constructor Create(AOwner: TComponent); override;

    procedure MouseWheelHandler(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
  end;

// Setzt einen Event-Handler f�r OnMouseWheel-Event einer Form
//
// Der Handler implementiert das Scrollverhalten mittels des Mausrads in einer beliebigen
// TScrollBox
procedure SetGeneralMouseWheelHandler(TargetForm: TForm);
begin
  TFormMouseWheelMediator.Create(TargetForm);
end;

function HasFirstSiblingControlByClass(RefControl: TWinControl; RequestedClass: TControlClass;
  out FoundControl: TControl): Boolean;
var
  cc: Integer;
  TempControl: TControl;
begin
  Result := Assigned(RefControl) and Assigned(RefControl.Parent);
  if not Result then
    Exit;

  for cc := 0 to RefControl.Parent.ControlCount - 1 do
  begin
    TempControl := RefControl.Parent.Controls[cc];
    if (TempControl is RequestedClass) and (TempControl <> RefControl) then
    begin
      FoundControl := TempControl;
      Exit;
    end;
  end;

  Result := FALSE;
end;

// Sucht das erste TEdit-Control, welches den selben Parent hat, wie das �bergebene RefControl
// Wird als R�ckgabewert True geliefert, so wird auch das gefundene Edit im Ausgabeparameter
// EditControl gesetzt.
function HasFirstSiblingEdit(RefControl: TWinControl; out EditControl: TEdit): Boolean;
var
  FoundControl: TControl;
begin
  Result := HasFirstSiblingControlByClass(RefControl, TEdit, FoundControl);
  if Result then
    EditControl := TEdit(FoundControl);
end;

// Sucht aufsteigend vom RefControl aus nach dem 1. Parent, welches der �bergebenen Klasse
// entspricht. Wird es f�ndig, liefert es True als R�ckgabe und den entsprechenden Parent
// im Ausgabeparameter.
function HasParentControlByClass(RefControl: TControl; RequestedParentClass: TWinControlClass;
  out FoundParentControl: TWinControl): Boolean;
var
  ParentAssigned: Boolean;
begin
  ParentAssigned := Assigned(RefControl) and Assigned(RefControl.Parent);
  Result := ParentAssigned and (RefControl.Parent is RequestedParentClass);
  if Result then
    FoundParentControl := RefControl.Parent
  else if ParentAssigned then
    Result := HasParentControlByClass(RefControl.Parent, RequestedParentClass, FoundParentControl);
end;

function HasParentControlByClass(RefControl: TControl;
  RequestedParentClass: TWinControlClass): Boolean;
var
  Dummy: TWinControl;
begin
  Result := HasParentControlByClass(RefControl, RequestedParentClass, Dummy);
end;

// Findet die 1. Form anhand der Klasse RequestedFormClass, die der RefForm untergeordnet ist und
// liefert es im Ausgabeparameter FoundChildForm, wenn der R�ckgabewert True ist
function HasChildFormByClass(RefForm: TCustomForm; RequestedFormClass: TCustomFormClass;
  out FoundChildForm: TCustomForm): Boolean;
var
  cc: Integer;
begin
  Result := Assigned(RefForm);
  if not Result then
    Exit;

  for cc := 0 to RefForm.ComponentCount - 1 do
    if RefForm.Components[cc] is RequestedFormClass then
    begin
      FoundChildForm := TCustomForm(RefForm.Components[cc]);
      Exit;
    end;

  Result := False;
end;

type
  TCustomLabelAccess = class(TCustomLabel);

// Ermittelt das 1. Label, welches den selben Parent hat und als FocusControl f�r das im
// 1. Parameter �bergebenen Control fungiert.
function HasAssignedLabel(Control: TControl; out FoundLabel: TCustomLabel): Boolean;
var
  cc: Integer;
  TempControl: TControl;
  ParentFormWC: TWinControl;
  ParentForm: TCustomForm absolute ParentFormWC;
  TempComponent: TComponent;
begin
  Result := True;

  for cc := 0 to Control.Parent.ControlCount -1 do
  begin
    TempControl := Control.Parent.Controls[cc];
    if (TempControl is TCustomLabel) and
      (TCustomLabelAccess(TempControl).FocusControl = Control) then
    begin
      FoundLabel := TCustomLabel(TempControl);
      Exit;
    end;
  end;

  // If no label was found on the same parent control level, then we try to find them
  // from components in the containing form
  if HasParentControlByClass(Control, TCustomForm, ParentFormWC) then
  begin
    for cc := 0 to ParentForm.ComponentCount - 1 do
    begin
      TempComponent := ParentForm.Components[cc];
      if (TempComponent is TCustomLabel) and
        (TCustomLabelAccess(TempComponent).FocusControl = Control) then
      begin
        FoundLabel := TCustomLabelAccess(TempComponent);
        Exit;
      end;
    end;
  end;

  Result := False;
end;

// Behandelt eine Menge an Checkboxen (CheckboxGroup) als exklusiv-checkable (�hnlich RadioButton)
//
// Im Parameter Sender sollte die aktuell zu behandelnde Checkbox, also die die aktuell ein Event
// ausgel�st hat, �bergeben werden.
//
// Beispiel:
// <code>
// procedure TMyForm.CheckBoxClick(Sender: TObject);
// begin
//   HandleCheckboxGroup(Sender, [JaCheckBox, NeinCheckBox, VielleichtCheckBox]);
// end;
// </code>
procedure HandleCheckboxGroup(Sender: TObject; CheckboxGroup: array of TCheckBox);
var
  SenderCB: TCheckBox absolute Sender;
  cc: Integer;
begin
  if (Sender is TCheckBox) and SenderCB.Checked then
    for cc := 0 to Length(CheckboxGroup) - 1 do
      if CheckboxGroup[cc] <> SenderCB then
        CheckboxGroup[cc].Checked := False;
end;

// Leitet einen Klick auf ein Label an ein �ber TLabel.FocusControl verkn�pftes Control (aktuell
// nur CheckBoxen) weiter
procedure RouteLabelClick(Sender: TObject);
var
  SenderLabel: TLabel absolute Sender;
  FocusControl: TWinControl;

  procedure RouteClickToCheckBox(CheckBox: TCheckBox);
  begin
    if CheckBox.CanFocus then
      CheckBox.SetFocus;
    CheckBox.Checked := not CheckBox.Checked;
  end;

begin
  FocusControl := SenderLabel.FocusControl;

  if FocusControl is TCheckBox then
    RouteClickToCheckBox(TCheckBox(FocusControl));
end;

// Liefert bei allen Nachk�mmlingen von TScrollingWinControl (z.B. TForm, TScrollBox) die Scrollbar
// im Ausgabeparamter ScrollBar, wenn die Funktion True liefert. Es werden nur sichtbare Scrollbars
// geliefert.
function HasScrollableScrollbar(Control: TControl; Kind: TScrollBarKind;
  out Scrollbar: TControlScrollBar): Boolean;

  function AcceptedFirstLevelComponent(Control: TControl): Boolean;
  const
    ForbiddenArray: array [0..1] of TControlClass = (TCustomMemo, TCustomListControl);
  var
    cc: Integer;
    IsForbidden: Boolean;
  begin
    Result := Assigned(Control);
    if not Result then
      Exit;

    IsForbidden := False;
    for cc := 0 to Length(ForbiddenArray) - 1 do
      if Control is ForbiddenArray[cc] then
      begin
        IsForbidden := True;
        Break;
      end;

    Result := not IsForbidden;
  end;

  function ControlAccepted: Boolean;
  var
    SBControl: TScrollingWinControl absolute Control;
    SB: TControlScrollBar;
  begin
    Result := Control is TScrollingWinControl;
    if Result then
    begin
      SB := nil;
      case Kind of
        sbHorizontal:
          SB := SBControl.HorzScrollBar;
        sbVertical:
          SB := SBControl.VertScrollBar;
      end;

      Result := Assigned(SB) and SB.IsScrollBarVisible;
      if Result then
        Scrollbar := SB;
    end;
  end;

begin
  Result := AcceptedFirstLevelComponent(Control);
  if not Result then
    Exit;

  repeat
    if ControlAccepted then
      Exit
    else if Assigned(Control) then
      Control := Control.Parent;
  until not Assigned(Control);

  Result := False;
end;

function HasControlMouseWheelSupport(AControl: TComponent;
  AdditionalAccepts: array of TComponentClass): Boolean;

  function IsAcceptedByAdditionalAccepts: Boolean;
  var
    cc: Integer;
  begin
    Result := True;
    for cc := 0 to Length(AdditionalAccepts) - 1 do
      if AControl is AdditionalAccepts[cc] then
        Exit;
    Result := False;
  end;

var
  hwnd: THandle;
  Style: LongWord;
  SB: TControlScrollBar;
begin
  Result := False;
  if AControl is TWinControl then
  begin
    hwnd := TWinControl(AControl).Handle;
    Style := GetWindowLong(hWnd, GWL_STYLE);
    Result := ((Style and WS_HSCROLL) <> 0) or ((Style and WS_VSCROLL) <> 0);
    if Result then
      Exit;
  end;

  if AControl is TControl then
    Result := HasScrollableScrollbar(TControl(AControl), sbVertical, SB);

  if not Result then
    Result := IsAcceptedByAdditionalAccepts;
end;

{ TFormMouseWheelMediator }

constructor TFormMouseWheelMediator.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPrevOnMouseWheel := TForm(AOwner).OnMouseWheel;
  TForm(AOwner).OnMouseWheel := MouseWheelHandler;
end;

procedure TFormMouseWheelMediator.MouseWheelHandler(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  SB: TControlScrollbar;
  SBKind: TScrollBarKind;
begin
  if GetAsyncKeyState(VK_SHIFT) < 0 then
    SBKind := sbHorizontal
  else
    SBKind := sbVertical;

  if
    // Prio 1: Geh vom Control unter dem Cursor aus
    HasScrollableScrollbar(FindDragTarget(MousePos, True), SBKind, SB) or
    // Prio 2: Geh vom Control aus, welches aktuell den Fokus hat
    HasScrollableScrollbar(Screen.ActiveControl, SBKind, SB) then
  begin
    SB.Position := SB.Position - (Sign(WheelDelta) * SB.Increment);
    Handled := True;
  end;

  if not Handled and Assigned(FPrevOnMouseWheel) then
    FPrevOnMouseWheel(Sender, Shift, WheelDelta, MousePos, Handled);
end;

end.
