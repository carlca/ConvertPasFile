program ConvertPasFile;

{$mode objfpc}{$H+}

uses
  SysUtils,
  Classes,
  StrUtils;

const
  OLD_PREFIX = 'AsoundSeq';
  NEW_PREFIX = 'caAsoundSeq';

type
  TStringArray = array of string;

procedure Pass;
begin
end;

function CleanComment(const comment: string): string;
begin
  Result := StringReplace(comment, '//*', '//', [rfReplaceAll]);
end;

function ConvertComment(const line: string): string;
var
  commentStart, commentEnd: Integer;
  beforeComment, comment: string;
begin
  commentStart := Pos('(*', line);
  if commentStart = 0 then
  begin
    // Clean any existing //* comments
    if Pos('//*', line) > 0 then
      Result := CleanComment(line)
    else
      Result := line;
    Exit;
  end;

  commentEnd := Pos('*)', line);
  if commentEnd = 0 then
  begin
    Result := line;
    Exit;
  end;

  beforeComment := Copy(line, 1, commentStart - 1);
  comment := Copy(line, commentStart + 2, commentEnd - commentStart - 2);
  Result := beforeComment + '//' + comment;
end;

function CleanMethodEnd(const line: string): string;
var
  endPos: Integer;
begin
  endPos := Pos('end', line);
  if (endPos > 0) and (Pos('{', line) > endPos) then
    Result := 'end;'
  else
    Result := line;
end;

function StandardizeCase(const Value: string): string;
begin
  Result := StringReplace(Value, 'Name', 'name', [rfReplaceAll]);
  Result := StringReplace(Result, 'Type', 'type', [rfReplaceAll]);
  Result := StringReplace(Result, 'Value', 'value', [rfReplaceAll]);
end;

function FormatParameter(const param: string): string;
var
  parts: TStringArray;
  paramName, paramType: string;
begin
  parts := param.Split([':']);
  if Length(parts) = 2 then
  begin
    paramName := StandardizeCase(Trim(parts[0]));
    paramType := Trim(parts[1]);
    Result := paramName + ': ' + paramType;
  end
  else
    Result := param;
end;

function FormatFunctionSignature(const line: string): string;
var
  paramStart, paramEnd: Integer;
  beforeParams, params, afterParams: string;
  paramList: TStringArray;
  i: Integer;
  formattedParams: string;
begin
  paramStart := Pos('(', line);
  paramEnd := LastDelimiter(')', line);

  if (paramStart > 0) and (paramEnd > paramStart) then
  begin
    beforeParams := Copy(line, 1, paramStart);
    params := Copy(line, paramStart + 1, paramEnd - paramStart - 1);
    afterParams := Copy(line, paramEnd, Length(line));

    paramList := params.Split([';']);
    formattedParams := '';

    for i := 0 to Length(paramList) - 1 do
    begin
      if i > 0 then
        formattedParams := formattedParams + '; ';
      formattedParams := formattedParams + FormatParameter(Trim(paramList[i]));
    end;

    Result := beforeParams + formattedParams + afterParams;
  end
  else
    Result := line;
end;

procedure ConvertFile(const inputFileName, outputFileName: string);
var
  inputFile, outputFile: TStringList;
  i: Integer;
  line: string;
  inImplementation, inComment: Boolean;
  lastLineWasBlank, lastLineWasFunction: Boolean;

  function ShouldSkipComment(const commentLine: string): Boolean;
  var
    trimmedLine: string;
  begin
    trimmedLine := Trim(commentLine);
    Result := (trimmedLine = '//')  // Empty comment line
           or (StartsText('//**', trimmedLine)) // Asterisk separator line
           or (StartsText('//*', trimmedLine))  // Star comment
           or (Pos('//', trimmedLine) = 1) and (TrimRight(Copy(trimmedLine, 3, Length(trimmedLine))) = ''); // Just spaces after //
  end;

  function FormatCompilerDirective(const directiveLine: string): string;
  var
    startPos, endPos: Integer;
  begin
    Result := directiveLine;
    if (Pos('{$', directiveLine) > 0) then
    begin
      startPos := Pos('{$', directiveLine);
      endPos := Pos('}', directiveLine);

      // Special case for {$i
      if LowerCase(Copy(directiveLine, startPos, 3)) = '{$i' then
      begin
        Result := Copy(directiveLine, 1, startPos - 1) +
                  '{$I' +
                  Copy(directiveLine, startPos + 3, Length(directiveLine));
      end
      // All other directives
      else
      begin
        Result := Copy(directiveLine, 1, startPos - 1) +
                  UpperCase(Copy(directiveLine, startPos, endPos - startPos + 1)) +
                  Copy(directiveLine, endPos + 1, Length(directiveLine));
      end;
    end;
  end;

begin
  inputFile := TStringList.Create;
  outputFile := TStringList.Create;
  try
    inputFile.LoadFromFile(inputFileName);

    inImplementation := False;
    inComment := False;
    lastLineWasBlank := False;
    lastLineWasFunction := False;

    for i := 0 to inputFile.Count - 1 do
    begin
      line := inputFile[i];

      // Handle comments
      if (Pos('(*', line) > 0) and (Pos('*)', line) = 0) then
      begin
        inComment := True;
        line := StringReplace(line, '(*', '//', []);
      end
      else if inComment and (Pos('*)', line) > 0) then
      begin
        inComment := False;
        line := StringReplace(line, '*)', '', []);
        if Trim(line) <> '' then
          line := '//' + TrimLeft(line);
      end
      else if inComment then
      begin
        if Trim(line) <> '' then
          line := '//' + TrimLeft(line);
      end
      else
      begin
        line := ConvertComment(line);
      end;

      // Format compiler directives
      if Pos('{$', line) > 0 then
        line := FormatCompilerDirective(line);

      // Skip unwanted comment lines
      if ShouldSkipComment(Trim(line)) then
        Continue;

      // Skip blank lines after function signatures
      if lastLineWasFunction and (Trim(line) = '') then
        Continue;

      // Skip multiple blank lines
      if (Trim(line) = '') and lastLineWasBlank then
        Continue;

      // Convert unit name
      if StartsText('unit ', line) then
        line := StringReplace(line, OLD_PREFIX, NEW_PREFIX, [rfIgnoreCase]);

      // Track implementation section
      if line = 'implementation' then
        inImplementation := True;

      // Format procedure/function declarations
      if ((StartsText('function ', line) or StartsText('procedure ', line)) and
          (Pos(';', line) > 0)) then
      begin
        line := FormatFunctionSignature(line);
        if inImplementation and (not lastLineWasBlank) and (outputFile.Count > 0) then
          outputFile.Add('');
        lastLineWasFunction := True;
      end
      else
        lastLineWasFunction := False;

      // Clean up method endings
      if StartsText('end ', line) then
        line := CleanMethodEnd(line);

      // Standardize parameter names
      line := StandardizeCase(line);

      outputFile.Add(line);

      lastLineWasBlank := (Trim(line) = '');
    end;

    outputFile.SaveToFile(outputFileName);
  finally
    inputFile.Free;
    outputFile.Free;
  end;
end;

procedure ApplyPostAIFixes(outputFileName: string);
var
  i: integer;
  outputFile: TStringList;
  fixedFile: TStringList;
  line: string;

  function ApplyCompilerDirectiveFix(line: string): string;
  begin
    Result := line;
    if (Pos('{$', line) > 0) then
    begin
      if line[Length(line)] = '}' then
      begin
        SetLength(line, Length(line) - 1);
        line := Trim(line) + '}';
        Result := line;
      end;
    end;
  end;

  function IsBlankLineNeeded(Index: integer; line: string): boolean;
  var
    NextIndex: integer = -1;
    PrevIndex: integer = -1;
    NextLine: string;
    PrevLine: string;
  begin
    Result := true;
    if Index < outputFile.Count then
      NextIndex := Succ(Index);
    if Index > 0 then
      PrevIndex := Pred(Index);
    if (NextIndex >= 0) and (PrevIndex >= 0) then
    begin
      NextLine := outputFile[NextIndex];
      PrevLine := outputFile[PrevIndex];
      // for blank between comment and procedure/function/constructor
      if Pos('//', Trim(PrevLine)) > 0 then
      begin
        if (Pos('function', Trim(NextLine)) > 0)
        or (Pos('procedure', Trim(NextLine)) > 0)
        or (Pos('constructor', Trim(NextLine)) > 0) then
        begin
          Result := false;
          Exit;
        end;
      end;
      // for blank between constructor and begin
      if Pos('constructor', Trim(PrevLine)) > 0 then
      begin
        if Pos('begin', Trim(NextLine)) > 0 then
        begin
          Result := false;
          Exit;
        end;
      end;
    end;
  end;

begin
  outputFile := TStringList.Create;
  fixedFile := TStringList.Create;
  try
    outputFile.LoadFromFile(outputFileName);
    for i := 0 to outputFile.Count - 1 do
    begin
      line := outputFile[i];

      line := ApplyCompilerDirectiveFix(line);

      if (Trim(line) <> '') then
        fixedFile.Add(line)
      else
        if (Trim(line) = '') and IsBlankLineNeeded(i, line) then
        begin
          fixedFile.Add(line)
        end;
    end;
    fixedFile.SaveToFile(outputFileName);
  finally
    outputFile.Free;
    fixedFile.Free;
  end;
end;

// Run with: ../ConvertPasFile/ConvertPasFile ./asoundseq_dynamic.pas ./caasoundseq_dynamic.pas

var
  inputFileName, outputFileName: string;
begin
  if ParamCount < 2 then
  begin
    inputFileName := '/users/carlcaulkett/Code/fpc/asound/asoundseq_dynamic.pas';
    outputFileName := '/users/carlcaulkett/Code/fpc/asound/caasoundseq_dynamic.pas';
    ConvertFile(inputFileName, outputFileName);
    ApplyPostAIFixes(outputFileName);
  end
  else
  begin
    try
      inputFileName := ParamStr(1);
      outputFileName := ParamStr(2);
      ConvertFile(inputFileName, outputFileName);
      ApplyPostAIFixes(outputFileName);
      WriteLn('Conversion completed successfully.');
    except
      on E: Exception do
      begin
        WriteLn('Error: ', E.Message);
        ExitCode := 1;
      end;
    end;
  end;
end.
