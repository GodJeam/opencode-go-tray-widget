' Starts the OpenCode widget without a visible console window
Dim shell, fso, dir
Set shell = CreateObject("Wscript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -File """ & dir & "\opencode-tray.ps1""", 0, False

