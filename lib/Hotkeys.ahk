; Registers every hotkey Alcadeias owns, records new ones, and reads the
; hotkeys defined inside your .ahk scripts (for search + conflict warnings).

class Hotkeys {
    static Active := Map()      ; hotkey string -> true
    static Errors := []
    static _parseCache := Map() ; path -> {time, list}

    ; (Re)register all hotkeys from settings + items.
    static Rebuild() {
        HotIf()
        wanted := Map()
        Hotkeys.Errors := []
        dh := Store.Setting("dashboardHotkey")
        if (dh != "")
            wanted[dh] := (*) => Dashboard.Toggle()
        ph := Store.Setting("pasteHotkey")
        if (ph != "" && !wanted.Has(ph))
            wanted[ph] := (*) => Dashboard.ShowTab("paste")
        for item in Store.Items {
            hk := item["hotkey"]
            if (hk = "")
                continue
            if wanted.Has(hk) {
                Hotkeys.Errors.Push(Hotkeys.Pretty(hk) " is used twice; '" item["name"] "' is ignored")
                continue
            }
            wanted[hk] := Hotkeys._Callback(item["id"])
        }
        for hk in Hotkeys.Active
            if !wanted.Has(hk)
                try Hotkey(hk, "Off")
        Hotkeys.Active := Map()
        Snippets.Rebuild()
        for hk, cb in wanted {
            try {
                Hotkey(hk, cb, "On")
                Hotkeys.Active[hk] := true
            } catch as e {
                Hotkeys.Errors.Push("'" hk "' is not a valid hotkey (" e.Message ")")
            }
        }
    }

    static _Callback(id) => (*) => Actions.FromHotkey(id)

    ; Waits for the user to press a key combo. Returns e.g. "^!d",
    ; "" when cancelled (Esc / timeout), or "CLEAR" for Backspace.
    static Record(timeoutSec := 8) {
        Suspend(true)
        ih := InputHook("T" timeoutSec)
        ih.KeyOpt("{All}", "ES")
        ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-ES")
        ih.Start()
        ih.Wait()
        Suspend(false)
        if (ih.EndReason != "EndKey")
            return ""
        key := ih.EndKey
        if (StrLen(key) = 1)
            key := StrLower(key)
        raw := RegExReplace(ih.EndMods, "[<>]")
        mods := ""
        for m in ["^", "!", "+", "#"]
            if InStr(raw, m)
                mods .= m
        if (mods = "" && key = "Escape")
            return ""
        if (mods = "" && key = "Backspace")
            return "CLEAR"
        return mods . key
    }

    ; "^!d" -> "Ctrl+Alt+D"
    static Pretty(hk) {
        if (hk = "")
            return ""
        s := RegExReplace(hk, "^[~*$]+")
        if InStr(s, " & ") {
            parts := StrSplit(s, " & ", " `t")
            return Hotkeys.Pretty(parts[1]) " + " Hotkeys.Pretty(parts[2])
        }
        up := ""
        if RegExMatch(s, "i)\s+up$") {
            s := RegExReplace(s, "i)\s+up$")
            up := " (release)"
        }
        mods := "", key := s
        while (StrLen(key) > 1 && InStr("^!+#<>", SubStr(key, 1, 1))) {
            mods .= SubStr(key, 1, 1)
            key := SubStr(key, 2)
        }
        out := ""
        if InStr(mods, "^")
            out .= "Ctrl+"
        if InStr(mods, "!")
            out .= "Alt+"
        if InStr(mods, "+")
            out .= "Shift+"
        if InStr(mods, "#")
            out .= "Win+"
        if (StrLen(key) = 1)
            key := StrUpper(key)
        else
            key := StrUpper(SubStr(key, 1, 1)) . SubStr(key, 2)
        return out . key . up
    }

    ; Comparable form: modifiers sorted, no prefixes, lower case.
    static Normalize(hk) {
        s := StrLower(Trim(RegExReplace(hk, "^[~*$]+")))
        if InStr(s, " & ")
            return s
        mods := "", key := s
        while (StrLen(key) > 1 && InStr("^!+#<>", SubStr(key, 1, 1))) {
            c := SubStr(key, 1, 1)
            if !InStr("<>", c) && !InStr(mods, c)
                mods .= c
            key := SubStr(key, 2)
        }
        sorted := ""
        for m in ["^", "!", "+", "#"]
            if InStr(mods, m)
                sorted .= m
        return sorted . key
    }

    ; Hotkeys defined in an .ahk file: array of {hk, ctx} where ctx is "" for global ones.
    static FromScript(path) {
        if !FileExist(path)
            return []
        t := FileGetTime(path, "M")
        if Hotkeys._parseCache.Has(path) && Hotkeys._parseCache[path].time = t
            return Hotkeys._parseCache[path].list
        list := []
        try text := FileRead(path)
        catch
            return list
        ctx := "", inComment := false
        Loop Parse text, "`n", "`r" {
            line := A_LoopField
            if inComment {
                if RegExMatch(line, "^\s*\*/")
                    inComment := false
                continue
            }
            if RegExMatch(line, "^\s*/\*") {
                inComment := !RegExMatch(line, "\*/\s*$")
                continue
            }
            if RegExMatch(line, "i)^\s*#(HotIf|IfWin\w*|If)\b(.*)$", &m) {
                c := Trim(RegExReplace(m[2], "\s;.*$"), " `t,")
                ctx := c
                if RegExMatch(c, "i)ahk_exe\s+([^\s`"')]+)", &e)
                    ctx := e[1]
                continue
            }
            if RegExMatch(line, "^\s*([~*$<>^!+#]*(?:[^\s:;,`"']+|``;)(?:\s+&\s+[^\s:;,]+)?(?:\s+up)?)::", &m)
                list.Push({hk: m[1], ctx: ctx})
        }
        Hotkeys._parseCache[path] := {time: t, list: list}
        return list
    }

    ; Returns a list of human-readable clashes for hk (ignores the item being edited).
    static Conflicts(hk, exceptId := "") {
        out := []
        if (hk = "")
            return out
        n := Hotkeys.Normalize(hk)
        if (exceptId != "__dashboard" && Hotkeys.Normalize(Store.Setting("dashboardHotkey")) = n)
            out.Push("the dashboard hotkey")
        if (exceptId != "__paste" && Hotkeys.Normalize(Store.Setting("pasteHotkey")) = n)
            out.Push("the Paste hotkey")
        for item in Store.Items {
            if (item["id"] = exceptId)
                continue
            if (item["hotkey"] != "" && Hotkeys.Normalize(item["hotkey"]) = n)
                out.Push(Store.TypeNames[item["type"]] " '" item["name"] "'")
            if (item["type"] = "script")
                for h in Hotkeys.FromScript(item["path"])
                    if (h.ctx = "" && Hotkeys.Normalize(h.hk) = n)
                        out.Push("inside script '" item["name"] "'")
        }
        return out
    }
}
