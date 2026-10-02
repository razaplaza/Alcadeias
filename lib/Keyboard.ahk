; Visual key map for the Razer slave keyboard (Cynosa Chroma, Nordic ISO).
; Every key shows what it does; hover = details below the keyboard; click =
; searchable list of everything you can put on it. With live detection on,
; pressing a Razer key lights it up (and teaches Alcadeias its name).

class Keyboard {
    static LayoutFile := A_ScriptDir "\assets\keyboards\cynosa-chroma-nordic.json"
    static LiveFile := A_Temp "\alcadeias-razer.ini"
    static _layout := ""
    static Windows := Map()   ; script item id -> KeyboardWindow

    static Contexts := [["global", "Everywhere"], ["premiere", "Premiere"], ["ae", "After Effects"],
        ["explorer", "Explorer"], ["chrome", "Chrome"]]

    static Layout() {
        if !Keyboard._layout
            Keyboard._layout := JSON.Load(FileRead(Keyboard.LayoutFile, "UTF-8"))
        return Keyboard._layout
    }

    static Open(item) {
        if Keyboard.Windows.Has(item["id"]) {
            w := Keyboard.Windows[item["id"]]
            try {
                w.g.Show()
                WinActivate(w.g)
                return
            }
        }
        Keyboard.Windows[item["id"]] := KeyboardWindow(item)
    }

    ; What the Razer sends for a key: learned name, else the layout default.
    static NameOf(key) {
        names := Store.Setting("razerKeyNames", "")
        if (names is Map && names.Has(key["id"]))
            return names[key["id"]]
        return key["name"]
    }

    static SetName(key, name) {
        if !(Store.Settings.Get("razerKeyNames", "") is Map)
            Store.Settings["razerKeyNames"] := Map()
        ; a name belongs to one key only
        for k in Keyboard.Layout()["keys"]
            if (k["id"] != key["id"] && Keyboard.NameOf(k) = name)
                Store.Settings["razerKeyNames"][k["id"]] := "?" k["id"]
        Store.Settings["razerKeyNames"][key["id"]] := name
        Store.Save()
    }

    ; Keys the Razer script handles itself (before macros.ini is looked at).
    static SysShort := Map("Bind a key", "Bind", "Open macros.ini", "ini", "Reload script", "Reload",
        "Edit script", "Edit", "Cheat sheet", "Cheat", "Grab latest download", "Grab DL")

    static SystemKeys(scriptText) {
        known := Map("numpadAdd", "Bind a key", "plus", "Bind a key", "numpadDiv", "Open macros.ini",
            "minus", "Open macros.ini", "numpadMult", "Reload script", "F12", "Reload script",
            "F11", "Edit script", "NumLock", "Cheat sheet", "tilde", "Cheat sheet", "numpadDot", "Grab latest download")
        out := Map()
        for name, what in known
            if InStr(scriptText, '"' name '"')
                out[StrLower(name)] := what
        return out
    }

    static HasLiveDetection(item) {
        try return InStr(FileRead(item["path"]), "alcadeias-razer.ini") ? true : false
        return false
    }

    ; Adds two logging lines at the top of HandleKey() so Alcadeias can see
    ; which Razer key was pressed. Backed up first; reloads the script.
    static EnableLiveDetection(item) {
        path := item["path"]
        enc := Editor.DetectEncoding(path)
        text := FileRead(path, enc)
        if InStr(text, "alcadeias-razer.ini")
            return true
        if !RegExMatch(text, "m)^HandleKey\(key\)[ \t]*\R\{[^\r\n]*\R([ \t]*global[^\r\n]*\R)?", &m)
            return false
        nl := InStr(text, "`r`n") ? "`r`n" : "`n"
        add := "    IniWrite, %key%, %A_Temp%\alcadeias-razer.ini, last, key  `; Alcadeias: live key detection" nl
            . "    IniWrite, %A_TickCount%, %A_Temp%\alcadeias-razer.ini, last, t" nl
        text := SubStr(text, 1, m.Pos + m.Len - 1) add SubStr(text, m.Pos + m.Len)
        Scripts.Backup(item)
        f := FileOpen(path, "w", enc)
        f.Write(text)
        f.Close()
        Scripts.MarkSeen(item)
        Scripts.Apply(item, false)
        return true
    }

    ; Functions in the script you can bind with func|Name.
    static ScriptFunctions(scriptText) {
        skip := "|Receive_WM_COPYDATA|HandleKey|GetContext|RunSpec|QuickAssign|NavTo|GetActiveExplorerPath|CheatSheet|Tip|"
        out := []
        pos := 1
        while (pos := RegExMatch(scriptText, "m)^([A-Za-z_]\w*)\(\)\s*\R?\s*\{", &m, pos)) {
            if !InStr(skip, "|" m[1] "|")
                out.Push(m[1])
            pos += m.Len
        }
        return out
    }

    ; Short label shown on a key: "studio.youtube", "CLUK Content", "NewProject"…
    static Short(value, section, maxLen := 9) {
        p := KeyMap.Parse(value, section)
        t := p.target
        switch p.type {
            case "url":
                t := RegExReplace(t, "i)^https?://(www\.)?")
                t := RegExReplace(t, "[/?#].*$")
            case "folder", "run":
                t := Files.Name(Trim(RegExReplace(t, '^"([^"]*)".*$', "$1"), '"'))
            case "keys":
                t := Hotkeys.Pretty(t)
            case "text":
                t := '"' t
        }
        return StrLen(t) > maxLen ? SubStr(t, 1, maxLen - 1) "…" : t
    }
}

class KeyboardWindow {
    static U := 44        ; pixels per key unit
    static Gap := 4

    __New(item) {
        this.item := item
        this.ini := KeyMap.IniFor(item)
        this.ctx := "global"
        this.keys := Map()        ; hwnd -> key
        this.ctrls := Map()       ; key id -> ctrl
        this.hover := ""
        this.selected := ""
        this.learn := false
        this.pending := ""
        this.lastT := ""
        try this.lastT := IniRead(Keyboard.LiveFile, "last", "t", "")
        this.scriptText := ""
        try this.scriptText := FileRead(item["path"])
        this.sys := Keyboard.SystemKeys(this.scriptText)
        this.hasWarps := RegExMatch(this.scriptText, "numpad\(\\d\)") || InStr(this.scriptText, "[folders]") || InStr(this.scriptText, "folders,")

        U := KeyboardWindow.U, lay := Keyboard.Layout()
        winW := Round(lay["width"] * U) + 48
        g := Theme.NewGui("Key map — " item["name"], "-MinimizeBox")
        this.g := g
        Theme.DarkTitle(g)

        Theme.Label(g, "x24 y18 w600 h28", "Razer key map", Theme.Text, 14, true)
        this.liveLbl := Theme.Label(g, Format("x{} y22 w420 h22 Right", winW - 444), "", Theme.Muted, 9)

        ; context tabs
        this.tabs := []
        for i, c in Keyboard.Contexts {
            t := FlatButton(g, Format("x{} y58 w120 h32", 24 + (i - 1) * 124), c[2], this._CtxFn(c[1]), "tab")
            this.tabs.Push([c[1], t])
        }
        this.tabLine := g.Add("Text", "x24 y90 w120 h2 Background" Theme.Accent)

        ; the keyboard
        top := 108
        for key in lay["keys"] {
            x := 24 + Round(key["x"] * U), y := top + Round(key["y"] * U)
            w := Round(key["w"] * U) - KeyboardWindow.Gap, h := Round(key["h"] * U) - KeyboardWindow.Gap
            c := g.Add("Text", Format("x{} y{} w{} h{} Center Background{}", x, y, w, h, Theme.Panel), key["legend"])
            c.SetFont("s8 q5 c" Theme.Muted, Theme.Font)
            c.OnEvent("Click", this._KeyFn(key))
            this.keys[c.Hwnd] := key
            this.ctrls[key["id"]] := c
        }
        y := top + Round(lay["height"] * U) + 14

        ; legend
        lx := 24
        for x in [[Theme.Accent, "bound here"], [Theme.Panel2, "bound in another app"], ["3B3220", "built into the script"], ["1E3B37", "numpad folder warp"], [Theme.Panel, "free"]] {
            g.Add("Text", Format("x{} y{} w14 h14 Background{}", lx, y + 3, x[1]))
            Theme.Label(g, Format("x{} y{} w170 h20", lx + 20, y), x[2], Theme.Muted, 9)
            lx += 175
        }
        y += 32

        ; info panel
        Theme.Line(g, 24, y, winW - 48, Theme.Panel)
        y += 12
        this.infoTitle := Theme.Label(g, Format("x24 y{} w{} h26", y, winW - 48), "Hover a key to see what it does. Click it to change it.", Theme.Text, 11, true)
        this.infoBody := Theme.Label(g, Format("x24 y{} w{} h96", y + 30, winW - 48 - 300), "", Theme.Muted, 9)
        this.bAssign := FlatButton(g, Format("x{} y{} w140 h32", winW - 24 - 140, y + 30), "Change…", (*) => this.Assign(this.selected ? this.selected : this.hover))
        this.bName := FlatButton(g, Format("x{} y{} w140 h32", winW - 24 - 140, y + 70), "Key name…", (*) => this.RenameKey(this.selected ? this.selected : this.hover))
        this.bAssign.Visible := false, this.bName.Visible := false
        y += 132

        ; bottom bar
        Theme.Line(g, 0, y, winW, Theme.Panel)
        y += 14
        this.bLive := FlatButton(g, Format("x24 y{} w200 h34", y), "", (*) => this.LiveButton())
        FlatButton(g, Format("x232 y{} w110 h34", y), "List view", (*) => (KeyMap.OpenList(this.item), this.Refresh()))
        FlatButton(g, Format("x350 y{} w150 h34", y), "Open macros.ini", (*) => Run('notepad.exe "' this.ini '"'))
        FlatButton(g, Format("x{} y{} w110 h34", winW - 24 - 110, y), "Close", (*) => this.Close(), "accent")
        y += 34 + 18

        g.OnEvent("Close", (*) => this.Close())
        g.OnEvent("Escape", (*) => this.Close())
        this.mouseFn := ObjBindMethod(this, "_OnMouse")
        OnMessage(0x200, this.mouseFn)
        this.pollFn := ObjBindMethod(this, "_Poll")
        SetTimer(this.pollFn, 120)
        this.reloadFn := ObjBindMethod(this, "_ReloadScript")

        this.SetContext("global")
        this.UpdateLive()
        g.Show(Format("w{} h{}", winW, y))
    }

    _CtxFn(c) => (*) => this.SetContext(c)
    _KeyFn(key) => (*) => this.Click(key)

    SetContext(c) {
        this.ctx := c
        for t in this.tabs {
            t[2].SetActive(t[1] = c)
            if (t[1] = c) {
                t[2].ctrl.GetPos(&x, &y, &w, &h)
                this.tabLine.Move(x, y + h, w, 2)
                this.tabLine.Redraw()
            }
        }
        this.Refresh()
    }

    ; Reads macros.ini and repaints every key.
    Refresh() {
        this.bind := Map()
        for c in Keyboard.Contexts {
            m := Map()
            for e in KeyMap.Entries(this.ini, c[1])
                m[StrLower(e.key)] := e.value
            this.bind[c[1]] := m
        }
        this.warps := Map()
        for e in KeyMap.Entries(this.ini, "folders")
            this.warps[e.key] := e.value
        for key in Keyboard.Layout()["keys"]
            this.Paint(key)
        if this.hover
            this.ShowInfo(this.hover)
    }

    ; State of a key in the current context: [kind, label]
    State(key) {
        name := StrLower(Keyboard.NameOf(key))
        fit := Max(4, Floor((key["w"] * KeyboardWindow.U - KeyboardWindow.Gap) / 6.5))   ; chars that fit on one line
        if !key["bindable"]
            return ["off", ""]
        if RegExMatch(name, "^numpad(\d)$", &d) && this.hasWarps
            return this.warps.Has(d[1]) ? ["warp", KeyboardWindow._Cut(Files.Name(this.warps[d[1]]), fit)] : ["warp0", "warp"]
        if this.sys.Has(name)
            return ["sys", Keyboard.SysShort.Get(this.sys[name], this.sys[name])]
        if this.bind[this.ctx].Has(name)
            return ["here", Keyboard.Short(this.bind[this.ctx][name], this.ctx, fit)]
        for c in Keyboard.Contexts
            if (c[1] != this.ctx && this.bind[c[1]].Has(name))
                return ["other", Keyboard.Short(this.bind[c[1]][name], c[1], fit)]
        return ["free", ""]
    }

    static _Cut(t, n) => StrLen(t) > n ? SubStr(t, 1, n - 1) "…" : t

    Paint(key, flash := false) {
        c := this.ctrls[key["id"]]
        st := this.State(key)
        colors := Map("here", [Theme.Accent, "FFFFFF"], "other", [Theme.Panel2, Theme.AccentHi],
            "sys", ["3B3220", Theme.Warn], "warp", ["1E3B37", "7EE0C8"], "warp0", [Theme.Panel, "4F8F84"],
            "free", [Theme.Panel, Theme.Muted], "off", [Theme.Bg, "55565F"])
        col := colors[st[1]]
        bg := flash ? Theme.Ok : (this.selected && this.selected["id"] = key["id"]) ? Theme.AccentHi : col[1]
        fg := flash ? "000000" : col[2]
        label := st[2] != "" && key["h"] * KeyboardWindow.U >= 40 ? key["legend"] "`n" st[2] : key["legend"]
        if (c.Text != label)
            c.Text := label
        c.Opt("Background" bg)
        c.SetFont("c" fg)
        c.Redraw()
    }

    _OnMouse(wParam, lParam, msg, hwnd) {
        if !this.keys.Has(hwnd)
            return
        key := this.keys[hwnd]
        if (this.hover && this.hover["id"] = key["id"])
            return
        this.hover := key
        this.ShowInfo(key)
    }

    ShowInfo(key) {
        name := Keyboard.NameOf(key)
        lname := StrLower(name)
        title := (key["legend"] != "" ? key["legend"] : "Space") "     sends '" name "'"
        lines := ""
        if !key["bindable"]
            lines := "The Fn key is handled by the keyboard itself and can't be bound."
        else if RegExMatch(lname, "^numpad(\d)$", &d) && this.hasWarps
            lines := "Numpad folder warp " d[1] ": " (this.warps.Has(d[1]) ? this.warps[d[1]] : "(not set)") "`nWorks in Explorer and Save/Open dialogs, otherwise opens the folder."
        else if this.sys.Has(lname)
            lines := "Built into your Razer script: " this.sys[lname] "."
        else {
            for c in Keyboard.Contexts
                if this.bind[c[1]].Has(lname) {
                    p := KeyMap.Parse(this.bind[c[1]][lname], c[1])
                    lines .= (lines = "" ? "" : "`n") c[2] ":   " KeyMap.TypeLabel(p.type) "   " p.target
                }
            if (lines = "")
                lines := "Free in every app. Click to give it a job."
        }
        this.infoTitle.Text := title
        this.infoBody.Text := lines
        this.bAssign.Visible := key["bindable"] && !this.sys.Has(lname)
        this.bName.Visible := key["bindable"]
    }

    Click(key) {
        ; learn mode: "click the key you just pressed"
        if (this.pending != "") {
            Keyboard.SetName(key, this.pending)
            App.Status("'" key["legend"] "' now sends '" this.pending "'", "ok")
            this.pending := ""
            this.UpdateLive()
            this.Refresh()
            return
        }
        prev := this.selected
        this.selected := key
        if prev
            this.Paint(prev)
        this.Paint(key)
        this.ShowInfo(key)
        if !key["bindable"]
            return
        lname := StrLower(Keyboard.NameOf(key))
        if this.sys.Has(lname) {
            App.Status("'" key["legend"] "' is built into your Razer script (" this.sys[lname] ")", "warn")
            return
        }
        this.Assign(key)
    }

    ; Searchable list of everything this key could do.
    Assign(key) {
        if !key
            return
        name := Keyboard.NameOf(key)
        lname := StrLower(name)
        if RegExMatch(lname, "^numpad(\d)$", &d) && this.hasWarps {
            dest := Picker.Choose("Numpad " d[1] " jumps to…", "", this.g)
            if (dest != "") {
                IniWrite(dest, this.ini, "folders", d[1])
                this.Changed()
            }
            return
        }
        ctxName := ""
        for c in Keyboard.Contexts
            if (c[1] = this.ctx)
                ctxName := c[2]
        current := this.bind[this.ctx].Get(lname, "")
        choice := ActionPicker.Choose("'" (key["legend"] != "" ? key["legend"] : "Space") "' in " ctxName " does…", current, this.ctx, this.scriptText, this.g)
        if !choice
            return
        if (choice.type = "remove")
            IniDelete(this.ini, this.ctx, name)
        else
            IniWrite(KeyMap.Build(choice.type, choice.target, this.ctx), this.ini, this.ctx, name)
        this.Changed()
    }

    Changed() {
        this.Refresh()
        SetTimer(this.reloadFn, -700)
    }

    _ReloadScript() {
        if Scripts.IsRunning(this.item)
            Scripts.Apply(this.item, false)
    }

    RenameKey(key) {
        if !key
            return
        n := Dialogs.AskText("Key name", "What '" key["legend"] "' sends:", Keyboard.NameOf(key))
        if (n = "" || n = Keyboard.NameOf(key))
            return
        Keyboard.SetName(key, n)
        this.Refresh()
        this.ShowInfo(key)
    }

    ; ---- live key detection ------------------------------------------------

    UpdateLive() {
        if !Keyboard.HasLiveDetection(this.item) {
            this.bLive.Text := "Turn on live key detection"
            this.liveLbl.Text := "Live detection is off"
        } else if this.learn {
            this.bLive.Text := "Stop learning"
            this.liveLbl.SetFont("c" Theme.Warn)
            this.liveLbl.Text := this.pending != "" ? "Got '" this.pending "'. Now click that key on the picture." : "Learning: press each Razer key once…"
        } else {
            this.bLive.Text := "Learn key names"
            this.liveLbl.SetFont("c" Theme.Ok)
            this.liveLbl.Text := "Live: press a Razer key to find it here"
        }
    }

    LiveButton() {
        if !Keyboard.HasLiveDetection(this.item) {
            if (MsgBox("To see which Razer key you press, Alcadeias adds two small logging lines to the start of HandleKey() in '" this.item["name"] "'.`n`nThe current version is backed up first (Backups folder), and the script is reloaded. OK?", "Alcadeias", "OKCancel Icon? Owner" this.g.Hwnd) != "OK")
                return
            if !Keyboard.EnableLiveDetection(this.item) {
                MsgBox("Couldn't find HandleKey(key) in the script, so live detection can't be added automatically.", "Alcadeias", "Icon! Owner" this.g.Hwnd)
                return
            }
            App.Status("Live key detection is on", "ok")
        } else {
            this.learn := !this.learn
            this.pending := ""
        }
        this.UpdateLive()
    }

    _Poll() {
        t := ""
        try t := IniRead(Keyboard.LiveFile, "last", "t", "")
        if (t = "" || t = this.lastT)
            return
        this.lastT := t
        name := ""
        try name := IniRead(Keyboard.LiveFile, "last", "key", "")
        if (name = "")
            return
        for key in Keyboard.Layout()["keys"]
            if (Keyboard.NameOf(key) = name) {
                this.hover := key
                this.ShowInfo(key)
                this.Paint(key, true)
                SetTimer(ObjBindMethod(this, "Paint", key), -350)
                if this.learn {
                    this.liveLbl.Text := "That was '" key["legend"] "' (" name "). Press the next one…"
                }
                return
            }
        ; a name we don't know yet
        if this.learn {
            this.pending := name
            this.UpdateLive()
        } else
            App.Status("Razer sent '" name "', which isn't on the picture yet. Use Learn key names.", "warn")
    }

    Close() {
        SetTimer(this.pollFn, 0)
        OnMessage(0x200, this.mouseFn, 0)
        try Keyboard.Windows.Delete(this.item["id"])
        FlatButton.Forget(this.g)
        this.g.Destroy()
    }
}

; Search-as-you-type list of everything a key can do.
class ActionPicker {
    static Choose(title, current, ctx, scriptText, owner) {
        f := Form(title, owner, 780)
        if (current != "") {
            p := KeyMap.Parse(current, ctx)
            Theme.Label(f.g, Format("x24 y{} w732 h22", f.y), "Now: " KeyMap.TypeLabel(p.type) "   " p.target, Theme.AccentHi, 9)
            f.y += 28
        }
        q := Theme.Edit(f.g, Format("x24 y{} w732 h32", f.y))
        q.SetFont("s11")
        SendMessage(0xD3, 1, 10, q)
        Theme.Cue(q, "Search: layouts, projects, apps, folders, snippets, script functions, website…")
        f.y += 42
        lv := Theme.ListView(f.g, Format("x24 y{} w732 h380", f.y), ["Do", "Details"], 28)
        lv.ModifyCol(1, 300), lv.ModifyCol(2, 410)
        f.y += 390
        all := ActionPicker._All(current, scriptText)
        shown := []
        fill := () => ActionPicker._Fill(lv, all, shown, q.Value)
        q.OnEvent("Change", (*) => fill())
        result := ""
        pick := () => (
            r := lv.GetNext(0),
            r && r <= shown.Length ? (result := ActionPicker._Finish(shown[r], f), result ? f.Close(true) : 0) : 0)
        lv.OnEvent("DoubleClick", (*) => pick())
        f.Buttons(pick, "Choose")
        hwnd := f.g.Hwnd   ; the window is gone after ShowModal
        HotIfWinActive("ahk_id " hwnd)
        Hotkey("Up", (*) => Picker._Move(lv, -1), "On")
        Hotkey("Down", (*) => Picker._Move(lv, 1), "On")
        HotIf()
        fill()
        q.Focus()
        f.ShowModal()
        HotIfWinActive("ahk_id " hwnd)
        try Hotkey("Up", "Off")
        try Hotkey("Down", "Off")
        HotIf()
        return result
    }

    static _All(current, scriptText) {
        out := []
        if (current != "")
            out.Push({label: "Remove this binding", details: "the key goes back to doing nothing here", type: "remove", target: ""})
        for item in Store.Items
            if (item["type"] != "script")
                out.Push({label: Store.TypeNames[item["type"]] ": " item["name"], details: "Alcadeias item", type: "alcadeias", target: item["name"]})
        for fn in Keyboard.ScriptFunctions(scriptText)
            out.Push({label: "Script function: " fn, details: "built into the Razer script", type: "func", target: fn})
        for x in [["Website…", "type an address", "url"], ["Send keys…", "a shortcut, e.g. ^+e = Ctrl+Shift+E", "keys"],
                ["Type text…", "types the text you enter", "text"], ["Program or file…", "pick something to run", "run"],
                ["Any folder…", "pick a folder", "folder"]]
            out.Push({label: x[1], details: x[2], type: x[3], target: "", ask: true})
        seen := Map()
        for p in Projects.Recent(30) {
            r := Actions.Expand(p["root"])
            if (r != "" && !seen.Has(StrLower(r)))
                seen[StrLower(r)] := 1, out.Push({label: "Folder: " Files.Name(r), details: r, type: "folder", target: r})
        }
        for it in Store.OfType("folder") {
            r := Actions.Expand(it["path"])
            if !seen.Has(StrLower(r))
                seen[StrLower(r)] := 1, out.Push({label: "Folder: " Files.Name(r), details: r, type: "folder", target: r})
        }
        for pl in Places.Top(25, "", "dir")
            if !seen.Has(StrLower(pl["path"]))
                seen[StrLower(pl["path"])] := 1, out.Push({label: "Folder: " Files.Name(pl["path"]), details: pl["path"], type: "folder", target: pl["path"]})
        return out
    }

    static _Fill(lv, all, shown, query) {
        q := Trim(StrLower(query))
        tokens := q = "" ? "" : StrSplit(RegExReplace(q, "\s+", " "), " ")
        shown.Length := 0
        lv.Opt("-Redraw")
        lv.Delete()
        for x in all {
            if tokens && !Files.MatchAll(StrLower(x.label " " x.details), tokens)
                continue
            shown.Push(x)
            lv.Add(, x.label, x.details)
        }
        ; typed something that looks like a web address or folder: offer it directly
        t := Trim(query)
        if RegExMatch(t, "i)^(https?://|www\.)") {
            shown.InsertAt(1, {label: "Website: " t, details: "open this address", type: "url", target: RegExMatch(t, "i)^https?://") ? t : "https://" t})
            lv.Insert(1, , "Website: " t, "open this address")
        } else if (RegExMatch(t, "^[A-Za-z]:\\") && DirExist(t)) {
            shown.InsertAt(1, {label: "Folder: " t, details: t, type: "folder", target: t})
            lv.Insert(1, , "Folder: " Files.Name(t), t)
        }
        lv.Opt("+Redraw")
        if shown.Length
            lv.Modify(1, "Select Focus Vis")
    }

    ; Asks for the missing part (address, keys, text, file, folder) if needed.
    static _Finish(x, f) {
        if !x.HasOwnProp("ask")
            return x
        switch x.type {
            case "url":
                v := Dialogs.AskText("Website", "Address:", "https://")
                if (v = "" || v = "https://")
                    return ""
            case "keys":
                v := Dialogs.AskText("Send keys", "Keys (AutoHotkey style, e.g. ^+e):", "")
            case "text":
                v := Dialogs.AskText("Type text", "Text:", "")
            case "run":
                v := FileSelect(3, , "Pick a program or file")
            case "folder":
                v := Picker.Choose("Pick a folder", "", f.g)
        }
        return v != "" ? {type: x.type, target: v} : ""
    }
}
