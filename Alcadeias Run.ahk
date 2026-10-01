; Runs an Alcadeias item by name from anywhere (Razer keys, Stream Deck,
; shortcuts, other scripts):
;   AutoHotkey64.exe "Alcadeias Run.ahk" "Item name"
#Requires AutoHotkey v2.0
#NoTrayIcon
name := A_Args.Length ? A_Args[1] : ""
if (name = "")
    ExitApp
DetectHiddenWindows(true)
SetTitleMatchMode(2)
target := WinExist(A_ScriptDir "\Alcadeias.ahk ahk_class AutoHotkey")
if !target {
    MsgBox("Alcadeias isn't running, so '" name "' can't be run.", "Alcadeias", "Icon! T5")
    ExitApp
}
msg := "run:" name
cds := Buffer(3 * A_PtrSize, 0)
NumPut("UPtr", 0, cds, 0)
NumPut("UInt", (StrLen(msg) + 1) * 2, cds, A_PtrSize)
NumPut("Ptr", StrPtr(msg), cds, 2 * A_PtrSize)
try SendMessage(0x4A, 0, cds, , target, , , , 3000)
