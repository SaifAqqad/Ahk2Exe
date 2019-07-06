
PreprocessScript(ByRef ScriptText, AhkScript, ExtraFiles, FileList := "", FirstScriptDir := "", Options := "", iOption := 0)
{
	SplitPath, AhkScript, ScriptName, ScriptDir
	if !IsObject(FileList)
	{
		FileList := [AhkScript]
		ScriptText := "; <COMPILER: v" A_AhkVersion ">`n"
		FirstScriptDir := ScriptDir
		IsFirstScript := true
		Options := { comm: ";", esc: "``", directives: [] }
		
		OldWorkingDir := A_WorkingDir
		SetWorkingDir, %ScriptDir%
		
		DerefIncludeVars.A_ScriptFullPath := AhkScript
		DerefIncludeVars.A_ScriptName := ScriptName
		DerefIncludeVars.A_ScriptDir := ScriptDir
	}
	oldLineFile := DerefIncludeVars.A_LineFile
	DerefIncludeVars.A_LineFile := AhkScript
	
	if SubStr(DerefIncludeVars.A_AhkVersion,1,1)=2 ; Handle v2 default folder
	{
		OldWorkingDirv2 := A_WorkingDir
		SetWorkingDir %ScriptDir%
	}
	
	IfNotExist, %AhkScript%
		if !iOption
			Util_Error((IsFirstScript ? "Script" : "#include") " file """ AhkScript """ cannot be opened.", 0x32)
		else return
	
	cmtBlock := false, contSection := false, ignoreSection := false
	Loop, Read, %AhkScript%
	{
		tline := Trim(A_LoopReadLine)
		if !cmtBlock
		{
			if ignoreSection
			{
				if StrStartsWith(tline, Options.comm "@Ahk2Exe-IgnoreEnd")
					ignoreSection := false
				continue
			}
			if !contSection
			{
				if StrStartsWith(tline, Options.comm)
				{
					StringTrimLeft, tline, tline, % StrLen(Options.comm)
					if !StrStartsWith(tline, "@Ahk2Exe-")
						continue
					StringTrimLeft, tline, tline, 9
					if StrStartsWith(tline, "IgnoreBegin")
						ignoreSection := true
					else if tline !=
						Options.directives.Insert(RegExReplace(tline
						, "\s+" RegExEscape(Options.comm) ".*$")) ;Strip any actual comments
					continue
				}
				else if tline =
					continue
				else if StrStartsWith(tline, "/*")
				{
					if StrStartsWith(tline, "/*@Ahk2Exe-Keep")
						continue
					cmtBlock := true
					continue
				}
				else if StrStartsWith(tline, "*/")
					continue ; Will only happen in a 'Keep' section
			}
			if StrStartsWith(tline, "(") && !IsFakeCSOpening(tline)
				contSection := true
			else if StrStartsWith(tline, ")")
				contSection := false
			
			tline := RegExReplace(tline, "\s+" RegExEscape(Options.comm) ".*$", "")
			if !contSection 
			&& RegExMatch(tline, "i)^#Include(Again)?[ \t]*[, \t]\s*(.*)$", o)
			{
				IsIncludeAgain := (o1 = "Again")
				IgnoreErrors := false
				IncludeFile := o2
				if RegExMatch(IncludeFile, "\*[iI]\s+?(.*)", o)
					IgnoreErrors := true, IncludeFile := Trim(o1)
				
				if RegExMatch(IncludeFile, "^<(.+)>$", o)
				{
					if IncFile2 := FindLibraryFile(o1, FirstScriptDir)
					{
						IncludeFile := IncFile2
						goto _skip_findfile
					}
				}
				
				IncludeFile := DerefIncludePath(IncludeFile, DerefIncludeVars)
				
				if InStr(FileExist(IncludeFile), "D")
				{
					SetWorkingDir, %IncludeFile%
					continue
				}
				
				_skip_findfile:
				
				IncludeFile := Util_GetFullPath(IncludeFile)
				
				AlreadyIncluded := false
				for k,v in FileList
				if (v = IncludeFile)
				{
					AlreadyIncluded := true
					break
				}
				if(IsIncludeAgain || !AlreadyIncluded)
				{
					if !AlreadyIncluded
						FileList.Insert(IncludeFile)
					PreprocessScript(ScriptText, IncludeFile, ExtraFiles, FileList, FirstScriptDir, Options, IgnoreErrors)
				}
			}else if !contSection && tline ~= "i)^FileInstall[, \t]"
			{
				if tline ~= "^\w+\s+(:=|\+=|-=|\*=|/=|//=|\.=|\|=|&=|\^=|>>=|<<=)"
					continue ; This is an assignment!
				
				; workaround for `, detection
					EscapeChar := Options.esc
					EscapeCharChar := EscapeChar EscapeChar
					EscapeComma := EscapeChar ","
					EscapeTmp := chr(2)
					EscapeTmpD := chr(3)
					StringReplace, tline, tline, %EscapeCharChar%, %EscapeTmpD%, All
					StringReplace, tline, tline, %EscapeComma%, %EscapeTmp%, All
				
				if !RegExMatch(tline, "i)^FileInstall[ \t]*[, \t][ \t]*([^,]+?)[ \t]*(,|$)", o) || o1 ~= "[^``]%"
					Util_Error("Error: Invalid ""FileInstall"" syntax found. Note that the first parameter must not be specified using a continuation section.", 0x12)
				_ := Options.esc
				StringReplace, o1, o1, %_%`%, `%, All
				StringReplace, o1, o1, %_%`,, `,, All
				StringReplace, o1, o1, %_%%_%,, %_%,, All
				
				; workaround for `, detection [END]
					StringReplace, o1, o1, %EscapeTmp%, `,, All
					StringReplace, o1, o1, %EscapeTmpD%, %EscapeChar%, All
					StringReplace, tline, tline, %EscapeTmp%, %EscapeComma%, All
					StringReplace, tline, tline, %EscapeTmpD%, %EscapeCharChar%, All
				
				ExtraFiles.Insert(o1)
				ScriptText .= tline "`n"
			}else if !contSection && RegExMatch(tline, "i)^#CommentFlag\s+(.+)$", o)
				Options.comm := o1, ScriptText .= tline "`n"
			else if !contSection && RegExMatch(tline, "i)^#EscapeChar\s+(.+)$", o)
				Options.esc := o1, ScriptText .= tline "`n"
			else if !contSection && RegExMatch(tline, "i)^#DerefChar\s+(.+)$", o)
				Util_Error("Error: #DerefChar is not supported.", 0x21)
			else if !contSection && RegExMatch(tline, "i)^#Delimiter\s+(.+)$", o)
				Util_Error("Error: #Delimiter is not supported.", 0x22)
			else
				ScriptText .= (contSection ? A_LoopReadLine : tline) "`n"
		}else if StrStartsWith(tline, "*/")
			cmtBlock := false
	}
	
	Loop, % !!IsFirstScript ; equivalent to "if IsFirstScript" except you can break from the block
	{
		AhkPath := A_IsCompiled ? A_ScriptDir "\..\AutoHotkey.exe" : A_AhkPath
		AhkPath := FileExist(AhkPath) ? AhkPath : A_AhkPath
		IfNotExist, %AhkPath%
		{	
			Util_Error("Warning: AutoHotkey.exe could not be located!`n`n"
			. "Auto-includes from Function Libraries will not be processed.",0)
			break ; Don't bother with auto-includes because the file does not exist
		}
		Util_Status("Auto-including any functions called from a library...")
		ilibfile := A_Temp "\_ilib.ahk", preprocfile := ScriptDir "\_ahk2exe.tmp~"
		IfExist, %ilibfile%, FileDelete, %ilibfile%
		IfExist, %preprocfile%, FileDelete, %preprocfile%
		AhkType := AHKType(AhkPath)
		if !AhkType
			Util_Error("Error: The AutoHotkey build used for auto-inclusion of library functions is not recognized.", 0x25, AhkPath)
		if (AhkType.Era = "Legacy")
			Util_Error("Error: Legacy AutoHotkey versions (prior to v1.1) are not allowed as the build used for auto-inclusion of library functions.", 0x26, AhkPath)
		tmpErrorLog := Util_TempFile()
		FileAppend, % ScriptText, % preprocfile, UTF-8
		RunWait, "%AhkPath%" /iLib "%ilibfile%" /ErrorStdOut "%preprocfile%" 2>"%tmpErrorLog%", %FirstScriptDir%, UseErrorLevel Hide
		if (ErrorLevel = 2)
		{
			FileRead,tmpErrorData,%tmpErrorLog%
			Util_Error("Error: The script contains syntax errors.", 0x11,tmpErrorData)
		}
		FileDelete,%tmpErrorLog%
		FileDelete,%preprocfile%
		IfExist, %ilibfile%
		{
			PreprocessScript(ScriptText, ilibfile, ExtraFiles, FileList, FirstScriptDir, Options)
			FileDelete, %ilibfile%
		}
		StringTrimRight, ScriptText, ScriptText, 1 ; remove trailing newline
	}
	
	DerefIncludeVars.A_LineFile := oldLineFile
	if OldWorkingDir
		SetWorkingDir, %OldWorkingDir%
	
	if SubStr(DerefIncludeVars.A_AhkVersion,1,1)=2 ; Handle v2 default folder
		SetWorkingDir %OldWorkingDirv2%

	if IsFirstScript
		return Options.directives
}

IsFakeCSOpening(tline)
{
	Loop, Parse, tline, %A_Space%%A_Tab%
		if !StrStartsWith(A_LoopField, "Join") && InStr(A_LoopField, ")")
			return true
	return false
}

FindLibraryFile(name, ScriptDir)
{
	libs := [ScriptDir "\Lib", A_MyDocuments "\AutoHotkey\Lib", A_ScriptDir "\..\Lib"]
	p := InStr(name, "_")
	if p
		name_lib := SubStr(name, 1, p-1)
	
	for each,lib in libs
	{
		file := lib "\" name ".ahk"
		IfExist, %file%
			return file
		
		if !p
			continue
		
		file := lib "\" name_lib ".ahk"
		IfExist, %file%
			return file
	}
}

StrStartsWith(ByRef v, ByRef w)
{
	return SubStr(v, 1, StrLen(w)) = w
}

RegExEscape(t)
{
	static _ := "\.*?+[{|()^$"
	Loop, Parse, _
		StringReplace, t, t, %A_LoopField%, \%A_LoopField%, All
	return t
}

Util_TempFile(d:="")
{
	if ( !StrLen(d) || !FileExist(d) )
		d:=A_Temp
	Loop
		tempName := d "\~temp" A_TickCount ".tmp"
	until !FileExist(tempName)
	return tempName
}

class DerefIncludeVars
{
	static A_IsCompiled := true
}

DerefIncludePath(path, vars, dosubset := 0)
{
	static SharedVars := {A_AhkPath:1, A_AppData:1, A_AppDataCommon:1, A_ComputerName:1, A_ComSpec:1, A_Desktop:1, A_DesktopCommon:1, A_MyDocuments:1, A_ProgramFiles:1, A_Programs:1, A_ProgramsCommon:1, A_Space:1, A_StartMenu:1, A_StartMenuCommon:1, A_Startup:1, A_StartupCommon:1, A_Tab:1, A_Temp:1, A_UserName:1, A_WinDir:1}
	p := StrSplit(path, "%")
	path := p[1]
	n := 2
	while n < p.Length()
	{
		vn := p[n]
		subs := StrReplace(StrReplace(vn, "````", "chr(2)"), "``~", "chr(3)")
		subs := dosubset ? StrSplit(subs, "~",, 3) : [vn]
		subs.2 := StrReplace(StrReplace(subs.2, "chr(2)", "``"), "chr(3)", "~")
		subs.3 := StrReplace(StrReplace(subs.3, "chr(2)", "``"), "chr(3)", "~")
		if ObjHasKey(vars, subs.1)
			path .= subset(vars[subs.1], subs) . p[++n]
		else if SharedVars[subs.1]
			vn := subs.1, path .= subset(%vn%, subs) . p[++n]
		else path .= "%" vn
		++n
	}
	if (n = p.Length())
		path .= "%" p[n]
	return path
}
; ^^ vv Can subset dereferenced value (only when used in Compiler Directives).
;
; Include at end of builtin variable name before end %, p2 [p3] all separated
;   by tilde "~". if p2 is [-]integer, p2 and p3 are used as p2, p3 of 'SubStr'
;   (v1), otherwise p2 and p3 are used as p2, p3 of 'RegExReplace'.
;
; E.g. %A_ScriptName~1~-4% trims 3 character extension plus full-stop.
; E.g. %A_ScriptName~\.[^\.]+$~.exe% replaces variable sized ext'n with .exe.
;
; To include tilde as data in p2, p3, preceded with back-tick, i.e. `~
; To include back-tick character as data in p2, p3, double it, i.e. ``

subset(val, subs)      ; Returns subset of val using subs.2 & subs.3
{                      ; if no subs.2 or empty, return val unchanged
	if (subs.2 = "")     ; If subs.2 [-]integer, use SubStr, else use RegExReplace
		return val
	else if (subs.2~="^-?\d+$")
		if (subs.3 = "")
			return        SubStr(val, subs.2)
		else return     SubStr(val, subs.2, subs.3)
	else return RegExReplace(val, subs.2, subs.3)
}
