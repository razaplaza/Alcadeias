; =============================================================================
;  Alcadeias — one dashboard for your scripts, window layouts, apps, folders
;  and links. Ctrl+Alt+D shows/hides it.
;
;  Needs AutoHotkey v2 to run Alcadeias itself. Your own scripts can stay v1;
;  Alcadeias starts each one with the right version.
; =============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#WinActivateForce
Persistent
SetTitleMatchMode(2)
SetWinDelay(-1)
SetControlDelay(-1)
A_MaxHotkeysPerInterval := 400

#Include lib\JSON.ahk
#Include lib\Theme.ahk
#Include lib\Store.ahk
#Include lib\Hotkeys.ahk
#Include lib\Scripts.ahk
#Include lib\Layouts.ahk
#Include lib\Actions.ahk
#Include lib\Editor.ahk
#Include lib\Dialogs.ahk
#Include lib\Dashboard.ahk

App.Start()

class App {
    static Version := "0.1.0"

    static Start() {
        Theme.InitApp()
        Store.Load()
        App.BuildTray()
        Hotkeys.Rebuild()
        Scripts.StartAutostart()
        SetTimer(() => Scripts.Watch(), 1000)
        Dashboard.Build()
        hidden := Store.Setting("startHidden")
        for arg in A_Args
            if (arg = "/tray")
                hidden := true
        if !hidden
            Dashboard.Show()
        if Hotkeys.Errors.Length
            App.Status("Hotkey problem: " Hotkeys.Errors[1], "warn")
    }

    static BuildTray() {
        A_IconTip := "Alcadeias"
        try TraySetIcon(A_ScriptDir "\assets\alcadeias.ico")
        m := A_TrayMenu
        m.Delete()
        m.Add("Open Alcadeias", (*) => Dashboard.Show())
        m.Add("Settings…", (*) => (Dashboard.Show(), Dialogs.Settings()))
        m.Add()
        m.Add("Reload Alcadeias", (*) => Reload())
        m.Add("Exit (your scripts keep running)", (*) => ExitApp())
        m.Default := "Open Alcadeias"
        m.ClickCount := 1
    }

    ; Status message: shown in the dashboard; when the dashboard is hidden
    ; (e.g. a hotkey fired) problems also pop up as a small toast.
    static Status(msg, kind := "", toast := false) {
        color := kind = "error" ? Theme.Danger : kind = "warn" ? Theme.Warn : kind = "ok" ? Theme.Ok : Theme.Muted
        if (Dashboard.g && Dashboard.statusText) {
            Dashboard.statusText.SetFont("c" color)
            Dashboard.statusText.Text := msg
        }
        if (!Dashboard.IsVisible() && (toast || kind = "error" || kind = "warn"))
            App.Toast(msg, color)
    }

    static Toast(msg, color := "") {
        static g := ""
        try g.Destroy()
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        g.BackColor := Theme.Panel
        g.MarginX := 16, g.MarginY := 12
        g.SetFont("s10 c" (color != "" ? color : Theme.Text), Theme.Font)
        g.Add("Text", "w420", msg)
        g.Show("Hide AutoSize")
        g.GetPos(, , &w, &h)
        MonitorGetWorkArea(MonitorGetPrimary(), , , &r, &b)
        g.Show(Format("x{} y{} NoActivate", r - w - 20, b - h - 20))
        WinSetTransparent(235, g)
        SetTimer(App._DestroyGui.Bind(App, g), -3500)
    }

    static _DestroyGui(gui) {
        try gui.Destroy()
    }

    ; Adds/removes the Startup-folder shortcut.
    static ApplyStartup() {
        lnk := A_Startup "\Alcadeias.lnk"
        if Store.Setting("startWithWindows") {
            try FileCreateShortcut(A_AhkPath, lnk, A_ScriptDir, '"' A_ScriptFullPath '" /tray', "Alcadeias")
        } else if FileExist(lnk)
            try FileDelete(lnk)
    }
}
