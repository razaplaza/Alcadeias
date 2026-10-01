; Clipboard history + snippets (saved text). Both live in Work -> Paste.
; Enter pastes into the window you came from. Snippets can also be typed
; anywhere with a short abbreviation (e.g. ;desc).

class Clips {
    static File := A_ScriptDir "\data\clipboard.json"
    static history := []     ; newest first: {text, time}
    static Max := 100
    static _ignore := false
    static _dirty := false

    static Load() {
        if Store.Setting("saveClipboard", 1)
            try {
                d := JSON.Load(FileRead(Clips.File, "UTF-8"))
                if (d is Array)
                    for x in d
                        if (x is Map)
                            Clips.history.Push({text: x["text"], time: x["time"]})
            }
        OnClipboardChange(ObjBindMethod(Clips, "_OnChange"))
        SetTimer(() => Clips.Save(), 15000)
        OnExit((*) => Clips.Save())
    }

    static Save() {
        if !Clips._dirty
            return
        Clips._dirty := false
        if !Store.Setting("saveClipboard", 1) {
            try FileDelete(Clips.File)
            return
        }
        arr := []
        for x in Clips.history
            arr.Push(Map("text", x.text, "time", x.time))
        try {
            tmp := Clips.File ".tmp"
            try FileDelete(tmp)
            FileAppend(JSON.Dump(arr, ""), tmp, "UTF-8")
            FileMove(tmp, Clips.File, 1)
        }
    }

    static _OnChange(type) {
        if (type != 1 || Clips._ignore)
            return
        ; password managers mark their copies as "don't record me"
        for fmt in ["ExcludeClipboardContentFromMonitorProcessing", "Clipboard Viewer Ignore"]
            if DllCall("IsClipboardFormatAvailable", "UInt", DllCall("RegisterClipboardFormat", "Str", fmt, "UInt"))
                return
        t := ""
        try t := A_Clipboard
        if (Trim(t, " `t`r`n") = "" || StrLen(t) > 50000)
            return
        Clips.Add(t)
    }

    static Add(t) {
        for i, x in Clips.history
            if (x.text == t) {
                Clips.history.RemoveAt(i)
                break
            }
        Clips.history.InsertAt(1, {text: t, time: A_Now})
        while (Clips.history.Length > Clips.Max)
            Clips.history.Pop()
        Clips._dirty := true
    }

    static Remove(t) {
        for i, x in Clips.history
            if (x.text == t) {
                Clips.history.RemoveAt(i)
                Clips._dirty := true
                return
            }
    }

    static Clear() {
        Clips.history := []
        Clips._dirty := true
        Clips.Save()
    }

    ; {date} {time} {clipboard} in snippets
    static Expand(text) {
        cb := ""
        try cb := A_Clipboard
        text := StrReplace(text, "{date}", FormatTime(, "yyyy-MM-dd"))
        text := StrReplace(text, "{time}", FormatTime(, "HH:mm"))
        return StrReplace(text, "{clipboard}", cb)
    }

    ; Pastes text into target (the window you came from) and restores the clipboard.
    static PasteText(text, target := 0) {
        Clips._ignore := true
        saved := ClipboardAll()
        A_Clipboard := text
        ClipWait(1)
        if (target && WinExist(target)) {
            try WinActivate(target)
            WinWaitActive(target, , 1)
        }
        Send("^v")
        Sleep(300)
        A_Clipboard := saved
        SetTimer(() => Clips._ignore := false, -500)
    }

    static CopyText(text) {
        A_Clipboard := text
        App.Status("Copied", "ok")
    }

    static Preview(text, n := 90) {
        t := Trim(RegExReplace(text, "\s+", " "))
        return StrLen(t) > n ? SubStr(t, 1, n) "…" : t
    }

    static LineInfo(text) {
        lines := StrSplit(text, "`n").Length
        return lines > 1 ? lines " lines" : StrLen(text) " chars"
    }
}

; Typed abbreviations for snippets (registered by Hotkeys.Rebuild).
class Snippets {
    static Active := Map()   ; hotstring -> true

    static Rebuild() {
        for hs in Snippets.Active
            try Hotstring(hs, , "Off")
        Snippets.Active := Map()
        for item in Store.OfType("snippet") {
            abbr := Trim(item["abbr"])
            if (abbr = "")
                continue
            hs := ":*B0:" abbr
            try {
                Hotstring(hs, Snippets._Fn(item["id"], StrLen(abbr)), "On")
                Snippets.Active[hs] := true
            } catch as e
                Hotkeys.Errors.Push("abbreviation '" abbr "': " e.Message)
        }
    }

    static _Fn(id, len) => (*) => Snippets.Fire(id, len)

    static Fire(id, len) {
        item := Store.ById(id)
        if !item
            return
        Send("{BS " len "}")
        Clips.PasteText(Clips.Expand(item["text"]), WinExist("A"))
    }
}
