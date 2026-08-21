' Avvia il widget OpenCode senza finestra di console visibile
Dim shell, fso, dir
Set shell = CreateObject("Wscript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -File """ & dir & "\opencode-tray.ps1""", 0, False
