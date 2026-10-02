; Editor for a macro keyboard's macros.ini (the Razer slave keyboard script).
; Shows up as "Key map" on any script that has a macros.ini next to it.

class KeyMap {
    static Types := [
        ["folder", "Open folder (also jumps Save dialogs)"], ["url", "Open website"],
        ["run", "Run program or file"], ["keys", "Send keys"], ["text", "Type text"],
        ["alcadeias", "Run an Alcadeias item"], ["func", "Script function"]]

    static Sections := [
        ["global", "Everywhere"], ["premiere", "Premiere Pro"], ["ae", "After Effects"],
        ["explorer", "Explorer + file dialogs"], ["chrome", "Chrome"], ["folders", "Numpad folder warps (1–9, 0)"]]

    static IniFor(item) {
        if (item["type"] != "script")
            return ""
        p := Files.Parent(item["path"]) "\macros.ini"
        return FileExist(p) ? p : ""
    }

    static TypeLabel(t) {
        for x in KeyMap.Types
            if (x[1] = t)
                return x[2]
        return t
    }

    static SectionLabel(s) {
        for x in KeyMap.Sections
            if (x[1] = s)
                return x[2]
        return s
    }

    ; "folder|C:\x" -> {type, target}
    static Parse(value, section) {
        if (section = "folders")
            return {type: "folder", target: value}
        p := InStr(value, "|")
        if !p
            return {type: "?", target: value}
        t := SubStr(value, 1, p - 1), v := SubStr(value, p + 1)
        if (t = "run" && InStr(v, "Alcadeias Run.ahk") && RegExMatch(v, '"([^"]*)"\s*$', &m))
            return {type: "alcadeias", target: m[1]}
        return {type: t, target: v}
    }

    static Build(type, target, section) {
        if (section = "folders")
            return target
        if (type = "alcadeias")
            return 'run|"' A_AhkPath '" "' A_ScriptDir '\Alcadeias Run.ahk" "' target '"'
        return type "|" target
    }

    static SectionList(ini) {
        have := Map()
        try for s in StrSplit(IniRead(ini), "`n")
            have[s] := true
        out := []
        for x in KeyMap.Sections
            out.Push(x[1])
        for s in have
            if (s != "config" && !KeyMap._In(s, out))
                out.Push(s)
        return out
    }

    static _In(v, arr) {
        for x in arr
            if (x = v)
                return true
        return false
    }

    static Entries(ini, section) {
        out := []
        txt := ""
        try txt := IniRead(ini, section)
        for line in StrSplit(txt, "`n") {
            p := InStr(line, "=")
            if !p
                continue
            out.Push({key: SubStr(line, 1, p - 1), value: SubStr(line, p + 1)})
        }
        return out
    }

    ; Visual keyboard when a layout is available, else the list.
    static Open(item) {
        if FileExist(Keyboard.LayoutFile)
            Keyboard.Open(item)
        else
            KeyMap.OpenList(item)
    }

    ; The list editor.
    static OpenList(item) {
        ini := KeyMap.IniFor(item)
        if (ini = "")
            return
        f := Form("Key map — " item["name"], Dialogs.Owner(), 860)
        sections := KeyMap.SectionList(ini)
        labels := []
        for s in sections
            labels.Push(KeyMap.SectionLabel(s))
        sec := f.DDL("Applies in", labels, 1, 320)
        f.Hint("App sections win over Everywhere when that app is in front. Changes save to macros.ini and reload the script.", 2)
        lv := Theme.ListView(f.g, Format("x24 y{} w812 h330", f.y), ["Key", "Does", "Target"], 28)
        lv.ModifyCol(1, 120), lv.ModifyCol(2, 230), lv.ModifyCol(3, 440)
        f.y += 340
        entries := []
        fill := () => KeyMap._Fill(lv, ini, sections[sec.Value], entries)
        sec.OnEvent("Change", (*) => fill())
        changed := false
        doEdit := (isNew) => (
            i := lv.GetNext(0),
            !isNew && !i ? 0 : (KeyMap.EditEntry(ini, sections[sec.Value], isNew ? "" : entries[i], f.g) ? (changed := true, fill()) : 0))
        FlatButton(f.g, Format("x24 y{} w110 h32", f.y), "+  Add key", (*) => doEdit(true))
        FlatButton(f.g, Format("x142 y{} w80 h32", f.y), "Edit", (*) => doEdit(false))
        FlatButton(f.g, Format("x230 y{} w90 h32", f.y), "Remove", (*) => (
            i := lv.GetNext(0),
            i ? (IniDelete(ini, sections[sec.Value], entries[i].key), changed := true, fill()) : 0), "danger")
        FlatButton(f.g, Format("x328 y{} w150 h32", f.y), "Open macros.ini", (*) => Run('notepad.exe "' ini '"'))
        lv.OnEvent("DoubleClick", (*) => doEdit(false))
        f.y += 42
        f.Buttons(() => f.Close(true), "Done")
        fill()
        f.ShowModal()
        if (changed && Scripts.IsRunning(item))
            Scripts.Apply(item, false)
    }

    static _Fill(lv, ini, section, entries) {
        entries.Length := 0
        lv.Delete()
        for e in KeyMap.Entries(ini, section) {
            p := KeyMap.Parse(e.value, section)
            entries.Push(e)
            lv.Add(, e.key, KeyMap.TypeLabel(p.type), p.target)
        }
    }

    ; Add (entry = "") or edit one key. Returns true if saved.
    static EditEntry(ini, section, entry, owner) {
        isFolders := section = "folders"
        p := entry ? KeyMap.Parse(entry.value, section) : {type: "folder", target: ""}
        f := Form(entry ? "Edit key" : "Add key", owner, 680)
        key := f.Edit("Key", entry ? entry.key : "")
        f.Hint(isFolders ? "1–9 or 0 for the numpad keys." : "The name your Razer sends, like numpad5, F13 or a (same names as the other rows).")
        labels := [], ti := 1
        for i, t in KeyMap.Types {
            labels.Push(t[2])
            if (t[1] = p.type)
                ti := i
        }
        typ := f.DDL("Does", labels, ti)
        if isFolders
            typ.Enabled := false
        target := f.EditBtn("Target", p.target, "Pick…", (c) => KeyMap._Pick(c, KeyMap.Types[typ.Value][1], f.g))
        f.Hint("Folder path, web address, program, keys like ^+e, text, an Alcadeias item name, or a function name.")
        saved := false
        save := () => (KeyMap._SaveEntry(f, ini, section, entry, Trim(key.Value), KeyMap.Types[typ.Value][1], Trim(target.Value)) ? (saved := true) : 0)
        f.Buttons(save)
        key.Focus()
        f.ShowModal()
        return saved
    }

    static _SaveEntry(f, ini, section, entry, k, type, target) {
        if (k = "" || RegExMatch(k, "[=\[\]]")) {
            MsgBox("Enter the key name.", "Alcadeias", "Icon!")
            return false
        }
        if (target = "") {
            MsgBox("Enter what it should open, send or run.", "Alcadeias", "Icon!")
            return false
        }
        if (entry && entry.key != k)
            IniDelete(ini, section, entry.key)
        IniWrite(KeyMap.Build(type, target, section), ini, section, k)
        f.Close(true)
        return true
    }

    static _Pick(c, type, owner) {
        switch type {
            case "folder":
                d := Picker.Choose("Pick a folder", "", owner)
                if (d != "")
                    c.Value := d
            case "run":
                p := FileSelect(3, , "Pick a program or file")
                if (p != "")
                    c.Value := p
            case "alcadeias":
                m := Menu()
                for item in Store.Items
                    if (item["type"] != "script")
                        m.Add(Store.TypeNames[item["type"]] ": " StrReplace(item["name"], "&", "&&"), KeyMap._SetFn(c, item["name"]))
                m.Show()
        }
    }

    static _SetFn(c, v) => (*) => c.Value := v
}
