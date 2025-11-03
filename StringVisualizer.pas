unit StringVisualizer;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ComCtrls, ToolsAPI, StdCtrls, ExtCtrls, Vcl.Mask;

type
  TAvailableState = (asAvailable, asProcRunning, asOutOfScope);

  TStringViewerFrame = class(TFrame, IOTADebuggerVisualizerExternalViewerUpdater, IOTAThreadNotifier)
    Panel2: TPanel;
    Button1: TButton;
    Button2: TButton;
    FSD: TFileSaveDialog;
    StatusBar1: TStatusBar;
    Memo: TMemo;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
  private
    FOwningForm: TCustomForm;
    FClosedProc: TOTAVisualizerClosedProcedure;
    FExpression: string;
    FNotifierIndex: Integer;
    FCompleted: Boolean;
    FDeferredResult: string;
    FDeferredError: Boolean;
    FString: string;
    FAvailableState: TAvailableState;
    function Evaluate(Expression: string): string;
  protected
    procedure SetParent(AParent: TWinControl); override;
  public
    procedure CloseVisualizer;
    procedure MarkUnavailable(Reason: TOTAVisualizerUnavailableReason);
    procedure RefreshVisualizer(const Expression, TypeName, EvalResult: string);
    procedure SetClosedCallback(ClosedProc: TOTAVisualizerClosedProcedure);
    procedure SetForm(AForm: TCustomForm);
    procedure DisplayString(const Expression, TypeName, EvalResult: string);

    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    procedure ThreadNotify(Reason: TOTANotifyReason);
    procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean; ResultAddress, ResultSize: LongWord; ReturnCode: Integer);
    procedure ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
  end;

procedure Register;

implementation

uses
  DesignIntf, Actnlist, ImgList, Menus, IniFiles, Vcl.Clipbrd, System.Math;

{$R *.dfm}

resourcestring
  sStringVisualizerName = 'String Visualizer for Delphi';
  sStringVisualizerDescription = 'Displays a String';
  sMenuText = 'Show String';
  sFormCaption = 'String Visualizer for %s';
  sProcessNotAccessible = 'process not accessible';
  sOutOfScope = 'out of scope';

type

  IFrameFormHelper = interface
    ['{1A770356-D01F-480E-9706-3A75F8AC5CFD}']
    function GetForm: TCustomForm;
    function GetFrame: TCustomFrame;
    procedure SetForm(Form: TCustomForm);
    procedure SetFrame(Form: TCustomFrame);
  end;

  TStringVisualizerForm = class(TInterfacedObject, INTACustomDockableForm, IFrameFormHelper)
  private
    FMyFrame: TStringViewerFrame;
    FMyForm: TCustomForm;
    FExpression: string;
  public
    constructor Create(const Expression: string);
    { INTACustomDockableForm }
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetIdentifier: string;
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    function GetToolbarActionList: TCustomActionList;
    function GetToolbarImageList: TCustomImageList;
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    procedure SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
    { IFrameFormHelper }
    function GetForm: TCustomForm;
    function GetFrame: TCustomFrame;
    procedure SetForm(Form: TCustomForm);
    procedure SetFrame(Frame: TCustomFrame);
  end;

  TDebuggerStringVisualizer = class(TInterfacedObject, IOTADebuggerVisualizer,
    IOTADebuggerVisualizerExternalViewer)
  public
    function GetSupportedTypeCount: Integer;
    procedure GetSupportedType(Index: Integer; var TypeName: string;
      var AllDescendants: Boolean);
    function GetVisualizerIdentifier: string;
    function GetVisualizerName: string;
    function GetVisualizerDescription: string;
    function GetMenuText: string;
    function Show(const Expression, TypeName, EvalResult: string; Suggestedleft, SuggestedTop: Integer): IOTADebuggerVisualizerExternalViewerUpdater;
  end;

{ TDebuggerDateTimeVisualizer }

function TDebuggerStringVisualizer.GetMenuText: string;
begin
  Result := sMenuText;
end;

procedure TDebuggerStringVisualizer.GetSupportedType(Index: Integer;
  var TypeName: string; var AllDescendants: Boolean);
begin
  TypeName := 'string';
  AllDescendants := False;
end;

function TDebuggerStringVisualizer.GetSupportedTypeCount: Integer;
begin
  Result := 1;
end;

function TDebuggerStringVisualizer.GetVisualizerDescription: string;
begin
  Result := sStringVisualizerDescription;
end;

function TDebuggerStringVisualizer.GetVisualizerIdentifier: string;
begin
  Result := ClassName;
end;

function TDebuggerStringVisualizer.GetVisualizerName: string;
begin
  Result := sStringVisualizerName;
end;

function TDebuggerStringVisualizer.Show(const Expression, TypeName, EvalResult: string; SuggestedLeft, SuggestedTop: Integer): IOTADebuggerVisualizerExternalViewerUpdater;
var
  AForm: TCustomForm;
  AFrame: TStringViewerFrame;
  VisDockForm: INTACustomDockableForm;
begin
  VisDockForm := TStringVisualizerForm.Create(Expression) as INTACustomDockableForm;
  AForm := (BorlandIDEServices as INTAServices).CreateDockableForm(VisDockForm);
  AForm.Left := SuggestedLeft;
  AForm.Top := SuggestedTop;
  (VisDockForm as IFrameFormHelper).SetForm(AForm);
  AFrame := (VisDockForm as IFrameFormHelper).GetFrame as TStringViewerFrame;
  Result := AFrame as IOTADebuggerVisualizerExternalViewerUpdater;
  AFrame.DisplayString(Expression, TypeName, EvalResult);
  TForm(AForm).FormStyle:=fsStayOnTop;
end;


Procedure StrToFile(FileName: String; Str: String; AppendFile: boolean = True); overload;
var
  f  : TextFile;
  FN : string;
begin
  if FileName='' then Exit;

  FN:=String(FileName);
  AssignFile(f,FN);
  if FileExists(FN) and AppendFile then begin
    Append(f);
  end else begin
    ReWrite(f);
  end;
  Write(f,Str);
  CloseFile(f);
end;


function DecodeText(const Text: string; Len: integer = -1): string;
var
  i,n      : integer;
  b        : boolean;
  QStart   : integer;
  CharMode : integer;
  CharText : string;
begin
  Result:=Text;
  n:=0;
  b:=False;
  CharMode:=0;
  CharText:='';
  if Len=-1 then Len:=Length(Text);

  QStart:=0;
  for i:=1 to Length(Text) do begin
    if (CharMode>0) and ((CharInSet(Text[i],['''','#']) and not b) or (i=Length(Text))) then begin
      CharMode:=0;
      if CharText<>'' then begin
        if i=Length(Text) then begin
          CharText:=CharText+Text[i];
          inc(n);
          Result[n]:=Char(StrToInt(CharText));
          Break;
        end else begin
          inc(n);
          Result[n]:=Char(StrToInt(CharText));
          CharText:='';
        end;
      end;
    end;

    if (Text[i]='''') then begin
      if (i>1) and (i>QStart) and (Text[i-1]='''') then begin
        inc(n);
        Result[n]:=Text[i];
      end;
      b:=not b;
      if b then QStart:=i+1;
      Continue;
    end;

    if b then begin
      inc(n);
      Result[n]:=Text[i];
    end else begin
      if (CharMode>0) then begin
        CharText:=CharText+Text[i];
      end;
      if (CharMode=1) and (Text[i]='$') then begin
        CharMode:=2;
      end;
      if Text[i]='#' then begin
        CharMode:=1;
        CharText:='';
      end;
    end;

  end;
  SetLength(Result,Min(n,Len));
end;

{ TStringViewerFrame }

procedure TStringViewerFrame.DisplayString(const Expression, TypeName, EvalResult: string);
var
  P,Size : integer;
begin
  FAvailableState:=asAvailable;
  FExpression:=Expression;

  if Length(EvalResult)<1024 then begin
    FString:=DecodeText(EvalResult);
  end else begin
    FString:='';

    P:=1;
    Size:=StrToIntDef(Evaluate('length('+Expression+')'),0);
    while p<Size do begin
      var Len:=Min(Size-P+1,4000);
      var s:=Evaluate('copy('+Expression+','+p.ToString+','+(Len+4).ToString+')');
//      StrToFile('d:\out1-'+P.ToString+'.txt',s,false);
      try
        s:=DecodeText(s,Len);
      except
        on E: Exception do begin
          raise Exception.Create('Convert Error at '+P.ToString+': '+E.Message);
        end;
      end;
//      StrToFile('d:\out1-'+P.ToString+'b.txt',s,false);
      FString:=FString+s;
      inc(P,Len);
    end;
//    StrToFile('d:\out.txt',FString,false);
  end;
  Memo.Lines.Text:=FString;
  Update;
  StatusBar1.Panels[0].Text:='String length: '+Length(FString).ToString+', Lines Count: '+Memo.Lines.Count.ToString;
end;

procedure TStringViewerFrame.AfterSave;
begin

end;

procedure TStringViewerFrame.BeforeSave;
begin

end;

procedure TStringViewerFrame.CloseVisualizer;
begin
  if FOwningForm <> nil then
    FOwningForm.Close;
end;

procedure TStringViewerFrame.Destroyed;
begin

end;


function TStringViewerFrame.Evaluate(Expression: string): string;
var
  CurProcess: IOTAProcess;
  CurThread: IOTAThread;
  ResultStr: array[0..1024*1024] of Char;
  CanModify: Boolean;
  ResultAddr, ResultSize, ResultVal: LongWord;
  EvalRes: TOTAEvaluateResult;
  DebugSvcs: IOTADebuggerServices;
begin
  begin
    Result := '';
    if Supports(BorlandIDEServices, IOTADebuggerServices, DebugSvcs) then
      CurProcess := DebugSvcs.CurrentProcess;
    if CurProcess <> nil then
    begin
      CurThread := CurProcess.CurrentThread;
      if CurThread <> nil then
      begin
        EvalRes := CurThread.Evaluate(Expression, @ResultStr, Length(ResultStr), CanModify, eseAll, '', ResultAddr, ResultSize, ResultVal, '', 0);
        case EvalRes of
          erOK: Result := ResultStr;
          erDeferred:
            begin
              FCompleted := False;
              FDeferredResult := '';
              FDeferredError := False;
              FNotifierIndex := CurThread.AddNotifier(Self);
              while not FCompleted do
                DebugSvcs.ProcessDebugEvents;
              CurThread.RemoveNotifier(FNotifierIndex);
              FNotifierIndex := -1;
              if not FDeferredError then
              begin
                if FDeferredResult <> '' then
                  Result := FDeferredResult
                else
                  Result := ResultStr;
              end;
            end;
          erBusy:
            begin
              DebugSvcs.ProcessDebugEvents;
              Result := Evaluate(Expression);
            end;
        end;
      end;
    end;
  end;
end;

procedure TStringViewerFrame.EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean; ResultAddress, ResultSize: LongWord; ReturnCode: Integer);
begin
  FCompleted := True;
  FDeferredResult := ResultStr;
  FDeferredError := ReturnCode <> 0;
end;

procedure TStringViewerFrame.MarkUnavailable(
  Reason: TOTAVisualizerUnavailableReason);
begin
  if Reason = ovurProcessRunning then
  begin
    FAvailableState := asProcRunning;
  end else if Reason = ovurOutOfScope then
    FAvailableState := asOutOfScope;

end;

procedure TStringViewerFrame.Modified;
begin

end;

procedure TStringViewerFrame.ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
begin

end;

procedure TStringViewerFrame.RefreshVisualizer(const Expression, TypeName, EvalResult: string);
begin
  FAvailableState := asAvailable;
  DisplayString(Expression, TypeName, EvalResult);
end;

procedure TStringViewerFrame.SetClosedCallback(
  ClosedProc: TOTAVisualizerClosedProcedure);
begin
  FClosedProc := ClosedProc;
end;

procedure TStringViewerFrame.SetForm(AForm: TCustomForm);
begin
  FOwningForm := AForm;
end;

procedure TStringViewerFrame.SetParent(AParent: TWinControl);
begin
  if AParent = nil then
  begin
    FString:='';
    if Assigned(FClosedProc) then
      FClosedProc;
  end;
  inherited;
end;

procedure TStringViewerFrame.ThreadNotify(Reason: TOTANotifyReason);
begin

end;

{ TStringVisualizerForm }

constructor TStringVisualizerForm.Create(const Expression: string);
begin
  inherited Create;
  FExpression := Expression;
end;

procedure TStringVisualizerForm.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
  // no toolbar
end;

procedure TStringVisualizerForm.CustomizeToolBar(ToolBar: TToolBar);
begin
 // no toolbar
end;

function TStringVisualizerForm.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure TStringVisualizerForm.FrameCreated(AFrame: TCustomFrame);
begin
  FMyFrame :=  TStringViewerFrame(AFrame);
end;

function TStringVisualizerForm.GetCaption: string;
begin
  Result := Format(sFormCaption, [FExpression]);
end;

function TStringVisualizerForm.GetEditState: TEditState;
begin
  Result := [];
end;

function TStringVisualizerForm.GetForm: TCustomForm;
begin
  Result := FMyForm;
end;

function TStringVisualizerForm.GetFrame: TCustomFrame;
begin
  Result := FMyFrame;
end;

function TStringVisualizerForm.GetFrameClass: TCustomFrameClass;
begin
  Result := TStringViewerFrame;
end;

function TStringVisualizerForm.GetIdentifier: string;
begin
  Result := 'StringDebugVisualizer';
end;

function TStringVisualizerForm.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TStringVisualizerForm.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

function TStringVisualizerForm.GetToolbarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TStringVisualizerForm.GetToolbarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TStringVisualizerForm.LoadWindowState(Desktop: TCustomIniFile;
  const Section: string);
begin
  //no desktop saving
end;

procedure TStringVisualizerForm.SaveWindowState(Desktop: TCustomIniFile;
  const Section: string; IsProject: Boolean);
begin
  //no desktop saving
end;

procedure TStringVisualizerForm.SetForm(Form: TCustomForm);
begin
  FMyForm := Form;
  if Assigned(FMyFrame) then
    FMyFrame.SetForm(FMyForm);
end;

procedure TStringVisualizerForm.SetFrame(Frame: TCustomFrame);
begin
   FMyFrame := TStringViewerFrame(Frame);
end;

var
  StringVis: IOTADebuggerVisualizer;

procedure Register;
begin
  StringVis := TDebuggerStringVisualizer.Create;
  (BorlandIDEServices as IOTADebuggerServices).RegisterDebugVisualizer(StringVis);
end;

procedure RemoveVisualizer;
var
  DebuggerServices: IOTADebuggerServices;
begin
  if Supports(BorlandIDEServices, IOTADebuggerServices, DebuggerServices) then begin
    DebuggerServices.UnregisterDebugVisualizer(StringVis);
    StringVis := nil;
  end;
end;

procedure TStringViewerFrame.Button1Click(Sender: TObject);
begin
  Clipboard.AsText:=FString;
end;

procedure TStringViewerFrame.Button2Click(Sender: TObject);
begin
  if FSD.Execute then begin
    StrToFile(FSD.FileName,FString,False);
  end;
end;

initialization
finalization
  RemoveVisualizer;

end.

