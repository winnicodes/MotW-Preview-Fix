#NoTrayIcon
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=docs\icon.ico
#AutoIt3Wrapper_Res_Description=A lightweight, portable Windows utility that repairs broken PDF previews in Windows Explorer.
#AutoIt3Wrapper_Res_Fileversion=1.1.0.0
#AutoIt3Wrapper_Res_ProductName=MotW-Preview-Fix
#AutoIt3Wrapper_Res_ProductVersion=1.1.0.0
#AutoIt3Wrapper_Res_CompanyName=winnicodes
#AutoIt3Wrapper_Res_LegalCopyright=winnicodes
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
#pragma compile(x64, true) ; Explorer is 64-bit, so the context menu only loads a 64-bit EXE
#include <File.au3>
#include <GUIConstantsEx.au3>
#include <ComboConstants.au3>

; --- INIT ---
Global $sIniFile = @ScriptDir & "\config.ini"
Global $bSilent = False

; --- CLI PRE-CHECK: /silent may appear in any argument position ---
If $CmdLine[0] > 0 Then
    For $i = 1 To $CmdLine[0]
        If StringLower($CmdLine[$i]) = "/silent" Or StringLower($CmdLine[$i]) = "/s" Then
            $bSilent = True
        EndIf
    Next
EndIf

; --- MAIN: dispatch on the first argument ---
If $CmdLine[0] > 0 Then
    Local $sParam1 = StringLower($CmdLine[1])

    Switch $sParam1
        ; CASE 1: system-wide install, needs admin rights
        ; Usage: .exe /install_global "lang_de" /silent
        Case "/install_global"
            If $CmdLine[0] >= 2 Then
                ; Not elevated yet: restart this EXE as admin and let that copy do the work
                If Not IsAdmin() Then
                    ; Rebuild the arguments for the elevated run
                    Local $sArgs = '/install_global "' & $CmdLine[2] & '"'
                    If $bSilent Then $sArgs &= " /silent"

                    ; "runas" is what raises the UAC prompt
                    ShellExecute(@ScriptFullPath, $sArgs, "", "runas")
                    Exit
                EndIf

                ; Already admin: install directly
                _InstallGlobal($CmdLine[2])
            EndIf

        ; CASE 2: per-user install, no admin rights needed
        ; Usage: .exe /install_user "lang_de" /silent
        Case "/install_user"
             If $CmdLine[0] >= 2 Then
                _InstallUser($CmdLine[2])
            EndIf

        ; CASE 3: remove the context menu entry again
        ; Usage: .exe /uninstall /silent
        Case "/uninstall"
            _UninstallAll()

        ; CASE 4: /silent came first, so the real command is in argument 2
        Case "/silent", "/s"
             If $CmdLine[0] >= 2 Then
                If StringLower($CmdLine[2]) = "/install_global" Then
                    ; Same elevation handling as CASE 1
                    If Not IsAdmin() Then
                        Local $sArgs = '/install_global "' & $CmdLine[3] & '" /silent'
                        ShellExecute(@ScriptFullPath, $sArgs, "", "runas")
                        Exit
                    EndIf
                    _InstallGlobal($CmdLine[3])
                EndIf
                If StringLower($CmdLine[2]) = "/install_user" Then _InstallUser($CmdLine[3])
                If StringLower($CmdLine[2]) = "/uninstall" Then _UninstallAll()
             EndIf

        ; CASE 5: the argument is a file path, not a switch, so this is the context menu click
        Case Else
            If StringLeft($sParam1, 1) <> "/" Then
                _WorkerMode($CmdLine[1])
            EndIf
    EndSwitch
Else
    ; CASE 6: started with no arguments, show the installer GUI
    _InstallerGUI()
EndIf

; ==============================================================================
; WORKER MODE
; ==============================================================================
Func _WorkerMode($sFilePath)
    If Not FileExists($sFilePath) Then Return

    ; The Mark of the Web lives in an NTFS alternate data stream attached to the file.
    ; Clear the read-only flag first, a read-only file will not give up its stream.
    FileSetAttrib($sFilePath, "-R")
    FileDelete($sFilePath & ":Zone.Identifier")

    ; Fallback for cases where the direct stream delete is refused. Single quotes in the
    ; file name are doubled so they cannot break out of the PowerShell string.
    If FileExists($sFilePath & ":Zone.Identifier") Then
        Local $sEscapedPath = StringReplace($sFilePath, "'", "''")
        Local $sCmd = 'Unblock-File -LiteralPath ''' & $sEscapedPath & ''''
        RunWait("powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command " & $sCmd, "", @SW_HIDE)
    EndIf

    ; Explorer caches the rendered preview per file. Toggling the archive attribute is a
    ; cheap way to change the file metadata, which invalidates that cache entry.
    Local $iAttrib = FileGetAttrib($sFilePath)
    If StringInStr($iAttrib, "A") Then
        FileSetAttrib($sFilePath, "-A")
    Else
        FileSetAttrib($sFilePath, "+A")
    EndIf

    ; Tell the shell the item changed: SHCNE_UPDATEITEM (0x2000), path passed as a wide
    ; string (SHCNF_PATHW, 0x0005). Explorer then re-reads the file and redraws the pane.
    DllCall("shell32.dll", "none", "SHChangeNotify", "long", 0x00002000, "uint", 0x0005, "wstr", $sFilePath, "wstr", "")
EndFunc

; ==============================================================================
; INSTALLER MODE (GUI)
; ==============================================================================
Func _InstallerGUI()
    If Not FileExists($sIniFile) Then
        If Not $bSilent Then MsgBox(16, "Error", "config.ini not found!")
        Return
    EndIf

    Local $aSections = IniReadSectionNames($sIniFile)
    If @error Then Return

    Local $aLangMap[100][2]
    Local $iLangCount = 0
    Local $sComboList = ""

    For $i = 1 To $aSections[0]
        Local $sSec = $aSections[$i]
        If StringLeft($sSec, 5) = "lang_" Then
            Local $sName = IniRead($sIniFile, $sSec, "Name", $sSec)
            $iLangCount += 1
            $aLangMap[$iLangCount][0] = $sName
            $aLangMap[$iLangCount][1] = $sSec
            $sComboList &= $sName & "|"
        EndIf
    Next

    Local $hGui = GUICreate("MotW-Preview-Fix - Installer", 360, 220)

    GUICtrlCreateLabel("Select Language:", 20, 20, 300, 20)
    Local $hCombo = GUICtrlCreateCombo("", 20, 45, 320, 25, $CBS_DROPDOWNLIST)
    GUICtrlSetData($hCombo, $sComboList, $aLangMap[1][0])

    GUICtrlCreateGroup(" Installation ", 10, 80, 340, 70)
    Local $btnUser = GUICtrlCreateButton("Install Current User", 20, 100, 150, 40)
    Local $btnGlobal = GUICtrlCreateButton("Install All Users", 180, 100, 150, 40)
    GUICtrlSendMsg($btnGlobal, 0x160C, 0, 1)

    GUICtrlCreateGroup("", -99, -99, 1, 1)
    Local $btnUninstall = GUICtrlCreateButton("Uninstall (Remove)", 20, 165, 320, 35)

    GUISetState(@SW_SHOW)

    While 1
        Switch GUIGetMsg()
            Case $GUI_EVENT_CLOSE
                ExitLoop
            Case $btnUser
                Local $sSel = GUICtrlRead($hCombo)
                For $k = 1 To $iLangCount
                    If $aLangMap[$k][0] = $sSel Then
                        _InstallUser($aLangMap[$k][1])
                        ExitLoop
                    EndIf
                Next
            Case $btnGlobal
                Local $sSel = GUICtrlRead($hCombo)
                For $k = 1 To $iLangCount
                    If $aLangMap[$k][0] = $sSel Then
                        _TriggerGlobalInstallGUI($aLangMap[$k][1]) ; asks for elevation if needed
                        ExitLoop
                    EndIf
                Next
            Case $btnUninstall
                _UninstallAll()
        EndSwitch
    WEnd
    GUIDelete($hGui)
EndFunc

; ==============================================================================
; INSTALL AND UNINSTALL LOGIC
; ==============================================================================

; #FUNCTION# ====================================================================================================================
; Name ..........: _InstallUser
; Description ...: Installs the context menu entry for the current user only (HKCU).
; Syntax ........: _InstallUser($sSec)
; Parameters ....: $sSec                - A string value representing the language section in config.ini (e.g., "lang_en").
; Return values .: None
; Author ........: winnicodes
; Modified ......:
; Remarks .......: Does not require Administrator privileges. Writes to HKEY_CURRENT_USER\Software\Classes\SystemFileAssociations\.pdf.
;                  Reads display name and messages from the specified section in config.ini.
; Related .......: _InstallGlobal
; Link ..........:
; Example .......: _InstallUser("lang_de")
; ===============================================================================================================================
Func _InstallUser($sSec)
    Local $sMenuText = IniRead($sIniFile, $sSec, "MenuText", "Fix Preview")
    Local $sMsgSuccess = IniRead($sIniFile, $sSec, "MsgSuccess", "Done.")

    Local $sRegKey = "HKEY_CURRENT_USER\Software\Classes\SystemFileAssociations\.pdf\shell\UnblockPreview"
    Local $sCommand = '"' & @ScriptFullPath & '" "%1"'

    RegWrite($sRegKey, "", "REG_SZ", $sMenuText)
    RegWrite($sRegKey & "\command", "", "REG_SZ", $sCommand)
    RegWrite($sRegKey, "Icon", "REG_SZ", "imageres.dll,-5347")
    RegWrite($sRegKey, "MultiSelectModel", "REG_SZ", "Player")

    If Not $bSilent Then MsgBox(64, "Success", $sMsgSuccess & @CRLF & "(Current User)")
EndFunc

; #FUNCTION# ====================================================================================================================
; Name ..........: _TriggerGlobalInstallGUI
; Description ...: Checks for Admin rights and initiates the global installation process.
; Syntax ........: _TriggerGlobalInstallGUI($sSec)
; Parameters ....: $sSec                - A string value representing the language section in config.ini.
; Return values .: None
; Author ........: winnicodes
; Modified ......:
; Remarks .......: If the script is already running as Admin, it calls _InstallGlobal directly.
;                  If not, it uses ShellExecute with "runas" to restart the script with Admin privileges
;                  and passes the necessary command line parameters (/install_global).
; Related .......: _InstallGlobal
; Link ..........:
; Example .......: _TriggerGlobalInstallGUI("lang_de")
; ===============================================================================================================================
Func _TriggerGlobalInstallGUI($sSec)
    If IsAdmin() Then
        _InstallGlobal($sSec)
    Else
        ShellExecute(@ScriptFullPath, '/install_global "' & $sSec & '"', "", "runas")
    EndIf
EndFunc


; #FUNCTION# ====================================================================================================================
; Name ..........: _InstallGlobal
; Description ...: Installs the context menu entry system-wide for all users (HKLM/HKCR).
; Syntax ........: _InstallGlobal($sSec)
; Parameters ....: $sSec                - A string value representing the language section in config.ini (e.g., "lang_en").
; Return values .: None
; Author ........: winnicodes
; Modified ......:
; Remarks .......: Requires Administrator privileges. Writes to HKEY_CLASSES_ROOT\SystemFileAssociations\.pdf.
;                  Reads display name and messages from the specified section in config.ini.
; Related .......: _InstallUser, _TriggerGlobalInstall
; Link ..........:
; Example .......: _InstallGlobal("lang_de")
; ===============================================================================================================================
Func _InstallGlobal($sSec)
    Local $sMenuText = IniRead($sIniFile, $sSec, "MenuText", "Fix Preview")
    Local $sMsgSuccess = IniRead($sIniFile, $sSec, "MsgSuccess", "Done.")

    Local $sRegKey = "HKEY_CLASSES_ROOT\SystemFileAssociations\.pdf\shell\UnblockPreview"
    Local $sCommand = '"' & @ScriptFullPath & '" "%1"'

    Local $iRes = RegWrite($sRegKey, "", "REG_SZ", $sMenuText)

    ; RegWrite returns 0 on failure, which here almost always means missing admin rights
    If $iRes = 0 Then
        If Not $bSilent Then MsgBox(16, "Error", "Could not write to Registry HKEY_CLASSES_ROOT." & @CRLF & "Are you Admin?")
        Return
    EndIf

    RegWrite($sRegKey & "\command", "", "REG_SZ", $sCommand)
    RegWrite($sRegKey, "Icon", "REG_SZ", "imageres.dll,-5347")
    RegWrite($sRegKey, "MultiSelectModel", "REG_SZ", "Player")

    If Not $bSilent Then MsgBox(64, "Success", $sMsgSuccess & @CRLF & "(All Users / Global)")
EndFunc


; #FUNCTION# ====================================================================================================================
; Name ..........: _UninstallAll
; Description ...: Removes the context menu entry from both the Current User (HKCU) and Global (HKCR) scopes.
; Syntax ........: _UninstallAll()
; Parameters ....: None
; Return values .: None
; Author ........: winnicodes
; Modified ......:
; Remarks .......: Always removes the HKCU entry. Checks for the existence of the HKCR entry.
;                  If the global entry exists and the user is not Admin, it may prompt for elevation (unless in silent mode).
; Related .......: _InstallUser, _InstallGlobal
; Link ..........:
; Example .......: _UninstallAll()
; ===============================================================================================================================

Func _UninstallAll()
    Local $sKeyUser = "HKEY_CURRENT_USER\Software\Classes\SystemFileAssociations\.pdf\shell\UnblockPreview"
    RegDelete($sKeyUser)

    Local $sKeyGlobal = "HKEY_CLASSES_ROOT\SystemFileAssociations\.pdf\shell\UnblockPreview"
    Local $bGlobalExists = False
    RegRead($sKeyGlobal, "")
    If Not @error Then $bGlobalExists = True

    If $bGlobalExists Then
        If IsAdmin() Then
            RegDelete($sKeyGlobal)
            If Not $bSilent Then MsgBox(64, "Uninstall", "Removed User and Global entries.")
        Else
            ; Not admin: hand the delete to reg.exe via "runas" so UAC does the elevation
            If $bSilent Then
                 ShellExecuteWait("reg", 'delete "HKCR\SystemFileAssociations\.pdf\shell\UnblockPreview" /f', "", "runas")
            Else
                Local $iAsk = MsgBox(36, "Admin Rights", "Global entry found. Remove it too?" & @CRLF & "(Requires Admin rights)")
                If $iAsk = 6 Then
                    ShellExecuteWait("reg", 'delete "HKCR\SystemFileAssociations\.pdf\shell\UnblockPreview" /f', "", "runas")
                    MsgBox(64, "Uninstall", "Cleanup finished.")
                Else
                    MsgBox(64, "Uninstall", "Removed User entry only.")
                EndIf
            EndIf
        EndIf
    Else
        If Not $bSilent Then MsgBox(64, "Uninstall", "Removed User entry.")
    EndIf
EndFunc