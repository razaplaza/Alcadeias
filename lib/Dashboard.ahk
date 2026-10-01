; The main window: categories on the left, one searchable list of everything,
; actions along the bottom. Ctrl+Alt+D shows/hides it.

class Dashboard {
    static g := ""
    static lv := ""
    static search := ""
    static nav := Map()
    static category := "all"
    static rowIds := []
    static prevWindow := 0
    static btn := Map()
    static primaryAction := ""
    static secondaryAction := ""
    static tertiaryAction := ""
    static _refreshPending := false

    static Categories := [
        ["all", "All"], ["script", "Scripts"], ["layout", "Layouts"],
        ["app", "Apps"], ["folder", "Folders"], ["link", "Links"]
    ]

    static Build() {
        g := Theme.NewGui("Alcadeias", "+Resize +MinSize820x520")
        Dashboard.g := g
        Theme.DarkTitle(g)

        Dashboard.title := Theme.Label(g, "x24 y14 w300 h34", "Alcadeias", Theme.Text, 18, true)
        Dashboard.summary := Theme.Label(g, "x26 y50 w600 h20", "", Theme.Muted, 9)
        Dashboard.summary.OnEvent("Click", (*) => Dashboard.ShowProblems())
        Dashboard.btn["settings"] := FlatButton(g, "x0 y20 w120 h36", "Settings", (*) => Dialogs.Settings())
        Dashboard.btn["help"] := FlatButton(g, "x0 y20 w40 h36", "?", (*) => Dashboard.ShowHelp())
        Dashboard.topLine := Theme.Line(g, 0, 84, 100, Theme.Panel)

        for i, c in Dashboard.Categories {
            key := c[1]
            b := FlatButton(g, Format("x16 y{} w168 h38", 100 + (i - 1) * 42), "", Dashboard._NavFn(key), "nav")
            b.ctrl.Opt("-Center")
            Dashboard.nav[key] := b
        }
        Dashboard.tips := Theme.Label(g, "x24 y0 w160 h120", "", Theme.Muted, 8)
        Dashboard.tips.Text := "Ctrl+Alt+D  show / hide`nType  to search`nUp/Down  pick   Enter  run`nF2  edit   Ctrl+N  new`nEsc  clear / hide"

        Dashboard.search := Theme.Edit(g, "x200 y100 w600 h32")
        Dashboard.search.SetFont("s11")
        Theme.Cue(Dashboard.search, "Search everything — scripts, layouts, apps, folders, links, hotkeys…")
        SendMessage(0xD3, 1, 12, Dashboard.search)   ; EM_SETMARGINS left padding
        Dashboard.search.OnEvent("Change", (*) => Dashboard.Refresh())

        lv := Theme.ListView(g, "x200 y144 w600 h300", ["Hotkey", "Name", "Type", "Status", "Details"])
        Dashboard.lv := lv
        lv.OnEvent("ItemSelect", (*) => Dashboard.UpdateButtons())
        lv.OnEvent("DoubleClick", (*) => Dashboard.RunSelected())
        lv.OnEvent("ContextMenu", (ctrl, row, *) => Dashboard.ContextMenu(row))

        Dashboard.btn["new"] := FlatButton(g, "x0 y0 w96 h36", "+  New", (*) => Dashboard.NewItem(), "accent")
        Dashboard.btn["edit"] := FlatButton(g, "x0 y0 w84 h36", "Edit", (*) => Dashboard.EditSelected())
        Dashboard.btn["delete"] := FlatButton(g, "x0 y0 w92 h36", "Delete", (*) => Dashboard.DeleteSelected(), "danger")
        Dashboard.btn["p3"] := FlatButton(g, "x0 y0 w110 h36", "", (*) => Dashboard._Do("tertiary"))
        Dashboard.btn["p2"] := FlatButton(g, "x0 y0 w110 h36", "", (*) => Dashboard._Do("secondary"))
        Dashboard.btn["p1"] := FlatButton(g, "x0 y0 w130 h36", "", (*) => Dashboard._Do("primary"), "accent")

        Dashboard.statusText := Theme.Label(g, "x200 y0 w600 h20", "Ready", Theme.Muted, 9)

        g.OnEvent("Size", (g, mm, w, h) => mm != -1 ? Dashboard.Layout(w, h) : 0)
        g.OnEvent("Escape", (*) => Dashboard.Escape())

        ; keys that only apply while the dashboard is in front
        HotIf((*) => Dashboard.IsActive() && !WinExist("ahk_class #32768"))
        Hotkey("Enter", (*) => Dashboard.RunSelected())
        Hotkey("NumpadEnter", (*) => Dashboard.RunSelected())
        Hotkey("Up", (*) => Dashboard.MoveSel(-1))
        Hotkey("Down", (*) => Dashboard.MoveSel(1))
        Hotkey("PgUp", (*) => Dashboard.MoveSel(-8))
        Hotkey("PgDn", (*) => Dashboard.MoveSel(8))
        Hotkey("^f", (*) => Dashboard.FocusSearch())
        Hotkey("^n", (*) => Dashboard.NewItem())
        Hotkey("F2", (*) => Dashboard.EditSelected())
        Hotkey("^e", (*) => Dashboard.EditSelected())
        Hotkey("$Delete", (*) => Dashboard.DeleteKey())
        Loop Dashboard.Categories.Length
            Hotkey("^" A_Index, Dashboard._NavFn(Dashboard.Categories[A_Index][1]))
        HotIf()

        Dashboard.SetCategory("all", false)
        Dashboard.Refresh()
        SetTimer(() => Dashboard.Tick(), 1500)
    }

    static IsActive() => Dashboard.g && WinActive("ahk_id " Dashboard.g.Hwnd)
    static IsVisible() => Dashboard.g && DllCall("IsWindowVisible", "Ptr", Dashboard.g.Hwnd)

    static Show() {
        if !Dashboard.g
            Dashboard.Build()
        active := WinExist("A")
        if (active && active != Dashboard.g.Hwnd)
            Dashboard.prevWindow := active
        Dashboard.Refresh()
        if !Dashboard._shownOnce {
            Dashboard.g.Show("w1080 h680 Center")
            Dashboard._shownOnce := true
        } else
            Dashboard.g.Show()
        WinActivate(Dashboard.g)
        Dashboard.FocusSearch()
    }
    static _shownOnce := false

    static Hide() {
        if Dashboard.g
            Dashboard.g.Hide()
    }

    static Toggle() {
        if Dashboard.IsActive()
            Dashboard.Hide()
        else
            Dashboard.Show()
    }

    static Escape() {
        if (Dashboard.search.Value != "") {
            Dashboard.search.Value := ""
            Dashboard.Refresh()
            Dashboard.FocusSearch()
        } else
            Dashboard.Hide()
    }

    static FocusSearch() {
        Dashboard.search.Focus()
        SendMessage(0xB1, 0, -1, Dashboard.search)   ; select all
    }

    ; ---- layout ----------------------------------------------------------

    static Layout(w, h) {
        Dashboard.btn["settings"].Move(w - 24 - 120, 22)
        Dashboard.btn["help"].Move(w - 24 - 120 - 8 - 40, 22)
        Dashboard.topLine.Move(0, 84, w)
        Dashboard.tips.Move(24, h - 130)
        cx := 200, cw := w - cx - 20
        Dashboard.search.Move(cx, 100, cw, 32)
        lvh := h - 144 - 100
        Dashboard.lv.Move(cx, 144, cw, lvh)
        by := h - 92
        Dashboard.btn["new"].Move(cx, by)
        Dashboard.btn["edit"].Move(cx + 104, by)
        Dashboard.btn["delete"].Move(cx + 196, by)
        rx := cx + cw
        Dashboard.btn["p1"].Move(rx - 130, by)
        Dashboard.btn["p2"].Move(rx - 130 - 8 - 110, by)
        Dashboard.btn["p3"].Move(rx - 130 - 8 - 110 - 8 - 110, by)
        Dashboard.statusText.Move(cx, h - 40, cw)
        ; columns: fixed widths, Details takes the rest
        fixed := 130 + 220 + 70 + 110
        Dashboard.lv.ModifyCol(1, 130), Dashboard.lv.ModifyCol(2, 220)
        Dashboard.lv.ModifyCol(3, 70), Dashboard.lv.ModifyCol(4, 110)
        Dashboard.lv.ModifyCol(5, Max(120, cw - fixed - 24))
        for b in FlatButton.Registry
            try FlatButton.Registry[b].ctrl.Redraw()
    }

    ; ---- list ------------------------------------------------------------

    static SetCategory(key, refresh := true) {
        Dashboard.category := key
        for k, b in Dashboard.nav
            b.SetActive(k = key)
        if refresh {
            Dashboard.Refresh()
            Dashboard.FocusSearch()
        }
    }

    static _NavFn(key) => (*) => Dashboard.SetCategory(key)

    static Refresh() {
        if !Dashboard.g
            return
        Dashboard._refreshPending := false
        lv := Dashboard.lv
        selId := Dashboard.SelectedId()
        q := Trim(StrLower(Dashboard.search.Value))
        tokens := q = "" ? [] : StrSplit(RegExReplace(q, "\s+", " "), " ")
        running := Scripts.Running()

        ; nav counts
        counts := Map("all", Store.Items.Length)
        for t in Store.Types
            counts[t] := 0
        for item in Store.Items
            counts[item["type"]] := counts.Get(item["type"], 0) + 1
        for c in Dashboard.Categories
            Dashboard.nav[c[1]].Text := "   " c[2] "   " (counts[c[1]] ? counts[c[1]] : "")

        ; filter + score
        rows := []
        typeOrder := Map("layout", 1, "app", 2, "folder", 3, "link", 4, "script", 5)
        for item in Store.Items {
            if (Dashboard.category != "all" && item["type"] != Dashboard.category)
                continue
            details := Dashboard.Details(item)
            if tokens.Length {
                hay := StrLower(item["name"] " " item["type"] " " Hotkeys.Pretty(item["hotkey"]) " " item["hotkey"] " " details)
                ok := true
                for t in tokens
                    if !InStr(hay, t) {
                        ok := false
                        break
                    }
                if !ok
                    continue
                n := StrLower(item["name"])
                score := InStr(n, q) = 1 ? 0 : InStr(n, q) ? 1 : InStr(n, tokens[1]) ? 2 : 3
            } else
                score := typeOrder.Get(item["type"], 9)
            rows.Push({item: item, details: details, key: Format("{:02}", score) StrLower(item["name"])})
        }
        ; sort by key (simple insertion sort, lists are small)
        Loop rows.Length - 1 {
            i := A_Index + 1
            r := rows[i], j := i - 1
            while (j >= 1 && StrCompare(rows[j].key, r.key) > 0) {
                rows[j + 1] := rows[j]
                j--
            }
            rows[j + 1] := r
        }

        lv.Opt("-Redraw")
        lv.Delete()
        Dashboard.rowIds := []
        selRow := 0
        for r in rows {
            item := r.item
            lv.Add(, Hotkeys.Pretty(item["hotkey"]), item["name"], Store.TypeNames[item["type"]],
                Dashboard.StatusOf(item, running), r.details)
            Dashboard.rowIds.Push(item["id"])
            if (item["id"] = selId)
                selRow := A_Index
        }
        if !rows.Length {
            msg := tokens.Length ? "No matches for '" Dashboard.search.Value "'"
                : "Nothing here yet. Press + New (Ctrl+N) to add one."
            lv.Add(, "", msg)
            Dashboard.rowIds.Push("")
        }
        lv.Opt("+Redraw")
        if (!selRow && rows.Length)
            selRow := 1
        if selRow
            lv.Modify(selRow, "Select Focus Vis")
        Dashboard.UpdateButtons()
        Dashboard.UpdateSummary(running)
    }

    static RefreshSoon() {
        if Dashboard.g && !Dashboard._refreshPending {
            Dashboard._refreshPending := true
            SetTimer(() => Dashboard.Refresh(), -50)
        }
    }

    static Details(item) {
        switch item["type"] {
            case "script":
                hks := ""
                for h in Hotkeys.FromScript(item["path"])
                    hks .= (hks = "" ? "" : ", ") Hotkeys.Pretty(h.hk) (h.ctx != "" ? " (" h.ctx ")" : "")
                SplitPath(item["path"], &fileName)
                return "v" Scripts.Version(item) " · " fileName (hks != "" ? " · " hks : "")
            case "layout":
                s := ""
                for slot in item["slots"]
                    s .= (s = "" ? "" : "   |   ") Layouts.SlotText(slot)
                return s
            case "app":
                return item["exe"] (item["title"] != "" ? " · '" item["title"] "'" : "")
            case "folder":
                return item["path"]
            case "link":
                return item["target"]
        }
        return ""
    }

    static StatusOf(item, running) {
        switch item["type"] {
            case "script":
                if running.Has(StrLower(item["path"]))
                    return "● Running"
                if !FileExist(item["path"])
                    return "! File missing"
                if Scripts.LastError.Has(item["id"])
                    return "! Error"
                return "○ Stopped"
            case "layout":
                n := item["slots"].Length
                return n " window" (n = 1 ? "" : "s")
        }
        return ""
    }

    ; Every 1.5s while visible: refresh running/stopped dots.
    static Tick() {
        if !Dashboard.IsVisible()
            return
        running := Scripts.Running()
        Loop Dashboard.rowIds.Length {
            id := Dashboard.rowIds[A_Index]
            if (id = "")
                continue
            item := Store.ById(id)
            if !item || item["type"] != "script"
                continue
            s := Dashboard.StatusOf(item, running)
            if (Dashboard.lv.GetText(A_Index, 4) != s)
                Dashboard.lv.Modify(A_Index, "Col4", s)
        }
        Dashboard.UpdateSummary(running)
        Dashboard.UpdateButtons()
    }

    static UpdateSummary(running) {
        n := 0
        for item in Store.OfType("script")
            if running.Has(StrLower(item["path"]))
                n++
        s := n " script" (n = 1 ? "" : "s") " running  ·  " Hotkeys.Active.Count " hotkeys active"
        if Hotkeys.Errors.Length
            s .= "  ·  ! " Hotkeys.Errors.Length " hotkey problem" (Hotkeys.Errors.Length = 1 ? "" : "s") " (click)"
        if (Dashboard.summary.Text != s)
            Dashboard.summary.Text := s
    }

    static ShowProblems() {
        if !Hotkeys.Errors.Length
            return
        t := ""
        for e in Hotkeys.Errors
            t .= "• " e "`n"
        MsgBox(t, "Alcadeias — hotkey problems", "Icon!")
    }

    static ShowHelp() {
        MsgBox("
        (
        Ctrl+Alt+D          show / hide Alcadeias (change in Settings)

        In the dashboard:
          type                 search everything
          Up Down PgUp PgDn    pick a row
          Enter / dbl-click    run it (scripts open in the editor)
          F2 or Ctrl+E         edit the selected item
          Ctrl+N               new item
          Delete               remove the selected item
          Ctrl+1 … Ctrl+6      switch category
          Esc                  clear search, then hide

        In the script editor:
          Ctrl+S               save, check for errors, swap in the new version
          Ctrl+G               go to line

        A script's own hotkey (set via Edit) turns that script on/off.
        )", "Alcadeias — keys")
    }

    ; ---- selection & actions ---------------------------------------------

    static SelectedId() {
        if !Dashboard.lv
            return ""
        row := Dashboard.lv.GetNext(0)
        return (row && row <= Dashboard.rowIds.Length) ? Dashboard.rowIds[row] : ""
    }

    static SelectedItem() {
        id := Dashboard.SelectedId()
        return id != "" ? Store.ById(id) : ""
    }

    static MoveSel(delta) {
        lv := Dashboard.lv
        n := lv.GetCount()
        if !n
            return
        row := lv.GetNext(0)
        row := Max(1, Min(n, (row ? row : 0) + delta))
        lv.Modify(0, "-Select")
        lv.Modify(row, "Select Focus Vis")
    }

    static UpdateButtons() {
        item := Dashboard.SelectedItem()
        has := item != ""
        Dashboard.btn["edit"].Visible := has
        Dashboard.btn["delete"].Visible := has
        p1 := "", p2 := "", p3 := ""
        Dashboard.primaryAction := "", Dashboard.secondaryAction := "", Dashboard.tertiaryAction := ""
        if has {
            switch item["type"] {
                case "script":
                    running := Scripts.IsRunning(item)
                    p1 := "Edit code", Dashboard.primaryAction := () => Editor.Open(item)
                    p2 := running ? "Reload" : "Start", Dashboard.secondaryAction := () => (Scripts.Apply(item), Dashboard.RefreshSoon())
                    if running
                        p3 := "Stop", Dashboard.tertiaryAction := () => (Scripts.Stop(item), App.Status("Stopped '" item["name"] "'", "ok"), Dashboard.RefreshSoon())
                case "layout":
                    p1 := "Apply", Dashboard.primaryAction := () => Dashboard.RunSelected()
                    p2 := "Preview", Dashboard.secondaryAction := () => Layouts.Preview(item["slots"])
                case "app":
                    p1 := "Focus / open", Dashboard.primaryAction := () => Dashboard.RunSelected()
                case "folder":
                    p1 := "Open", Dashboard.primaryAction := () => Dashboard.RunSelected()
                case "link":
                    p1 := "Open", Dashboard.primaryAction := () => Dashboard.RunSelected()
            }
        }
        for k, v in Map("p1", p1, "p2", p2, "p3", p3) {
            b := Dashboard.btn[k]
            if (b.Text != v)
                b.Text := v
            b.Visible := v != ""
        }
    }

    static _Do(which) {
        switch which {
            case "primary":   fn := Dashboard.primaryAction
            case "secondary": fn := Dashboard.secondaryAction
            default:          fn := Dashboard.tertiaryAction
        }
        if fn
            fn.Call()
    }

    static RunSelected() {
        item := Dashboard.SelectedItem()
        if !item
            return
        if (item["type"] = "script") {
            Editor.Open(item)
            return
        }
        target := Dashboard.prevWindow
        Dashboard.Hide()
        if (target && WinExist(target)) {
            try WinActivate(target)
            WinWaitActive(target, , 0.5)
        }
        Actions.Run(item, target)
    }

    static NewItem() {
        cat := Dashboard.category
        if (cat = "script") {
            m := Menu()
            m.Add("New script…", (*) => Dialogs.NewScript())
            m.Add("Add existing .ahk files…", (*) => Dialogs.AddExistingScripts())
            m.Show()
            return
        }
        if (cat != "all") {
            Dialogs.EditItem(Store.NewItem(cat), true)
            return
        }
        m := Menu()
        m.Add("Layout…", (*) => Dialogs.EditItem(Store.NewItem("layout"), true))
        m.Add("App (focus or launch)…", (*) => Dialogs.EditItem(Store.NewItem("app"), true))
        m.Add("Folder…", (*) => Dialogs.EditItem(Store.NewItem("folder"), true))
        m.Add("Link / file / command…", (*) => Dialogs.EditItem(Store.NewItem("link"), true))
        m.Add()
        m.Add("New script…", (*) => Dialogs.NewScript())
        m.Add("Add existing .ahk files…", (*) => Dialogs.AddExistingScripts())
        m.Show()
    }

    static EditSelected() {
        item := Dashboard.SelectedItem()
        if item
            Dialogs.EditItem(item, false)
    }

    static DeleteKey() {
        ; Delete in the search box deletes text, not items
        if (ControlGetFocus(Dashboard.g) = Dashboard.search.Hwnd) {
            Send("{Delete}")
            return
        }
        Dashboard.DeleteSelected()
    }

    static DeleteSelected() {
        item := Dashboard.SelectedItem()
        if !item
            return
        extra := item["type"] = "script" ? "`n`nThe .ahk file stays on disk, and if the script is running it keeps running." : ""
        if (MsgBox("Remove " StrLower(Store.TypeNames[item["type"]]) " '" item["name"] "' from Alcadeias?" extra,
                "Alcadeias", "YesNo Icon? Default2 Owner" Dashboard.g.Hwnd) != "Yes")
            return
        Store.Remove(item["id"])
        Hotkeys.Rebuild()
        Dashboard.Refresh()
        App.Status("Removed '" item["name"] "'", "ok")
    }

    static ContextMenu(row) {
        if (!row || row > Dashboard.rowIds.Length || Dashboard.rowIds[row] = "")
            return
        Dashboard.lv.Modify(0, "-Select")
        Dashboard.lv.Modify(row, "Select Focus")
        item := Dashboard.SelectedItem()
        m := Menu()
        if (item["type"] = "script") {
            m.Add("Open in editor", (*) => Editor.Open(item))
            m.Add("Open in external editor", (*) => Editor.External(item))
            m.Add(Scripts.IsRunning(item) ? "Reload" : "Start", (*) => (Scripts.Apply(item), Dashboard.RefreshSoon()))
            if Scripts.IsRunning(item)
                m.Add("Stop", (*) => (Scripts.Stop(item), Dashboard.RefreshSoon()))
            m.Add("Show file in Explorer", (*) => Run('explorer.exe /select,"' item["path"] '"'))
            m.Add("Open backups folder", (*) => (DirCreate(Scripts.BackupDir(item)), Run('explorer.exe "' Scripts.BackupDir(item) '"')))
        } else {
            m.Add("Run", (*) => Dashboard.RunSelected())
            if (item["type"] = "layout")
                m.Add("Preview zones", (*) => Layouts.Preview(item["slots"]))
        }
        m.Add()
        m.Add("Edit…", (*) => Dialogs.EditItem(item, false))
        m.Add("Duplicate", (*) => Dashboard.Duplicate(item))
        m.Add("Remove", (*) => Dashboard.DeleteSelected())
        m.Show()
    }

    static Duplicate(item) {
        c := Store.Clone(item)
        c["id"] := Store.NewId()
        c["name"] := item["name"] " (copy)"
        c["hotkey"] := ""
        Store.Add(c)
        Dashboard.Refresh()
    }
}
