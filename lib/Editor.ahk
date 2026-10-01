; Built-in script editor. Ctrl+S = save, syntax-check, and swap the running
; script for the new version (the old one keeps running if there's an error).

class Editor {
    static Windows := Map()   ; item id -> EditorWindow
    static _keysReady := false

    static Open(item) {
        if !FileExist(item["path"]) {
            App.Status("File not found: " item["path"], "error")
            return
        }
        id := item["id"]
        if Editor.Windows.Has(id) {
            w := Editor.Windows[id]
            w.g.Show()
            WinActivate(w.g)
            w.KeepCaret()
            return w
        }
        Editor._InitKeys()
        w := EditorWindow(item)
        Editor.Windows[id] := w
        return w
    }

    static External(item) {
        ed := Store.Setting("editorPath")
        try {
            if (ed != "" && FileExist(ed))
                Run('"' ed '" "' item["path"] '"')
            else
                Run('notepad.exe "' item["path"] '"')
            App.Status("Opened '" item["name"] "' externally. Saving there auto-applies it" (item["autoApply"] ? "." : " (auto-apply is off for this script)."), "ok")
        } catch as e
            App.Status("Couldn't open editor: " e.Message, "error")
    }

    static ActiveWindow() {
        hwnd := WinActive("A")
        for id, w in Editor.Windows
            if (w.g.Hwnd = hwnd)
                return w
        return ""
    }

    static _InitKeys() {
        if Editor._keysReady
            return
        Editor._keysReady := true
        HotIf((*) => Editor.ActiveWindow() != "" && !WinExist("ahk_class #32768"))
        Hotkey("^s", (*) => Editor.ActiveWindow().Save(true))
        Hotkey("^+s", (*) => Editor.ActiveWindow().Save(false))
        Hotkey("^g", (*) => Editor.ActiveWindow().GoToLinePrompt())
        Hotkey("^f", (*) => Editor.ActiveWindow().FindPrompt())
        Hotkey("F3", (*) => Editor.ActiveWindow().FindNext())
        HotIf()
    }

    ; "UTF-8" (with BOM), "UTF-8-RAW" (no BOM), "UTF-16" or "CP0" (ANSI)
    static DetectEncoding(path) {
        buf := FileRead(path, "RAW")
        n := buf.Size
        if (n >= 3 && NumGet(buf, 0, "UChar") = 0xEF && NumGet(buf, 1, "UChar") = 0xBB && NumGet(buf, 2, "UChar") = 0xBF)
            return "UTF-8"
        if (n >= 2 && NumGet(buf, 0, "UChar") = 0xFF && NumGet(buf, 1, "UChar") = 0xFE)
            return "UTF-16"
        if (n = 0)
            return "UTF-8"
        ; MB_ERR_INVALID_CHARS: fails if the bytes aren't valid UTF-8
        ok := DllCall("MultiByteToWideChar", "UInt", 65001, "UInt", 8, "Ptr", buf, "Int", n, "Ptr", 0, "Int", 0)
        return ok ? "UTF-8-RAW" : "CP0"
    }
}

class EditorWindow {
    __New(item) {
        this.item := item
        this.dirty := false
        this.findText := ""
        g := Theme.NewGui(item["name"] " — Alcadeias", "+Resize +MinSize640x420")
        this.g := g
        Theme.DarkTitle(g)

        this.bSave := FlatButton(g, "x16 y14 w170 h34", "Save && apply  (Ctrl+S)", (*) => this.Save(true), "accent")
        this.bSaveOnly := FlatButton(g, "x194 y14 w100 h34", "Save only", (*) => this.Save(false))
        this.bExternal := FlatButton(g, "x302 y14 w130 h34", "External editor", (*) => Editor.External(this.item))
        this.bRevert := FlatButton(g, "x440 y14 w90 h34", "Revert", (*) => this.Revert())
        this.bBackups := FlatButton(g, "x538 y14 w100 h34", "Backups", (*) => this.OpenBackups())
        this.bStop := FlatButton(g, "x646 y14 w80 h34", "Stop", (*) => this.StopScript(), "danger")
        this.info := Theme.Label(g, "x740 y22 w400 h20", "", Theme.Muted, 9)

        this.edit := Theme.Edit(g, "x16 y60 w900 h500 Multi WantTab -Wrap HScroll VScroll", "", true)
        this.edit.SetFont("s11")
        SendMessage(0xD3, 3, (8 << 16) | 8, this.edit)   ; left/right margins
        ; tab stops = 4 characters (16 dialog units)
        tabs := Buffer(4), NumPut("Int", 16, tabs)
        SendMessage(0xCB, 1, tabs.Ptr, this.edit)   ; EM_SETTABSTOPS
        this.edit.OnEvent("Change", (*) => this.MarkDirty())

        this.status := Theme.Label(g, "x16 y570 w900 h20", "", Theme.Muted, 9)
        this.status.OnEvent("Click", (*) => this.JumpToError())

        g.OnEvent("Size", (g, mm, w, h) => mm != -1 ? this.Layout(w, h) : 0)
        g.OnEvent("Close", (*) => this.Close())
        g.OnEvent("Escape", (*) => this.Close())

        this.Load()
        g.Show("w1000 h680")
        this.edit.Focus()
        this.KeepCaret(0)
        this.UpdateInfo()
        this.timer := ObjBindMethod(this, "UpdateInfo")
        SetTimer(this.timer, 1500)
    }

    ; Windows selects all text when a window focuses its first edit box;
    ; put the caret back (one typed key would otherwise replace the script).
    KeepCaret(pos := -1) {
        if (pos < 0) {
            start := 0, end := 0
            DllCall("SendMessage", "Ptr", this.edit.Hwnd, "UInt", 0xB0, "UInt*", &start, "UInt*", &end)
            pos := (start = 0 && end = StrLen(this.edit.Value) + EditorWindow._CountCR(this.edit, end)) ? 0 : end
        }
        fix := () => (DllCall("IsWindow", "Ptr", this.edit.Hwnd) ? SendMessage(0xB1, pos, pos, this.edit) : 0)
        fix()
        SetTimer(fix, -60)
        SetTimer(fix, -250)
    }

    Load() {
        p := this.item["path"]
        this.enc := Editor.DetectEncoding(p)
        text := FileRead(p, this.enc)
        this.crlf := InStr(text, "`r`n") || !InStr(text, "`n")
        this.edit.Value := text
        this.saved := this.edit.Value
        this.dirty := false
        this.UpdateTitle()
        Scripts.MarkSeen(this.item)
    }

    Layout(w, h) {
        this.edit.Move(16, 60, w - 32, h - 60 - 40)
        this.status.Move(16, h - 30, w - 32)
        this.info.Move(740, 22, Max(100, w - 756))
    }

    MarkDirty() {
        d := this.edit.Value != this.saved
        if (d != this.dirty) {
            this.dirty := d
            this.UpdateTitle()
        }
    }

    UpdateTitle() => this.g.Title := (this.dirty ? "● " : "") this.item["name"] " — Alcadeias"

    UpdateInfo(*) {
        if !this.HasOwnProp("g") || !WinExist(this.g)
            return
        running := Scripts.IsRunning(this.item)
        enc := this.enc = "UTF-8" ? "UTF-8 BOM" : this.enc = "UTF-8-RAW" ? "UTF-8" : this.enc = "CP0" ? "ANSI" : this.enc
        s := "AHK v" Scripts.Version(this.item) " · " enc " · " (this.crlf ? "CRLF" : "LF") " · " (running ? "● Running" : "○ Stopped")
        if (this.info.Text != s)
            this.info.Text := s
        this.bStop.Visible := running
    }

    ; apply=true: also syntax-check and swap in the new version.
    Save(apply := true) {
        text := this.edit.Value
        if this.crlf
            text := StrReplace(text, "`n", "`r`n")
        try {
            Scripts.Backup(this.item)
            f := FileOpen(this.item["path"], "w", this.enc)
            f.Write(text)
            f.Close()
        } catch as e {
            this.SetStatus("Couldn't save: " e.Message, "error")
            return
        }
        this.saved := this.edit.Value
        this.dirty := false
        this.UpdateTitle()
        Scripts.MarkSeen(this.item)
        if !apply {
            this.SetStatus("Saved " FormatTime(, "HH:mm:ss") " (not applied)", "ok")
            return
        }
        this.SetStatus("Checking…", "")
        if Scripts.Apply(this.item, true)
            this.SetStatus("Saved and applied " FormatTime(, "HH:mm:ss") " — the new version is running", "ok")
        else {
            err := Scripts.LastError.Get(this.item["id"], "unknown error")
            this.lastError := err
            this.SetStatus(Scripts.FirstLine(err) "   (click to jump there; the old version is still running)", "error")
            this.JumpToError()
        }
        Dashboard.RefreshSoon()
        this.UpdateInfo()
    }

    SetStatus(text, kind) {
        color := kind = "error" ? Theme.Danger : kind = "ok" ? Theme.Ok : Theme.Muted
        this.status.SetFont("c" color)
        this.status.Text := text
    }

    JumpToError() {
        if !this.HasOwnProp("lastError")
            return
        line := Scripts.ErrorLine(this.lastError)
        if line
            this.GoToLine(line)
    }

    GoToLine(n) {
        idx := SendMessage(0xBB, n - 1, 0, this.edit)   ; EM_LINEINDEX
        if (idx = -1 || idx = 0xFFFFFFFF)
            return
        len := SendMessage(0xC1, idx, 0, this.edit)    ; EM_LINELENGTH
        this.edit.Focus()
        SendMessage(0xB1, idx, idx + len, this.edit)   ; EM_SETSEL
        SendMessage(0xB7, 0, 0, this.edit)             ; EM_SCROLLCARET
    }

    GoToLinePrompt() {
        r := InputBox("Line number:", "Go to line", "w220 h110 Owner" this.g.Hwnd)
        if (r.Result = "OK" && IsInteger(r.Value))
            this.GoToLine(Integer(r.Value))
    }

    FindPrompt() {
        r := InputBox("Find:", "Find", "w300 h110 Owner" this.g.Hwnd, this.findText)
        if (r.Result = "OK" && r.Value != "") {
            this.findText := r.Value
            this.FindNext()
        }
    }

    FindNext() {
        if (this.findText = "")
            return this.FindPrompt()
        text := this.edit.Value   ; LF line endings, same as the control's character positions
        start := 0, end := 0
        DllCall("SendMessage", "Ptr", this.edit.Hwnd, "UInt", 0xB0, "UInt*", &start, "UInt*", &end)   ; EM_GETSEL
        ; the control counts CRLF as 2 chars; convert position to LF-text position
        lfPos := end - EditorWindow._CountCR(this.edit, end)
        p := InStr(text, this.findText, false, lfPos + 1)
        if !p
            p := InStr(text, this.findText, false)   ; wrap around
        if !p {
            this.SetStatus("'" this.findText "' not found", "error")
            return
        }
        ; back to control positions: add one per line break before p
        lines := StrSplit(SubStr(text, 1, p - 1), "`n").Length - 1
        s := p - 1 + lines
        this.edit.Focus()
        SendMessage(0xB1, s, s + StrLen(this.findText), this.edit)
        SendMessage(0xB7, 0, 0, this.edit)
    }

    static _CountCR(edit, pos) {
        line := SendMessage(0xC9, pos, 0, edit)   ; EM_LINEFROMCHAR
        return line
    }

    Revert() {
        if this.dirty && MsgBox("Throw away your unsaved changes?", "Alcadeias", "YesNo Icon! Owner" this.g.Hwnd) != "Yes"
            return
        this.Load()
        this.SetStatus("Reloaded from disk", "ok")
    }

    OpenBackups() {
        d := Scripts.BackupDir(this.item)
        DirCreate(d)
        Run('explorer.exe "' d '"')
    }

    StopScript() {
        Scripts.Stop(this.item)
        this.SetStatus("Stopped", "ok")
        this.UpdateInfo()
        Dashboard.RefreshSoon()
    }

    Close() {
        if this.dirty {
            r := MsgBox("Save changes to '" this.item["name"] "' and apply them?", "Alcadeias", "YesNoCancel Icon? Owner" this.g.Hwnd)
            if (r = "Cancel")
                return true
            if (r = "Yes")
                this.Save(true)
        }
        SetTimer(this.timer, 0)
        Editor.Windows.Delete(this.item["id"])
        FlatButton.Forget(this.g)
        this.g.Destroy()
        return true
    }
}
