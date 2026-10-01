; Every add/edit window: scripts, layouts (+ window slots + capture), apps,
; folders, links, and Settings.

; Small helper that stacks labeled rows top to bottom.
class Form {
    static Open := Map()   ; hwnd -> Form, for Enter = Save

    static Current() {
        h := WinActive("A")
        return Form.Open.Has(h) ? Form.Open[h] : ""
    }

    static _InitKeys() {
        static done := false
        if done
            return
        done := true
        HotIf((*) => Form._EnterSaves())
        Hotkey("Enter", (*) => Form.Current().onSave.Call())
        Hotkey("NumpadEnter", (*) => Form.Current().onSave.Call())
        HotIf()
    }

    ; Enter saves, unless a menu or an open dropdown should get it.
    static _EnterSaves() {
        f := Form.Current()
        if (f = "" || !f.HasOwnProp("onSave") || WinExist("ahk_class #32768"))
            return false
        try {
            ctl := ControlGetFocus("A")
            if (ctl && WinGetClass(ctl) = "ComboBox" && SendMessage(0x157, 0, 0, ctl))   ; CB_GETDROPPEDSTATE
                return false
        }
        return true
    }

    __New(title, owner := "", width := 640) {
        this.owner := owner
        this.width := width
        this.lx := 24, this.cx := 190
        this.cw := width - this.cx - 24
        this.y := 20
        this.result := false
        ownerOpt := owner ? " +Owner" owner.Hwnd : ""
        g := Theme.NewGui(title, "-MinimizeBox" ownerOpt)
        Theme.DarkTitle(g)
        this.g := g
        g.OnEvent("Close", (*) => this.Cancel())
        g.OnEvent("Escape", (*) => this.Cancel())
        Form.Open[g.Hwnd] := this
        Form._InitKeys()
    }

    Section(text) {
        this.y += 6
        Theme.Label(this.g, Format("x{} y{} w{} h22", this.lx, this.y, this.width - 48), text, Theme.AccentHi, 10, true)
        this.y += 30
    }

    Label(text) {
        Theme.Label(this.g, Format("x{} y{} w{} h22", this.lx, this.y + 6, this.cx - this.lx - 10), text, Theme.Muted)
    }

    Edit(label, value := "", width := 0) {
        this.Label(label)
        c := Theme.Edit(this.g, Format("x{} y{} w{} h30", this.cx, this.y, width ? width : this.cw), value)
        SendMessage(0xD3, 1, 8, c)
        this.y += 40
        return c
    }

    ; Edit plus a small button to its right (e.g. Browse).
    EditBtn(label, value, btnText, onClick, btnW := 90) {
        this.Label(label)
        c := Theme.Edit(this.g, Format("x{} y{} w{} h30", this.cx, this.y, this.cw - btnW - 8), value)
        SendMessage(0xD3, 1, 8, c)
        FlatButton(this.g, Format("x{} y{} w{} h30", this.cx + this.cw - btnW, this.y, btnW), btnText, (*) => onClick.Call(c))
        this.y += 40
        return c
    }

    DDL(label, items, chooseIndex := 1, width := 0) {
        this.Label(label)
        c := Theme.DDL(this.g, Format("x{} y{} w{} R12", this.cx, this.y + 1, width ? width : this.cw), items)
        c.Choose(chooseIndex)
        this.y += 40
        return c
    }

    Toggle(text, value) {
        t := Toggle(this.g, Format("x{} y{} w{} h26", this.cx, this.y, this.cw), text, value)
        this.y += 30
        return t
    }

    Hint(text, lines := 1) {
        lines := Max(lines, Ceil(StrLen(text) * 5.4 / this.cw))   ; rough wrap estimate for 8pt text
        this.y -= 8
        Theme.Label(this.g, Format("x{} y{} w{} h{}", this.cx, this.y, this.cw, lines * 17), text, Theme.Muted, 8)
        this.y += lines * 17 + 8
    }

    HotkeyRow(value, exceptId) => HotkeyField(this, value, exceptId)

    Buttons(onSave, saveText := "Save") {
        this.onSave := onSave
        this.y += 10
        Theme.Line(this.g, 0, this.y, this.width, Theme.Panel)
        this.y += 16
        FlatButton(this.g, Format("x{} y{} w100 h34", this.width - 24 - 100, this.y), "Cancel", (*) => this.Cancel())
        FlatButton(this.g, Format("x{} y{} w120 h34", this.width - 24 - 100 - 8 - 120, this.y), saveText, (*) => onSave.Call(), "accent")
        this.y += 34 + 18
    }

    ShowModal() {
        if this.owner
            this.owner.Opt("+Disabled")
        this.g.Show(Format("w{} h{}", this.width, this.y))
        WinWaitClose(this.g)
        if this.owner {
            this.owner.Opt("-Disabled")
            if DllCall("IsWindowVisible", "Ptr", this.owner.Hwnd)
                try WinActivate(this.owner)
        }
        return this.result
    }

    Close(result) {
        this.result := result
        if Form.Open.Has(this.g.Hwnd)
            Form.Open.Delete(this.g.Hwnd)
        FlatButton.Forget(this.g)
        this.g.Destroy()
    }

    Cancel() => this.Close(false)
}

; Hotkey input: type AHK syntax, or press Record and hit the combo.
class HotkeyField {
    __New(form, value, exceptId) {
        this.exceptId := exceptId
        g := form.g
        form.Label("Hotkey")
        this.edit := Theme.Edit(g, Format("x{} y{} w170 h30", form.cx, form.y), value)
        SendMessage(0xD3, 1, 8, this.edit)
        this.rec := FlatButton(g, Format("x{} y{} w100 h30", form.cx + 178, form.y), "● Record", (*) => this.DoRecord())
        FlatButton(g, Format("x{} y{} w70 h30", form.cx + 286, form.y), "Clear", (*) => this.Set(""))
        this.info := Theme.Label(g, Format("x{} y{} w{} h34", form.cx, form.y + 34, form.cw), "", Theme.Muted, 8)
        form.y += 34 + 40
        this.edit.OnEvent("Change", (*) => this.Update())
        this.Update()
    }

    Value => Trim(this.edit.Value)

    Set(v) {
        this.edit.Value := v
        this.Update()
    }

    DoRecord() {
        this.rec.Text := "Press keys…"
        this.info.Text := "Press the key combination now (Esc cancels, Backspace clears)"
        hk := Hotkeys.Record()
        this.rec.Text := "● Record"
        if (hk = "CLEAR")
            this.Set("")
        else if (hk != "")
            this.Set(hk)
        else
            this.Update()
    }

    Update() {
        v := this.Value
        if (v = "") {
            this.info.SetFont("c" Theme.Muted)
            this.info.Text := "No hotkey (optional). Record one, or type AutoHotkey syntax like ^!d or XButton2."
            return
        }
        c := Hotkeys.Conflicts(v, this.exceptId)
        if c.Length {
            s := ""
            for x in c
                s .= (s = "" ? "" : ", ") x
            this.info.SetFont("c" Theme.Warn)
            this.info.Text := Hotkeys.Pretty(v) "  -  heads up, also used by: " s
        } else {
            this.info.SetFont("c" Theme.Ok)
            this.info.Text := Hotkeys.Pretty(v) "  -  free"
        }
    }
}

class Dialogs {
    static Owner() => (Dashboard.g && Dashboard.IsVisible()) ? Dashboard.g : ""

    static EditItem(item, isNew) {
        switch item["type"] {
            case "script": ok := Dialogs.Script(item)
            case "layout": ok := Dialogs.Layout(item, isNew)
            default:       ok := Dialogs.Simple(item, isNew)
        }
        if ok {
            Hotkeys.Rebuild()
            Dashboard.Refresh()
        }
        return ok
    }

    ; Saves an edited copy back into the store.
    static _Commit(item, edited, isNew) {
        if isNew {
            Store.Add(edited)
            Dashboard.search.Value := ""
        } else
            Store.Replace(item, edited)
    }

    ; ---- app / folder / link ---------------------------------------------

    static Simple(item, isNew) {
        t := item["type"]
        e := Store.Clone(item)
        f := Form((isNew ? "New " : "Edit ") StrLower(Store.TypeNames[t]), Dialogs.Owner())
        name := f.Edit("Name", e["name"])
        hk := f.HotkeyRow(e["hotkey"], e["id"])
        switch t {
            case "app":
                f.Section("Which window")
                exe := f.EditBtn("Program (exe)", e["exe"], "Pick…", (*) => Dialogs._PickWindow(f, exe, title, launch, name))
                f.Hint("The process name, e.g. obsidian.exe. Pick… fills it from a window that's open now.")
                title := f.Edit("Title contains", e["title"])
                f.Hint("Optional. Only windows whose title contains this, e.g. Claude for a Chrome app window.")
                launch := f.EditBtn("Launch if closed", e["launch"], "Browse…", (c) => Dialogs._BrowseExe(c))
                f.Hint("Optional; defaults to the exe. Example: chrome.exe --app=https://claude.ai", 1)
                minim := f.Toggle("Pressing the hotkey again minimizes it", e["minimizeIfActive"])
            case "folder":
                path := f.EditBtn("Folder", e["path"], "Browse…", (c) => Dialogs._BrowseDir(c, name))
                f.Hint("Opens here — or, if a Save/Open dialog or Explorer is in front, jumps that window here.", 2)
            case "link":
                target := f.EditBtn("Open", e["target"], "File…", (c) => Dialogs._BrowseFile(c, name))
                f.Hint("A URL, a file, a program, or a command. %USERPROFILE%-style variables work.")
        }
        save := () => (
            e["name"] := Trim(name.Value),
            e["hotkey"] := hk.Value,
            t = "app" ? (e["exe"] := Trim(exe.Value), e["title"] := Trim(title.Value), e["launch"] := Trim(launch.Value), e["minimizeIfActive"] := minim.Value) : 0,
            t = "folder" ? (e["path"] := Trim(path.Value, " `t`"")) : 0,
            t = "link" ? (e["target"] := Trim(target.Value)) : 0,
            Dialogs._ValidateSimple(e) ? (Dialogs._Commit(item, e, isNew), f.Close(true)) : 0
        )
        f.Buttons(save)
        name.Focus()
        return f.ShowModal()
    }

    static _ValidateSimple(e) {
        if (e["name"] = "") {
            switch e["type"] {
                case "folder":
                    SplitPath(RTrim(e["path"], "\"), &n)
                    e["name"] := n
                case "app":
                    e["name"] := RegExReplace(e["exe"], "i)\.exe$")
                case "link":
                    e["name"] := RegExReplace(e["target"], "i)^https?://(www\.)?|/.*$")
            }
        }
        if (e["name"] = "") {
            MsgBox("Give it a name.", "Alcadeias", "Icon!")
            return false
        }
        if (e["type"] = "app" && e["exe"] = "" && e["title"] = "") {
            MsgBox("An app needs a program (exe) or title text to look for.", "Alcadeias", "Icon!")
            return false
        }
        return true
    }

    static _BrowseExe(c) {
        p := FileSelect(3, , "Pick a program", "Programs (*.exe; *.lnk; *.bat; *.cmd)")
        if (p != "")
            c.Value := '"' p '"'
    }

    static _BrowseDir(c, nameCtrl := "") {
        p := DirSelect("*" c.Value, 3, "Pick a folder")
        if (p != "") {
            c.Value := p
            if (nameCtrl && nameCtrl.Value = "") {
                SplitPath(RTrim(p, "\"), &n)
                nameCtrl.Value := n
            }
        }
    }

    static _BrowseFile(c, nameCtrl := "") {
        p := FileSelect(3, , "Pick a file")
        if (p != "") {
            c.Value := p
            if (nameCtrl && nameCtrl.Value = "") {
                SplitPath(p, , , , &n)
                nameCtrl.Value := n
            }
        }
    }

    ; Menu of open windows; picking one fills exe/title/launch.
    static _PickWindow(f, exe, title, launch, name := "") {
        m := Menu()
        seen := Map()
        for hwnd in WinGetList() {
            if !Layouts.IsAppWindow(hwnd)
                continue
            try {
                pe := WinGetProcessName(hwnd)
                pt := WinGetTitle(hwnd)
                pp := ""
                try pp := WinGetProcessPath(hwnd)
            } catch
                continue
            label := pe "   —   " (StrLen(pt) > 60 ? SubStr(pt, 1, 60) "…" : pt)
            if seen.Has(label)
                continue
            seen[label] := true
            m.Add(StrReplace(label, "&", "&&"), Dialogs._PickFn(pe, pt, pp, exe, title, launch, name))
        }
        m.Show()
    }

    static _PickFn(pe, pt, pp, exe, title, launch, name) {
        return (*) => (
            exe.Value := pe,
            title ? (title.Value := Layouts.Browsers.Has(StrLower(pe)) ? Layouts.CleanTitle(pe, pt) : "") : 0,
            launch && launch.Value = "" && pp != "" ? (launch.Value := '"' pp '"') : 0,
            name && name.Value = "" ? (name.Value := RegExReplace(pe, "i)\.exe$")) : 0
        )
    }

    ; ---- scripts ---------------------------------------------------------

    static Script(item) {
        e := Store.Clone(item)
        f := Form("Edit script", Dialogs.Owner())
        name := f.Edit("Name", e["name"])
        path := f.EditBtn("File", e["path"], "Browse…", (c) => (p := FileSelect(3, c.Value, "Pick a script", "AutoHotkey (*.ahk)"), p != "" ? (c.Value := p) : 0))
        detected := Scripts.DetectVersion(e["path"])
        vers := ["Auto-detect (v" detected ")", "AutoHotkey v1", "AutoHotkey v2"]
        ver := f.DDL("Version", vers, e["ahkVersion"] = "1" ? 2 : e["ahkVersion"] = "2" ? 3 : 1)
        f.Hint("Auto uses the #Requires line if there is one, otherwise the default in Settings.")
        hk := f.HotkeyRow(e["hotkey"], e["id"])
        f.Hint("This hotkey turns the script on and off.")
        auto := f.Toggle("Start this script when Alcadeias starts", e["autostart"])
        apply := f.Toggle("Auto-apply when the file is saved (in any editor)", e["autoApply"])
        f.Hint("Only reloads it if it's running. Errors are caught first; the old version keeps running.")
        save := () => (
            e["name"] := Trim(name.Value),
            e["path"] := Trim(path.Value, " `t`""),
            e["ahkVersion"] := ["auto", "1", "2"][ver.Value],
            e["hotkey"] := hk.Value,
            e["autostart"] := auto.Value,
            e["autoApply"] := apply.Value,
            e["name"] = "" ? MsgBox("Give it a name.", "Alcadeias", "Icon!")
                : !FileExist(e["path"]) ? MsgBox("That file doesn't exist.", "Alcadeias", "Icon!")
                : (Dialogs._Commit(item, e, false), f.Close(true))
        )
        f.Buttons(save)
        return f.ShowModal()
    }

    static NewScript() {
        f := Form("New script", Dialogs.Owner())
        name := f.Edit("Name", "")
        f.Hint("Becomes the file name, e.g. Chrome tweaks → Chrome tweaks.ahk")
        dir := f.EditBtn("Folder", Store.Setting("scriptsDir"), "Browse…", (c) => (p := DirSelect("*" c.Value, 3, "Where should the script go?"), p != "" ? (c.Value := p) : 0))
        names := []
        for k in Scripts.Templates
            names.Push(k)
        tpl := f.DDL("Start from", names, 2)
        auto := f.Toggle("Start this script when Alcadeias starts", 1)
        create := () => Dialogs._CreateScript(f, name.Value, dir.Value, names[tpl.Value], auto.Value)
        f.Buttons(create, "Create")
        name.Focus()
        ok := f.ShowModal()
        if f.HasOwnProp("created")
            Editor.Open(f.created)   ; after the dialog is gone, so the editor ends up in front
        return ok
    }

    static _CreateScript(f, name, dir, tplName, autostart) {
        name := Trim(name)
        if (name = "")
            return MsgBox("Give it a name.", "Alcadeias", "Icon!")
        fileName := RegExReplace(name, '[\\/:*?"<>|]', "_")
        dir := RTrim(Trim(dir), "\")
        try DirCreate(dir)
        catch
            return MsgBox("Can't create the folder:`n" dir, "Alcadeias", "Icon!")
        path := dir "\" fileName ".ahk"
        if FileExist(path)
            return MsgBox(path "`nalready exists. Use 'Add existing' for it, or pick another name.", "Alcadeias", "Icon!")
        fo := FileOpen(path, "w", "UTF-8")
        fo.Write(StrReplace(Scripts.Templates[tplName], "`n", "`r`n"))
        fo.Close()
        ; an entry for this path may survive from a file that was deleted; reuse it
        item := ""
        for it in Store.OfType("script")
            if (StrLower(it["path"]) = StrLower(path))
                item := it
        if !item {
            item := Store.NewItem("script", name)
            item["path"] := path
            Store.Items.Push(item)
        }
        item["name"] := name
        item["autostart"] := autostart
        Store.Save()
        f.created := item
        f.Close(true)
        Dashboard.search.Value := ""
        Dashboard.SetCategory("script")
    }

    static AddExistingScripts() {
        files := FileSelect("M3", Store.Setting("scriptsDir"), "Add AutoHotkey scripts", "AutoHotkey (*.ahk)")
        if !(files is Array) || !files.Length
            return
        have := Map()
        for item in Store.OfType("script")
            have[StrLower(item["path"])] := true
        running := Scripts.Running()
        added := 0
        for p in files {
            if have.Has(StrLower(p))
                continue
            SplitPath(p, , , , &stem)
            item := Store.NewItem("script", StrReplace(stem, "_", " "))
            item["path"] := p
            Store.Items.Push(item)
            added++
        }
        Store.Save()
        Hotkeys.Rebuild()
        Dashboard.search.Value := ""
        Dashboard.SetCategory("script")
        App.Status("Added " added " script" (added = 1 ? "" : "s") ". Turn on 'Start when Alcadeias starts' (Edit) for the ones you always want running.", "ok")
    }

    ; ---- layouts ---------------------------------------------------------

    static Layout(item, isNew) {
        e := Store.Clone(item)
        f := Form((isNew ? "New" : "Edit") " layout", Dialogs.Owner(), 820)
        name := f.Edit("Name", e["name"], 300)
        hk := f.HotkeyRow(e["hotkey"], e["id"])
        desks := ["Stay on the current desktop"]
        Loop 9
            desks.Push("Switch to desktop " A_Index " first")
        desk := f.DDL("Virtual desktop", desks, e["desktop"] + 1, 300)
        minim := f.Toggle("Minimize every other window", e["minimizeOthers"])

        f.Section("Windows in this layout")
        lv := Theme.ListView(f.g, Format("x24 y{} w772 h220", f.y), ["#", "App", "Title contains", "Monitor", "Position", "If closed"], 26)
        lv.ModifyCol(1, 32), lv.ModifyCol(2, 120), lv.ModifyCol(3, 170), lv.ModifyCol(4, 70), lv.ModifyCol(5, 190), lv.ModifyCol(6, 170)
        f.y += 230
        fill := () => Dialogs._FillSlots(lv, e["slots"])
        sel := () => lv.GetNext(0)
        bx := 24, by := f.y
        FlatButton(f.g, Format("x{} y{} w110 h32", bx, by), "+  Add window", (*) => (
            s := Dialogs.Slot(Store.SlotDefaults(Map()), f.g), s ? (e["slots"].Push(s), fill()) : 0))
        FlatButton(f.g, Format("x{} y{} w70 h32", bx + 118, by), "Edit", (*) => (
            i := sel(), i ? ((s := Dialogs.Slot(Store.Clone(e["slots"][i]), f.g)) ? (e["slots"][i] := s, fill(), lv.Modify(i, "Select")) : 0) : 0))
        FlatButton(f.g, Format("x{} y{} w80 h32", bx + 196, by), "Remove", (*) => (
            i := sel(), i ? (e["slots"].RemoveAt(i), fill()) : 0), "danger")
        FlatButton(f.g, Format("x{} y{} w46 h32", bx + 284, by), "Up", (*) => Dialogs._MoveSlot(e["slots"], lv, -1))
        FlatButton(f.g, Format("x{} y{} w56 h32", bx + 338, by), "Down", (*) => Dialogs._MoveSlot(e["slots"], lv, 1))
        FlatButton(f.g, Format("x{} y{} w120 h32", 430, by), "Capture screen", (*) => (
            Dialogs.Capture(e["slots"], f.g) ? fill() : 0))
        FlatButton(f.g, Format("x{} y{} w100 h32", 558, by), "Preview", (*) => Layouts.Preview(e["slots"]))
        FlatButton(f.g, Format("x{} y{} w130 h32", 666, by), "Identify monitors", (*) => Layouts.IdentifyMonitors())
        f.y += 42
        lv.OnEvent("DoubleClick", (*) => (
            i := sel(), i ? ((s := Dialogs.Slot(Store.Clone(e["slots"][i]), f.g)) ? (e["slots"][i] := s, fill()) : 0) : 0))
        f.Hint("Order matters: window 1 ends up focused. Capture screen = arrange windows by hand first, then grab them.", 1)
        fill()

        collect := () => (
            e["name"] := Trim(name.Value),
            e["hotkey"] := hk.Value,
            e["desktop"] := desk.Value - 1,
            e["minimizeOthers"] := minim.Value)
        test := () => (collect(), Layouts.Apply(e), WinActivate(f.g))
        save := () => (collect(),
            e["name"] = "" ? MsgBox("Give the layout a name.", "Alcadeias", "Icon!")
                : (Dialogs._Commit(item, e, isNew), f.Close(true)))
        FlatButton(f.g, Format("x24 y{} w120 h34", f.y + 26), "Test it now", (*) => test())
        f.Buttons(save)
        name.Focus()
        return f.ShowModal()
    }

    static _FillSlots(lv, slots) {
        lv.Delete()
        for i, s in slots {
            pos := s["state"] = "normal" ? Layouts.ZoneLabel(s["zone"]) : Layouts.StateLabel(s["state"])
            if (s["state"] = "normal" && s["zone"] = "custom")
                pos := Format("Custom {}/{}/{}/{}", s["x"], s["y"], s["w"], s["h"])
            lv.Add(, i, s["exe"], s["title"], "M" s["monitor"], pos, s["launch"] != "" ? "launch" : "skip")
        }
    }

    static _MoveSlot(slots, lv, d) {
        i := lv.GetNext(0)
        j := i + d
        if (!i || j < 1 || j > slots.Length)
            return
        t := slots[i], slots[i] := slots[j], slots[j] := t
        Dialogs._FillSlots(lv, slots)
        lv.Modify(j, "Select Focus")
    }

    ; One window slot. Returns the edited slot Map, or "" if cancelled.
    static Slot(s, owner) {
        f := Form("Window in layout", owner, 660)
        f.Section("Which window")
        exe := f.EditBtn("Program (exe)", s["exe"], "Pick…", (*) => Dialogs._PickWindow(f, exe, title, launch))
        f.Hint("Process name like obsidian.exe. Pick… grabs it from a window that's open now.")
        title := f.Edit("Title contains", s["title"])
        f.Hint("Optional. Tells windows of the same app apart, e.g. Claude vs. YouTube Studio in Chrome.")
        launch := f.EditBtn("Launch if closed", s["launch"], "Browse…", (c) => Dialogs._BrowseExe(c))
        f.Hint("Leave empty to skip it when closed. Claude as its own window: chrome.exe --app=https://claude.ai", 1)

        f.Section("Where it goes")
        mons := Layouts.MonitorNames()
        mon := f.DDL("Monitor", mons, Min(Max(1, s["monitor"]), mons.Length))
        states := [], si := 1
        for i, st in Layouts.States {
            states.Push(st[2])
            if (st[1] = s["state"])
                si := i
        }
        state := f.DDL("Size", states, si)
        zones := [], zi := 1
        for i, z in Layouts.Zones {
            zones.Push(z[2])
            if (z[1] = s["zone"])
                zi := i
        }
        zone := f.DDL("Position", zones, zi)
        f.Label("Custom %")
        cust := []
        for i, k in ["x", "y", "w", "h"] {
            Theme.Label(f.g, Format("x{} y{} w16 h22", f.cx + (i - 1) * 110, f.y + 6), k, Theme.Muted)
            c := Theme.Edit(f.g, Format("x{} y{} w80 h30", f.cx + (i - 1) * 110 + 18, f.y), s[k])
            cust.Push(c)
        }
        f.y += 40
        f.Hint("Percent of the monitor (minus taskbar). Used when Position is Custom.")
        sync := () => Dialogs._SyncSlotFields(state, zone, cust)
        state.OnEvent("Change", (*) => sync())
        zone.OnEvent("Change", (*) => (
            z := Layouts.Zones[zone.Value],
            z[1] != "custom" ? (cust[1].Value := z[3], cust[2].Value := z[4], cust[3].Value := z[5], cust[4].Value := z[6]) : 0,
            sync()))
        for c in cust
            c.OnEvent("Change", (*) => (zone.Value != Layouts.Zones.Length ? zone.Choose(Layouts.Zones.Length) : 0))
        if (s["zone"] != "custom") {
            z := Layouts.ZoneRect(s)
            Loop 4
                cust[A_Index].Value := z[A_Index]
        }
        sync()

        result := ""
        collect := () => (
            s["exe"] := Trim(exe.Value),
            s["title"] := Trim(title.Value),
            s["launch"] := Trim(launch.Value),
            s["monitor"] := mon.Value,
            s["state"] := Layouts.States[state.Value][1],
            s["zone"] := Layouts.Zones[zone.Value][1],
            s["x"] := Dialogs._Num(cust[1].Value, 0), s["y"] := Dialogs._Num(cust[2].Value, 0),
            s["w"] := Dialogs._Num(cust[3].Value, 100), s["h"] := Dialogs._Num(cust[4].Value, 100))
        FlatButton(f.g, Format("x24 y{} w120 h34", f.y + 26), "Preview", (*) => (collect(), Layouts.Preview([s])))
        save := () => (collect(),
            s["exe"] = "" && s["title"] = "" ? MsgBox("Fill in the program (exe) or some title text so Alcadeias can find the window.", "Alcadeias", "Icon!")
                : (result := s, f.Close(true)))
        f.Buttons(save, "OK")
        f.ShowModal()
        return result
    }

    static _SyncSlotFields(state, zone, cust) {
        normal := state.Value = 1
        zone.Enabled := normal
        isCustom := normal && zone.Value = Layouts.Zones.Length
        for c in cust
            c.Enabled := isCustom
    }

    static _Num(v, default) {
        v := Trim(StrReplace(v, ",", "."))
        return IsNumber(v) ? Round(Number(v), 2) : default
    }

    ; Lets you tick which on-screen windows to add. Returns true if slots changed.
    static Capture(slots, owner) {
        found := Layouts.Capture()
        if !found.Length {
            MsgBox("No windows found on this desktop.", "Alcadeias", "Icon!")
            return false
        }
        f := Form("Capture screen", owner, 820)
        Theme.Label(f.g, Format("x24 y{} w772 h40", f.y), "These are the windows on screen right now. Untick any you don't want. Arrange them how you like first — positions are saved as % of the monitor.", Theme.Muted, 9)
        f.y += 46
        lv := Theme.ListView(f.g, Format("x24 y{} w772 h300 Checked", f.y), ["App", "Window title", "Title match", "Monitor", "Position"], 26)
        lv.ModifyCol(1, 120), lv.ModifyCol(2, 260), lv.ModifyCol(3, 140), lv.ModifyCol(4, 60), lv.ModifyCol(5, 170)
        for s in found {
            pos := s["state"] != "normal" ? Layouts.StateLabel(s["state"])
                : s["zone"] != "custom" ? Layouts.ZoneLabel(s["zone"])
                : Format("{}/{}/{}/{} %", s["x"], s["y"], s["w"], s["h"])
            lv.Add("Check", s["exe"], s["_title"], s["title"], "M" s["monitor"], pos)
        }
        f.y += 310
        replace := Toggle(f.g, Format("x24 y{} w500 h26", f.y), "Replace the layout's current windows (otherwise add to them)", slots.Length = 0)
        f.y += 30
        changed := false
        save := () => (
            Dialogs._TakeCaptured(lv, found, slots, replace.Value),
            changed := true,
            f.Close(true))
        f.Buttons(save, "Use these")
        f.ShowModal()
        return changed
    }

    static _TakeCaptured(lv, found, slots, replace) {
        if replace
            slots.Length := 0
        row := 0
        while (row := lv.GetNext(row, "Checked")) {
            s := found[row]
            s.Delete("_title"), s.Delete("_hwnd")
            slots.Push(s)
        }
    }

    ; ---- settings --------------------------------------------------------

    static Settings() {
        st := Store.Settings
        f := Form("Settings", Dialogs.Owner(), 720)
        f.Section("Alcadeias")
        hk := f.HotkeyRow(st["dashboardHotkey"], "__dashboard")
        startWin := f.Toggle("Start Alcadeias with Windows", st["startWithWindows"])
        startHidden := f.Toggle("Start hidden (open with the hotkey or the tray icon)", st["startHidden"])

        f.Section("AutoHotkey")
        v1 := f.EditBtn("v1 interpreter", st["ahkV1Path"], "Browse…", (c) => (p := FileSelect(3, , "AutoHotkey v1 (AutoHotkeyU64.exe)", "Programs (*.exe)"), p != "" ? (c.Value := p) : 0))
        found1 := Scripts.FindV1()
        f.Hint(found1 != "" ? "Empty = auto: " found1 : "Not found automatically. v1 scripts need AutoHotkey v1.1 installed (the v2 installer can add it).")
        v2 := f.EditBtn("v2 interpreter", st["ahkV2Path"], "Browse…", (c) => (p := FileSelect(3, , "AutoHotkey v2 (AutoHotkey64.exe)", "Programs (*.exe)"), p != "" ? (c.Value := p) : 0))
        f.Hint("Empty = the one running Alcadeias: " A_AhkPath)
        defv := f.DDL("Scripts with no #Requires", ["are v1", "are v2"], st["defaultVersion"] = "2" ? 2 : 1, 200)

        f.Section("Files")
        ed := f.EditBtn("External editor", st["editorPath"], "Browse…", (c) => (p := FileSelect(3, , "Pick your editor", "Programs (*.exe)"), p != "" ? (c.Value := p) : 0))
        f.Hint("Empty = Notepad. VS Code is usually %LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe")
        sdir := f.EditBtn("New scripts go in", st["scriptsDir"], "Browse…", (c) => (p := DirSelect("*" c.Value, 3, "Folder for new scripts"), p != "" ? (c.Value := p) : 0))
        vdaEdit := f.EditBtn("VirtualDesktop dll", st["vdaPath"], "Browse…", (c) => (p := FileSelect(3, , "VirtualDesktopAccessor.dll", "DLL (*.dll)"), p != "" ? (c.Value := p) : 0))
        f.Hint("Optional. Lets layouts switch desktops and pull windows over from other desktops. Use the same dll your Win_Hotkeys script uses.", 2)

        FlatButton(f.g, Format("x24 y{} w150 h34", f.y + 26), "Open data folder", (*) => Run('explorer.exe "' Store.Dir '"'))
        save := () => (
            st["dashboardHotkey"] := hk.Value != "" ? hk.Value : "^!d",
            st["startWithWindows"] := startWin.Value,
            st["startHidden"] := startHidden.Value,
            st["ahkV1Path"] := Trim(v1.Value, " `t`""),
            st["ahkV2Path"] := Trim(v2.Value, " `t`""),
            st["defaultVersion"] := defv.Value = 2 ? "2" : "1",
            st["editorPath"] := Trim(Actions.Expand(ed.Value), " `t`""),
            st["scriptsDir"] := Trim(sdir.Value, " `t`""),
            st["vdaPath"] := Trim(vdaEdit.Value, " `t`""),
            Store.Save(),
            App.ApplyStartup(),
            Hotkeys.Rebuild(),
            f.Close(true),
            Dashboard.Refresh(),
            App.Status("Settings saved", "ok"))
        f.Buttons(save)
        return f.ShowModal()
    }
}
