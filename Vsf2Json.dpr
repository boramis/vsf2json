{ Convert a Delphi VCL/FireMonkey style file (.vsf) to JSON

  Usage:
    Vsf2Json stylefile [outputfile]

  stylefile is a Delphi .vsf style file.
  outputfile is a JSON conversion, excluding bitmaps.  Omit to write to stdout.

  Requires mORMot and mORMot\sqllite3 to compile.

  -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

  Copyright (c) 2021 Scooter Software, Inc.
  Distributed under the MIT software license, see the accompanying
  file LICENSE or http://www.opensource.org/licenses/mit-license.php. }

program Vsf2Json;

{$APPTYPE CONSOLE}
{$WARN IMPLICIT_STRING_CAST OFF}
{$WARN IMPLICIT_STRING_CAST_LOSS OFF}

{$R *.res}

uses
  Winapi.D2D1, Winapi.Messages, Winapi.Windows,
  System.Classes, System.IOUtils, System.StrUtils, System.SysUtils, System.Types, System.UITypes, System.ZLib,
  Vcl.Consts, Vcl.Controls, Vcl.Direct2D, Vcl.Forms, Vcl.Graphics, Vcl.GraphUtil, Vcl.ImgList, Vcl.Styles,
  mORMot, SynCommons;

{$I 'C:\Program Files (x86)\Embarcadero\Studio\21.0\source\vcl\StyleUtils.inc'}
{$I 'C:\Program Files (x86)\Embarcadero\Studio\21.0\source\vcl\StyleAPI.inc'}

const
  JSONWriteOptions = [woHumanReadable, woDontStoreDefault, woStoreClassName,
    woEnumSetsAsText];

{ TTextWriterHelper }

type
  TTextWriterHelper = class helper for TTextWriter
    procedure AddBoolProp(const APropName: ShortString; APropValue: Boolean);
    procedure AddObjectProp(const APropName: ShortString; APropValue: TObject);
    procedure AddStringProp(const APropName, APropValue: string);
    procedure StartNested(aOpenChar: AnsiChar = '{');
    procedure EndNested(aCloseChar: AnsiChar = '}');
  end;

procedure TTextWriterHelper.AddBoolProp(const APropName: ShortString;
  APropValue: Boolean);
begin
  AddCRAndIndent;
  AddPropName(APropName);
  Add(' ');
  Add(APropValue);
  Add(',');
end;

procedure TTextWriterHelper.AddObjectProp(const APropName: ShortString;
  APropValue: TObject);
begin
  AddCR;
  AddCRAndIndent;
  AddPropName(APropName);
  Add(' ');
  WriteObject(APropValue, JSONWriteOptions);
  Add(',');
end;

procedure TTextWriterHelper.AddStringProp(const APropName, APropValue: string);
begin
  AddCRAndIndent;
  AddPropName(ShortString(APropName));
  Add(' ');
  AddJSONString(RawUTF8(APropValue));
  Add(',');
end;

procedure TTextWriterHelper.StartNested(aOpenChar: AnsiChar);
begin
  Add(aOpenChar);
  HumanReadableLevel := HumanReadableLevel + 1;
end;

procedure TTextWriterHelper.EndNested(aCloseChar: AnsiChar);
begin
  CancelLastComma;
  HumanReadableLevel := HumanReadableLevel - 1;
  AddCRAndIndent;
  Add(aCloseChar);
end;

{ TSeStyleSerializerCallbacks }

type
  TSeStyleSerializerCallbacks = class
  private
    FPrevStyleObject: TObject;
    procedure WriteStyleSource(const aSerializer: TJSONSerializer;
      aValue: TObject; aOptions: TTextWriterWriteObjectOptions);
    procedure WriteColors(const aSerializer: TJSONSerializer;
      aValue: TObject; aOptions: TTextWriterWriteObjectOptions);
    procedure WriteSysColors(const aSerializer: TJSONSerializer;
      aValue: TObject; aOptions: TTextWriterWriteObjectOptions);
    procedure WriteFonts(const aSerializer: TJSONSerializer;
      aValue: TObject; aOptions: TTextWriterWriteObjectOptions);
    function WriteStyleObject(aSerializer: TTextWriter; aValue: TObject;
      aPropInfo: Pointer; aOptions: TTextWriterWriteObjectOptions): Boolean;
  public
    constructor Create;
  end;

constructor TSeStyleSerializerCallbacks.Create;
begin
  inherited;
  TJSONSerializer.RegisterCustomSerializer(TSeStyleSource, nil, WriteStyleSource);
  TJSONSerializer.RegisterCustomSerializer(TSeStyleColors, nil, WriteColors);
  TJSONSerializer.RegisterCustomSerializer(TSeStyleSysColors, nil, WriteSysColors);
  TJSONSerializer.RegisterCustomSerializer(TSeStyleFonts, nil, WriteFonts);
end;

procedure TSeStyleSerializerCallbacks.WriteStyleSource(
  const aSerializer: TJSONSerializer; aValue: TObject;
  aOptions: TTextWriterWriteObjectOptions);
begin
  var Style := aValue as TSeStyleSource;
  aSerializer.StartNested;
  { Write published properties;  RegisterCustomSerializer doesn't appear to have
    an automatic way to serialize published properties in addition to custom
    ones, and publishing Colors/SysColors/Fonts in a descendant class serializes
    them first }
  aSerializer.AddStringProp('Name', Style.Name);
  aSerializer.AddStringProp('Version', Style.Version);
  aSerializer.AddStringProp('Author', Style.Author);
  aSerializer.AddStringProp('AuthorEMail', Style.AuthorEMail);
  aSerializer.AddStringProp('AuthorURL', Style.AuthorURL);
  aSerializer.AddBoolProp('MobilePlatform', Style.MobilePlatform);
  aSerializer.AddBoolProp('RetinaDisplay', Style.RetinaDisplay);
  aSerializer.AddStringProp('Description', Style.Description);
  // Public properties
  aSerializer.AddObjectProp('Colors', Style.Colors);
  aSerializer.AddObjectProp('SysColors', Style.SysColors);
  aSerializer.AddObjectProp('Fonts', Style.Fonts);
  // Objects[]
  aSerializer.AddCR;
  aSerializer.AddCRAndIndent;
  aSerializer.AddPropName('Objects');
  aSerializer.Add(' ');
  aSerializer.StartNested('[');
  for var i := 0 to Style.Count - 1 do begin
    aSerializer.AddCRAndIndent;
    aSerializer.OnWriteObject := WriteStyleObject;
    try
      FPrevStyleObject := nil;
      aSerializer.WriteObject(Style.Objects[i], JSONWriteOptions);
    finally
      aSerializer.OnWriteObject := nil;
    end;
    aSerializer.Add(',');
  end;
  aSerializer.EndNested(']');
  // Done
  aSerializer.EndNested;
end;

procedure TSeStyleSerializerCallbacks.WriteColors(
  const aSerializer: TJSONSerializer; aValue: TObject;
  aOptions: TTextWriterWriteObjectOptions);
begin
  var Colors := aValue as TSeStyleColors;
  aSerializer.StartNested;
  for var StyleColor := Low(TSeStyleColor) to High(TSeStyleColor) do
    aSerializer.AddStringProp(StyleColorNames[StyleColor],
      ColorToString(Colors[StyleColor]));
  aSerializer.EndNested;
end;

procedure TSeStyleSerializerCallbacks.WriteFonts(
  const aSerializer: TJSONSerializer; aValue: TObject;
  aOptions: TTextWriterWriteObjectOptions);
begin
  var Fonts := aValue as TSeStyleFonts;
  aSerializer.StartNested;
  for var Font := Low(TSeStyleFont) to High(TSeStyleFont) do
    aSerializer.AddStringProp(StyleFontNames[Font], FontToString(Fonts[Font]));
  aSerializer.EndNested;
end;

procedure TSeStyleSerializerCallbacks.WriteSysColors(
  const aSerializer: TJSONSerializer; aValue: TObject;
  aOptions: TTextWriterWriteObjectOptions);
begin
  var Colors := aValue as TSeStyleSysColors;
  aSerializer.StartNested;
  for var SysColor := 0 to MaxSysColor - 1 do
    aSerializer.AddStringProp(SysColors[SysColor].Name,
      ColorToString(Colors[SysColor]));
  aSerializer.EndNested;
end;

function TSeStyleSerializerCallbacks.WriteStyleObject(aSerializer: TTextWriter;
  aValue: TObject; aPropInfo: Pointer; aOptions: TTextWriterWriteObjectOptions):
  Boolean;
begin
  { Force the "Name" property to be stored at the top of the object, immediately
    after ClassName, and manufacture an "Objects[]" property at the very bottom.

    The "Name" property is normally the last one encountered, since WriteObject
    goes up through parent properties after writing the child's ones, and isn't
    written since it has "stored False".  Forcibly add Name whenever we
    see a new aValue object, and add Objects[] once we see the actual "Name"
    propinfo. }
  Result := False;
  if not (aValue is TSeStyleObject) then
    Exit;
  var StyleObject := TSeStyleObject(aValue);
  if StyleObject <> FPrevStyleObject then begin
    aSerializer.AddStringProp('Name', StyleObject.Name);
    FPrevStyleObject := StyleObject;
  end;
  if PPropInfo(aPropInfo).Name = 'Name' then begin
    Result := True;
    aSerializer.AddCRAndIndent;
    aSerializer.AddPropName('Objects');
    aSerializer.Add(' ');
    if StyleObject.Count > 0 then begin
      aSerializer.StartNested('[');
      for var i := 0 to StyleObject.Count - 1 do begin
        aSerializer.AddCRAndIndent;
        aSerializer.WriteObject(StyleObject.Objects[i], JSONWriteOptions);
        aSerializer.Add(',');
      end;
      aSerializer.EndNested(']');
      FPrevStyleObject := StyleObject; // Reset after writing children
    end
    else
      aSerializer.Add('[', ']');
    aSerializer.Add(',');
  end;
end;

{ Program Main }

begin
  try
    if System.ParamCount < 1 then begin
      WriteLn('Convert a Delphi style file (.vsf) to JSON');
      WriteLn('');
      WriteLn('Vsf2Json stylefile [outputfile]');
      WriteLn('');
      WriteLn('stylefile is a Delphi VCL/FireMonkey .vsf style file.');
      WriteLn('outputfile is a JSON conversion, excluding bitmaps.  Omit to write to stdout.');
      ExitCode := 1;
      Exit;
    end;

    InitStyleAPI;
    var StyleSource := TSeStyleSource.Create(nil);
    try
      StyleSource.LoadFromFile(System.ParamStr(1));
      var SerializerCallbacks := TSeStyleSerializerCallbacks.Create;
      try
        var JsonOutput: string := string(ObjectToJSON(StyleSource,
          JSONWriteOptions));
        if System.ParamCount < 2 then
          WriteLn(JsonOutput)
        else
          TFile.WriteAllText(System.ParamStr(2), JsonOutput,
            TEncoding.UTF8);
      finally
        SerializerCallbacks.Free;
      end;
    finally
      StyleSource.Free;
    end;
  except
    on E: Exception do begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.

