; The main window: categories on the left, one searchable list, actions along
; the bottom. Ctrl+Alt+D shows/hides it.
;
; The list holds "rows" from several sources: your items (projects, layouts,
; scripts, shortcuts), auto-remembered places, whole-PC search (Everything),
; folder contents while browsing, and the inbox (Downloads/Desktop).

class Dashboard {
    static g := ""
    static lv := ""
    static search := ""
    static nav := Map()
    static category := "all"
    static rows := []
    static browse := ""          ; folder being browsed, "" = not browsing
    static prevWindow := 0
    static btn := Map()
    static actions := Map()
    static _refreshPending := false
    static _inboxCount := 0
    static _ticks := 0

    static Categories := [
        ["all", "Home"], ["projects", "Projects"], ["files", "Files"], ["inbox", "Inbox"],
        ["layouts", "Layouts"], ["scripts", "Scripts"], ["shortcuts", "Apps && links"]
    ]
    static CatTypes := Map("projects", ["project", "template"], "layouts", ["layout"],
        "scripts", ["script"], "shortcuts", ["app", "folder", "link"])

    static Build() {
        g := Theme.NewGui("Alcadeias", "+Resize +MinSize860x540")
        Dashboard.g := g
        Theme.DarkTitle(g)

        Dashboard.title := Theme.Label(g, "x24 y14 w300 h34", "Alcadeias", Theme.Text, 18, true)
        Dashboard.summary := Theme.Label(g, "x26 y50 w700 h20", "", Theme.Muted, 9)
        Dashboard.summary.OnEvent("Click", (*) => Dashboard.ShowProblems())
        Dashboard.btn["settings"] := FlatButton(g, "x0 y20 w120 h36", "Settings", (*) => Dialogs.Settings())
        Dashboard.btn["help"] := FlatButton(g, "x0 y20 w40 h36", "?", (*) => Dashboard.ShowHelp())
        Dashboard.topLine := Theme.Line(g, 0, 84, 100, Theme.Panel)

        for i, c in Dashboard.Categories {
            b := FlatButton(g, Format("x16 y{} w168 h36", 100 + (i - 1) * 40), "", Dashboard._NavFn(c[1]), "nav")
            b.ctrl.Opt("-Center")
            Dashboard.nav[c[1]] := b
        }
        Dashboard.tips := Theme.Label(g, "x24 y0 w165 h140", "", Theme.Muted, 8)
        Dashboard.tips.Text := "Type  search all`nEnter  open   Tab  inside`nBackspace  up a folder`nCtrl+M  move   Ctrl+Z  undo`nF2  edit / rename`nCtrl+N  new   Esc  back"

        Dashboard.search := Theme.Edit(g, "x200 y100 w600 h32")
        Dashboard.search.SetFont("s11")
        SendMessage(0xD3, 1, 12, Dashboard.search)
        Dashboard.search.OnEvent("Change", (*) => Dashboard.RefreshSoon(90))

        lv := Theme.ListView(g, "x200 y144 w600 h300", ["Key", "Name", "Type", "Status", "Details"], 30, true)
        Dashboard.lv := lv
        lv.OnEvent("ItemSelect", (*) => Dashboard.UpdateButtons())
        lv.OnEvent("DoubleClick", (*) => Dashboard.RunSelected())
        lv.OnEvent("ContextMenu", (ctrl, row, *) => Dashboard.ContextMenu(row))

        Dashboard.btn["new"] := FlatButton(g, "x0 y0 w96 h36", "+  New", (*) => Dashboard.NewItem(), "accent")
        Dashboard.btn["edit"] := FlatButton(g, "x0 y0 w84 h36", "Edit", (*) => Dashboard.EditSelected())
        Dashboard.btn["delete"] := FlatButton(g, "x0 y0 w92 h36", "Delete", (*) => Dashboard.DeleteSelected(), "danger")
        Dashboard.btn["p3"] := FlatButton(g, "x0 y0 w124 h36", "", (*) => Dashboard._Do("p3"))
        Dashboard.btn["p2"] := FlatButton(g, "x0 y0 w124 h36", "", (*) => Dashboard._Do("p2"))
        Dashboard.btn["p1"] := FlatButton(g, "x0 y0 w140 h36", "", (*) => Dashboard._Do("p1"), "accent")

        Dashboard.statusText := Theme.Label(g, "x200 y0 w600 h20", "Ready", Theme.Muted, 9)

        g.OnEvent("Size", (g, mm, w, h) => mm != -1 ? Dashboard.Layout(w, h) : 0)
        g.OnEvent("Escape", (*) => Dashboard.Escape())

        HotIf((*) => Dashboard.IsActive() && !WinExist("ahk_class #32768"))
        Hotkey("Enter", (*) => Dashboard.RunSelected())
        Hotkey("NumpadEnter", (*) => Dashboard.RunSelected())
        Hotkey("Up", (*) => Dashboard.MoveSel(-1))
        Hotkey("Down", (*) => Dashboard.MoveSel(1))
        Hotkey("+Up", (*) => Dashboard.MoveSel(-1, true))
        Hotkey("+Down", (*) => Dashboard.MoveSel(1, true))
        Hotkey("PgUp", (*) => Dashboard.MoveSel(-10))
        Hotkey("PgDn", (*) => Dashboard.MoveSel(10))
        Hotkey("Tab", (*) => Dashboard.BrowseInto())
        Hotkey("$Backspace", (*) => Dashboard.BackspaceKey())
        Hotkey("^f", (*) => Dashboard.FocusSearch())
        Hotkey("^n", (*) => Dashboard.NewItem())
        Hotkey("^m", (*) => Dashboard.MoveSelected())
        Hotkey("$^z", (*) => Dashboard.UndoKey())
        Hotkey("^+c", (*) => Dashboard.CopySelectedPaths())
        Hotkey("^r", (*) => Dashboard.RevealSelected())
        Hotkey("F2", (*) => Dashboard.EditSelected())
        Hotkey("^e", (*) => Dashboard.EditSelected())
        Hotkey("$Delete", (*) => Dashboard.DeleteKey())
        Loop Dashboard.Categories.Length
            Hotkey("^" A_Index, Dashboard._NavFn(Dashboard.Categories[A_Index][1]))
        HotIf()

        Dashboard._inboxCount := Files.InboxCount()
        Dashboard.SetCategory("all", false)
        Dashboard.Refresh()
        SetTimer(() => Dashboard.Tick(), 1500)
    }

    static IsActive() => Dashboard.g && WinActive("ahk_id " Dashboard.g.Hwnd)
    static IsVisible() => Dashboard.g && DllCall("IsWindowVisible", "Ptr", Dashboard.g.Hwnd)
    static SearchFocused() => ControlGetFocus(Dashboard.g) = Dashboard.search.Hwnd

    static Show() {
        if !Dashboard.g
            Dashboard.Build()
        active := WinExist("A")
        if (active && active != Dashboard.g.Hwnd)
            Dashboard.prevWindow := active
        Dashboard._inboxCount := Files.InboxCount()
        Dashboard.Refresh()
        if !Dashboard._shownOnce {
            Dashboard.g.Show("w1120 h700 Center")
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
        } else if (Dashboard.browse != "")
            Dashboard.ExitBrowse()
        else
            Dashboard.Hide()
    }

    static FocusSearch() {
        Dashboard.search.Focus()
        SendMessage(0xB1, 0, -1, Dashboard.search)
    }

    ; ---- layout ----------------------------------------------------------

    static Layout(w, h) {
        Dashboard.btn["settings"].Move(w - 24 - 120, 22)
        Dashboard.btn["help"].Move(w - 24 - 120 - 8 - 40, 22)
        Dashboard.topLine.Move(0, 84, w)
        Dashboard.tips.Move(24, h - 150)
        cx := 200, cw := w - cx - 20
        Dashboard.search.Move(cx, 100, cw, 32)
        Dashboard.lv.Move(cx, 144, cw, h - 144 - 100)
        by := h - 92
        Dashboard.btn["new"].Move(cx, by)
        Dashboard.btn["edit"].Move(cx + 104, by)
        Dashboard.btn["delete"].Move(cx + 196, by)
        rx := cx + cw
        Dashboard.btn["p1"].Move(rx - 140, by)
        Dashboard.btn["p2"].Move(rx - 140 - 8 - 124, by)
        Dashboard.btn["p3"].Move(rx - 140 - 8 - 124 - 8 - 124, by)
        Dashboard.statusText.Move(cx, h - 40, cw)
        fixed := 110 + 250 + 70 + 90
        Dashboard.lv.ModifyCol(1, 110), Dashboard.lv.ModifyCol(2, 250)
        Dashboard.lv.ModifyCol(3, 70), Dashboard.lv.ModifyCol(4, 90)
        Dashboard.lv.ModifyCol(5, Max(120, cw - fixed - 24))
        for b in FlatButton.Registry
            try FlatButton.Registry[b].ctrl.Redraw()
    }

    ; ---- categories & browsing -------------------------------------------

    static SetCategory(key, refresh := true) {
        Dashboard.category := key
        Dashboard.browse := ""
        for k, b in Dashboard.nav
            b.SetActive(k = key)
        if refresh {
            Dashboard.search.Value := ""
            Dashboard.Refresh()
            Dashboard.FocusSearch()
        }
    }

    static _NavFn(key) => (*) => Dashboard.SetCategory(key)

    static BrowseTo(path) {
        if !DirExist(path)
            return
        Dashboard.browse := RTrim(path, "\") (StrLen(RTrim(path, "\")) = 2 ? "\" : "")
        Places.Visit(Dashboard.browse)
        Dashboard.search.Value := ""
        Dashboard.Refresh()
        Dashboard.FocusSearch()
    }

    static BrowseInto() {
        r := Dashboard.SelectedRow()
        if !r
            return
        p := Dashboard.RowFolder(r)
        if (p != "")
            Dashboard.BrowseTo(p)
    }

    static BrowseUp() {
        if (Dashboard.browse = "")
            return
        cur := Dashboard.browse
        parent := Files.Parent(cur)
        if (parent = "" || parent = cur) {
            Dashboard.ExitBrowse()
            return
        }
        Dashboard.BrowseTo(parent)
        ; keep the folder we came from selected
        for i, r in Dashboard.rows
            if (r.HasOwnProp("path") && StrLower(r.path) = StrLower(cur)) {
                Dashboard.lv.Modify(0, "-Select")
                Dashboard.lv.Modify(i, "Select Focus Vis")
                break
            }
    }

    static ExitBrowse() {
        Dashboard.browse := ""
        Dashboard.search.Value := ""
        Dashboard.Refresh()
        Dashboard.FocusSearch()
    }

    static BackspaceKey() {
        if (Dashboard.SearchFocused() && Dashboard.search.Value = "" && Dashboard.browse != "") {
            Dashboard.BrowseUp()
            return
        }
        Send("{Backspace}")
    }

    ; Folder a row stands for (for Tab / browse), or "".
    static RowFolder(r) {
        if (r.kind = "file")
            return r.dir ? r.path : ""
        if (r.kind = "item") {
            t := r.item["type"]
            if (t = "project")
                return Actions.Expand(r.item["root"])
            if (t = "folder")
                return Actions.Expand(r.item["path"])
            if (t = "template")
                return Actions.Expand(r.item["source"])
            if (t = "script")
                return Files.Parent(r.item["path"])
        }
        return ""
    }

    ; ---- building the list -------------------------------------------------

    static Refresh() {
        if !Dashboard.g
            return
        Dashboard._refreshPending := false
        lv := Dashboard.lv
        selKey := Dashboard._RowKey(Dashboard.SelectedRow())
        q := Trim(StrLower(Dashboard.search.Value))
        tokens := q = "" ? "" : StrSplit(RegExReplace(q, "\s+", " "), " ")
        running := Scripts.Running()

        Dashboard.UpdateNav()
        rows := Dashboard.BuildRows(q, tokens, running)
        Dashboard.UpdateCue()

        lv.Opt("-Redraw")
        lv.Delete()
        selRow := 0
        for i, r in rows {
            lv.Add(, r.cols*)
            if (selKey != "" && Dashboard._RowKey(r) = selKey)
                selRow := i
        }
        Dashboard.rows := rows
        lv.Opt("+Redraw")
        if (!selRow && rows.Length && rows[1].kind != "msg")
            selRow := 1
        if selRow
            lv.Modify(selRow, "Select Focus Vis")
        Dashboard.UpdateButtons()
        Dashboard.UpdateSummary(running)
        if (Dashboard.browse != "")
            App.Status("In  " Dashboard.browse "      Tab = into folder   Backspace = up   Esc = leave", "")
    }

    static RefreshSoon(ms := 50) {
        if !Dashboard.g
            return
        Dashboard._refreshPending := true
        SetTimer(Dashboard._refreshFn, -ms)
    }
    static _refreshFn := () => Dashboard.Refresh()

    static _RowKey(r) {
        if !r
            return ""
        return r.kind = "item" ? "i:" r.item["id"] : r.HasOwnProp("path") ? "p:" StrLower(r.path) : ""
    }

    static UpdateNav() {
        counts := Map()
        for item in Store.Items
            counts[item["type"]] := counts.Get(item["type"], 0) + 1
        for c in Dashboard.Categories {
            n := ""
            if Dashboard.CatTypes.Has(c[1]) {
                s := 0
                for t in Dashboard.CatTypes[c[1]]
                    s += counts.Get(t, 0)
                n := s ? s : ""
            } else if (c[1] = "inbox")
                n := Dashboard._inboxCount ? Dashboard._inboxCount : ""
            Dashboard.nav[c[1]].Text := "   " c[2] "   " n
        }
    }

    static UpdateCue() {
        static last := ""
        cue := Dashboard.browse != "" ? "Filter " Files.Name(Dashboard.browse) "…   (Backspace = up a folder, Esc = leave)"
            : Dashboard.category = "files" ? "Find any file or folder: recent ones first, then the whole PC"
            : Dashboard.category = "inbox" ? "Filter the inbox…   Ctrl+M moves the selection to a folder"
            : "Search everything: projects, files, layouts, scripts, apps, hotkeys…"
        if (cue != last) {
            Theme.Cue(Dashboard.search, cue)
            last := cue
        }
    }

    static BuildRows(q, tokens, running) {
        rows := []
        if (Dashboard.browse != "")
            return Dashboard.BrowseRows(tokens)
        cat := Dashboard.category
        if (cat = "inbox")
            return Dashboard.InboxRows(tokens)
        if (cat = "files") {
            seen := Map()
            for p in Places.Top(tokens ? 40 : 100, tokens)
                Dashboard._AddFile(rows, seen, p["path"], p["dir"], p["last"], "recent")
            if tokens
                Dashboard._AddEverything(rows, seen, q, 150)
            if !rows.Length
                rows.Push(Dashboard.Msg(tokens ? "No matches for '" Dashboard.search.Value "'"
                    : "Nothing remembered yet. Folders you open in Explorer and files you open show up here automatically."))
            return rows
        }

        ; items
        types := Dashboard.CatTypes.Get(cat, "")
        order := Map("project", 1, "template", 2, "layout", 3, "app", 4, "folder", 5, "link", 6, "script", 7)
        list := []
        for item in Store.Items {
            if (types && !Dashboard._In(item["type"], types))
                continue
            details := Dashboard.Details(item)
            if tokens {
                hay := StrLower(item["name"] " " item["type"] " " Hotkeys.Pretty(item["hotkey"]) " " item["hotkey"] " " details)
                if !Files.MatchAll(hay, tokens)
                    continue
                n := StrLower(item["name"])
                key := (InStr(n, q) = 1 ? "0" : InStr(n, q) ? "1" : InStr(n, tokens[1]) ? "2" : "3") n
            } else if (item["type"] = "project")
                key := "1" (99999999999999 - Integer("0" item.Get("lastOpened", "0")))
            else
                key := order.Get(item["type"], 9) StrLower(item["name"])
            list.Push({k: key, row: Dashboard.ItemRow(item, details, running)})
        }
        Files.SortBy(list, "k")

        if (cat = "all" && !tokens && Dashboard._inboxCount)
            rows.Push({kind: "goto", target: "inbox", cols: ["", "Inbox: " Dashboard._inboxCount " loose file" (Dashboard._inboxCount = 1 ? "" : "s"), "Inbox", "", "Downloads + Desktop. Enter to sort them out"]})
        for x in list
            rows.Push(x.row)
        if (cat = "all") {
            seen := Map()
            for p in Places.Top(tokens ? 10 : 8, tokens)
                Dashboard._AddFile(rows, seen, p["path"], p["dir"], p["last"], "recent")
            if (tokens && StrLen(q) >= 3)
                Dashboard._AddEverything(rows, seen, q, 25)
        }
        if !rows.Length
            rows.Push(Dashboard.Msg(tokens ? "No matches for '" Dashboard.search.Value "'" : "Nothing here yet. Press + New (Ctrl+N) to add one."))
        return rows
    }

    static _In(v, arr) {
        for x in arr
            if (x = v)
                return true
        return false
    }

    static Msg(text) => ({kind: "msg", cols: ["", text, "", "", ""]})

    static ItemRow(item, details, running) {
        return {kind: "item", item: item, cols: [Hotkeys.Pretty(item["hotkey"]), item["name"],
            Store.TypeNames[item["type"]], Dashboard.StatusOf(item, running), details]}
    }

    static FileRow(path, isDir, time, src) {
        where := Files.Parent(path)
        proj := Projects.Containing(path)
        if proj
            where := "[" proj["name"] "]  " where
        return {kind: "file", path: path, dir: isDir, src: src,
            cols: ["", Files.Name(path), Files.Kind(path, isDir), Files.Age(time), where]}
    }

    static _AddFile(rows, seen, path, isDir, time, src) {
        k := StrLower(path)
        if seen.Has(k)
            return
        seen[k] := 1
        rows.Push(Dashboard.FileRow(path, isDir, time != "" ? time : Files.ModTime(path), src))
    }

    static _AddEverything(rows, seen, q, max) {
        r := Everything.Search(q, max)
        if (r is Array) {
            for x in r
                Dashboard._AddFile(rows, seen, x.path, x.dir, "", "search")
            return
        }
        static nagged := false
        if (Dashboard.category = "files" || !nagged) {
            nagged := true
            hint := Everything.LastError = "notrunning" ? "Start Everything to search the whole PC (it's installed but not running)"
                : "Whole-PC search: set up Everything in Settings (one click)"
            rows.Push({kind: "goto", target: "settings", cols: ["", hint, "Tip", "", ""]})
        }
    }

    static BrowseRows(tokens) {
        rows := []
        for x in Files.List(Dashboard.browse) {
            if tokens && !Files.MatchAll(x.name, tokens)
                continue
            rows.Push(Dashboard.FileRow(x.path, x.dir, x.time, "browse"))
        }
        if !rows.Length
            rows.Push(Dashboard.Msg(tokens ? "Nothing here matches" : "Empty folder"))
        return rows
    }

    static InboxRows(tokens) {
        rows := []
        for x in Files.Inbox() {
            if tokens && !Files.MatchAll(StrLower(Files.Name(x.path)), tokens)
                continue
            r := Dashboard.FileRow(x.path, x.dir, x.time, "inbox")
            sug := Places.Suggest(x.path, 1)
            r.cols[5] := (sug.Length ? "→ " Files.Name(sug[1]) "?   " : "") Files.Name(x.from)
            rows.Push(r)
        }
        Dashboard._inboxCount := rows.Length
        if !rows.Length
            rows.Push(Dashboard.Msg(tokens ? "Nothing matches" : "Inbox zero. Downloads and Desktop are clear."))
        return rows
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
            case "project":
                extra := item["layout"] != "" && Store.ById(item["layout"]) ? " · layout " Store.ById(item["layout"])["name"] : ""
                return item["root"] extra
            case "template":
                return "→ " (item["dest"] != "" ? item["dest"] : "next to the template") " · " item["source"]
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
            case "project":
                return item.Get("lastOpened", "") != "" ? Files.Age(item["lastOpened"]) : "new"
        }
        return ""
    }

    static Tick() {
        if !Dashboard.IsVisible()
            return
        Dashboard._ticks++
        running := Scripts.Running()
        for i, r in Dashboard.rows {
            if (r.kind != "item" || r.item["type"] != "script")
                continue
            s := Dashboard.StatusOf(r.item, running)
            if (Dashboard.lv.GetText(i, 4) != s)
                Dashboard.lv.Modify(i, "Col4", s)
        }
        if (Mod(Dashboard._ticks, 6) = 0) {
            n := Files.InboxCount()
            if (n != Dashboard._inboxCount) {
                Dashboard._inboxCount := n
                Dashboard.UpdateNav()
            }
        }
        Dashboard.UpdateSummary(running)
        Dashboard.UpdateButtons()
    }

    static UpdateSummary(running) {
        n := 0
        for item in Store.OfType("script")
            if running.Has(StrLower(item["path"]))
                n++
        s := n " script" (n = 1 ? "" : "s") " running  ·  " Hotkeys.Active.Count " hotkeys  ·  " Places.data.Count " places remembered"
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

        Finding things
          type                 search everything (Home), any file (Files)
          Enter / dbl-click    open it. If a Save/Open dialog was in front,
                               the folder or file goes into that dialog
          Tab                  look inside a folder or project
          Backspace            up one folder (when the search box is empty)
          Esc                  clear search, leave folder, then hide

        Files
          Ctrl+M               move selected file(s) to… (learns where things go)
          Ctrl+Z               undo the last move / rename
          F2                   rename
          Delete               Recycle Bin (in Recent: just forget it)
          Ctrl+R               show in Explorer
          Ctrl+Shift+C         copy path
          Shift+Up/Down        select several

        Items
          F2 or Ctrl+E         edit      Ctrl+N  new      Delete  remove
          Ctrl+1 … Ctrl+7      switch category

        Script editor
          Ctrl+S               save, check for errors, swap in the new version
          Ctrl+F / F3 / Ctrl+G find / next / go to line
        )", "Alcadeias — keys")
    }

    ; ---- selection -----------------------------------------------------------

    static SelectedRow() {
        if !Dashboard.lv
            return ""
        i := Dashboard.lv.GetNext(0)
        return (i && i <= Dashboard.rows.Length) ? Dashboard.rows[i] : ""
    }

    static SelectedRows() {
        out := []
        i := 0
        while (i := Dashboard.lv.GetNext(i))
            if (i <= Dashboard.rows.Length)
                out.Push(Dashboard.rows[i])
        return out
    }

    static SelectedFiles() {
        out := []
        for r in Dashboard.SelectedRows()
            if (r.kind = "file")
                out.Push(r.path)
        return out
    }

    static SelectedItem() {
        r := Dashboard.SelectedRow()
        return (r && r.kind = "item") ? r.item : ""
    }

    static MoveSel(delta, extend := false) {
        lv := Dashboard.lv
        n := lv.GetCount()
        if !n
            return
        cur := SendMessage(0x100C, -1, 0x1, lv)   ; LVM_GETNEXTITEM focused
        cur := (cur >= 0 && cur < 0xFFFFFFFF) ? cur + 1 : 0
        if !cur
            cur := lv.GetNext(0)
        row := Max(1, Min(n, (cur ? cur : 0) + delta))
        if !extend
            lv.Modify(0, "-Select")
        lv.Modify(row, "Select Focus Vis")
    }

    ; ---- buttons -------------------------------------------------------------

    static UpdateButtons() {
        r := Dashboard.SelectedRow()
        acts := []   ; [label, fn] for p1..p3
        editLabel := "", del := ""
        if r {
            switch r.kind {
                case "item":
                    item := r.item
                    editLabel := "Edit", del := "Remove"
                    switch item["type"] {
                        case "script":
                            running := Scripts.IsRunning(item)
                            acts.Push(["Edit code", () => Editor.Open(item)])
                            acts.Push([running ? "Reload" : "Start", () => (Scripts.Apply(item), Dashboard.RefreshSoon())])
                            if running
                                acts.Push(["Stop", () => (Scripts.Stop(item), App.Status("Stopped '" item["name"] "'", "ok"), Dashboard.RefreshSoon())])
                        case "layout":
                            acts.Push(["Apply", () => Dashboard.RunSelected()])
                            acts.Push(["Preview", () => Layouts.Preview(item["slots"])])
                        case "project":
                            acts.Push(["Open project", () => Dashboard.RunSelected()])
                            acts.Push(["Look inside  Tab", () => Dashboard.BrowseInto()])
                        case "template":
                            acts.Push(["New project", () => Dashboard.RunSelected()])
                            acts.Push(["Edit template files", () => Dashboard.BrowseInto()])
                        case "app":
                            acts.Push(["Focus / open", () => Dashboard.RunSelected()])
                        case "folder":
                            acts.Push(["Open", () => Dashboard.RunSelected()])
                            acts.Push(["Look inside  Tab", () => Dashboard.BrowseInto()])
                        default:
                            acts.Push(["Open", () => Dashboard.RunSelected()])
                    }
                case "file":
                    editLabel := "Rename", del := r.src = "recent" ? "Forget" : "Recycle"
                    if (r.src = "inbox") {
                        acts.Push(["Move to…  Ctrl+M", () => Dashboard.MoveSelected()])
                        acts.Push(["Open", () => Dashboard.RunSelected()])
                        acts.Push(["Show in folder", () => Dashboard.RevealSelected()])
                    } else if r.dir {
                        acts.Push(["Open", () => Dashboard.RunSelected()])
                        acts.Push(["Look inside  Tab", () => Dashboard.BrowseInto()])
                        acts.Push(["Move to…", () => Dashboard.MoveSelected()])
                    } else {
                        acts.Push(["Open", () => Dashboard.RunSelected()])
                        acts.Push(["Move to…", () => Dashboard.MoveSelected()])
                        acts.Push(["Show in folder", () => Dashboard.RevealSelected()])
                    }
                case "goto":
                    acts.Push(["Go", () => Dashboard.RunSelected()])
            }
        }
        Dashboard._SetBtn("edit", editLabel)
        Dashboard._SetBtn("delete", del)
        Loop 3 {
            k := "p" A_Index
            a := A_Index <= acts.Length ? acts[A_Index] : ["", ""]
            Dashboard._SetBtn(k, a[1])
            Dashboard.actions[k] := a[2]
        }
    }

    static _SetBtn(k, label) {
        b := Dashboard.btn[k]
        if (b.Text != label)
            b.Text := label
        b.Visible := label != ""
    }

    static _Do(k) {
        fn := Dashboard.actions.Get(k, "")
        if fn
            fn.Call()
    }

    ; ---- actions -------------------------------------------------------------

    static RunSelected() {
        r := Dashboard.SelectedRow()
        if !r || r.kind = "msg"
            return
        if (r.kind = "goto") {
            if (r.target = "settings")
                Dialogs.Settings()
            else
                Dashboard.SetCategory(r.target)
            return
        }
        if (r.kind = "item" && r.item["type"] = "script") {
            Editor.Open(r.item)
            return
        }
        if (r.kind = "item" && r.item["type"] = "template") {
            Templates.Create(r.item)
            return
        }
        target := Dashboard.prevWindow
        Dashboard.Hide()
        if (target && WinExist(target)) {
            try WinActivate(target)
            WinWaitActive(target, , 0.5)
        }
        if (r.kind = "file")
            Files.Open(r.path, target)
        else
            Actions.Run(r.item, target)
    }

    static MoveSelected() {
        paths := Dashboard.SelectedFiles()
        if !paths.Length {
            App.Status("Select a file or folder first (Files, Inbox, or inside a folder)", "warn")
            return
        }
        dest := Picker.Choose(paths.Length = 1 ? "Move '" Files.Name(paths[1]) "' to…" : "Move " paths.Length " items to…", paths[1], Dashboard.g)
        if (dest = "")
            return
        Files.Move(paths, dest)
        Dashboard._inboxCount := Files.InboxCount()
        Dashboard.Refresh()
    }

    static UndoKey() {
        if (Dashboard.SearchFocused() && Dashboard.search.Value != "") {
            Send("^z")
            return
        }
        if Files.Undo() {
            Dashboard._inboxCount := Files.InboxCount()
            Dashboard.Refresh()
        }
    }

    static CopySelectedPaths() {
        paths := Dashboard.SelectedFiles()
        if !paths.Length {
            item := Dashboard.SelectedItem()
            p := item ? Dashboard.RowFolder(Dashboard.SelectedRow()) : ""
            if (item && item["type"] = "script")
                p := item["path"]
            if (p != "")
                paths := [p]
        }
        if paths.Length
            Files.CopyPaths(paths)
    }

    static RevealSelected() {
        r := Dashboard.SelectedRow()
        if !r
            return
        if (r.kind = "file")
            Files.Reveal(r.path)
        else if (r.kind = "item" && r.item["type"] = "script")
            Files.Reveal(r.item["path"])
        else if (p := Dashboard.RowFolder(r))
            Run('explorer.exe "' p '"')
    }

    static NewItem() {
        m := Menu()
        tpls := Store.OfType("template")
        if tpls.Length {
            for t in tpls
                m.Add("New " t["name"] "…", Dashboard._TplFn(t))
            m.Add()
        }
        m.Add("Project…", (*) => Dialogs.EditItem(Store.NewItem("project"), true))
        m.Add("Template…", (*) => Dialogs.EditItem(Store.NewItem("template"), true))
        m.Add("Layout…", (*) => Dialogs.EditItem(Store.NewItem("layout"), true))
        m.Add()
        m.Add("App (focus or launch)…", (*) => Dialogs.EditItem(Store.NewItem("app"), true))
        m.Add("Folder shortcut…", (*) => Dialogs.EditItem(Store.NewItem("folder"), true))
        m.Add("Link / file / command…", (*) => Dialogs.EditItem(Store.NewItem("link"), true))
        m.Add()
        m.Add("New script…", (*) => Dialogs.NewScript())
        m.Add("Add existing .ahk files…", (*) => Dialogs.AddExistingScripts())
        if (Dashboard.browse != "") {
            m.Add()
            here := Dashboard.browse
            m.Add("New folder here…", (*) => Dashboard.NewFolderIn(here))
            m.Add("Make this folder a project", (*) => Dialogs.EditItem(Projects.FromFolder(here), true))
        }
        m.Show()
    }

    static _TplFn(t) => (*) => Templates.Create(t)

    static NewFolderIn(dir) {
        name := Dialogs.AskText("New folder", "Name:", "")
        if (name = "")
            return
        p := dir "\" RegExReplace(name, '[\\/:*?"<>|]', "_")
        try DirCreate(p)
        Dashboard.Refresh()
    }

    static EditSelected() {
        r := Dashboard.SelectedRow()
        if !r
            return
        if (r.kind = "item") {
            Dialogs.EditItem(r.item, false)
            return
        }
        if (r.kind = "file") {
            newName := Dialogs.AskText("Rename", "New name:", Files.Name(r.path))
            if (newName = "" || newName = Files.Name(r.path))
                return
            if Files.Rename(r.path, newName)
                Dashboard.Refresh()
        }
    }

    static DeleteKey() {
        if (Dashboard.SearchFocused() && Dashboard.search.Value != "") {
            Send("{Delete}")
            return
        }
        Dashboard.DeleteSelected()
    }

    static DeleteSelected() {
        r := Dashboard.SelectedRow()
        if !r
            return
        if (r.kind = "file") {
            paths := Dashboard.SelectedFiles()
            if (r.src = "recent") {
                for p in paths
                    Places.Forget(p)
                App.Status("Forgot " paths.Length " recent item" (paths.Length = 1 ? "" : "s") " (the files are untouched)", "ok")
                Dashboard.Refresh()
                return
            }
            what := paths.Length = 1 ? "'" Files.Name(paths[1]) "'" : paths.Length " items"
            if (MsgBox("Move " what " to the Recycle Bin?", "Alcadeias", "YesNo Icon? Default2 Owner" Dashboard.g.Hwnd) != "Yes")
                return
            Files.Recycle(paths)
            Dashboard._inboxCount := Files.InboxCount()
            Dashboard.Refresh()
            return
        }
        item := Dashboard.SelectedItem()
        if !item
            return
        extra := item["type"] = "script" ? "`n`nThe .ahk file stays on disk, and if the script is running it keeps running."
            : item["type"] = "project" || item["type"] = "template" ? "`n`nThe folder and its files stay on disk." : ""
        if (MsgBox("Remove " StrLower(Store.TypeNames[item["type"]]) " '" item["name"] "' from Alcadeias?" extra,
                "Alcadeias", "YesNo Icon? Default2 Owner" Dashboard.g.Hwnd) != "Yes")
            return
        Store.Remove(item["id"])
        Hotkeys.Rebuild()
        Dashboard.Refresh()
        App.Status("Removed '" item["name"] "'", "ok")
    }

    static ContextMenu(row) {
        if (!row || row > Dashboard.rows.Length)
            return
        r := Dashboard.rows[row]
        if (r.kind = "msg" || r.kind = "goto")
            return
        if !(Dashboard.lv.GetNext(row - 1) = row) {
            Dashboard.lv.Modify(0, "-Select")
            Dashboard.lv.Modify(row, "Select Focus")
        }
        m := Menu()
        if (r.kind = "file") {
            p := r.path
            m.Add("Open", (*) => Dashboard.RunSelected())
            if r.dir
                m.Add("Look inside (Tab)", (*) => Dashboard.BrowseTo(p))
            m.Add("Show in Explorer (Ctrl+R)", (*) => Files.Reveal(p))
            m.Add("Move to… (Ctrl+M)", (*) => Dashboard.MoveSelected())
            m.Add("Rename (F2)", (*) => Dashboard.EditSelected())
            m.Add("Copy path (Ctrl+Shift+C)", (*) => Dashboard.CopySelectedPaths())
            if r.dir {
                m.Add()
                m.Add("Make this folder a project", (*) => Dialogs.EditItem(Projects.FromFolder(p), true))
                m.Add("Add as folder shortcut", (*) => Dashboard._AddFolderShortcut(p))
            }
            m.Add()
            if (r.src = "recent")
                m.Add("Forget from recent", (*) => Dashboard.DeleteSelected())
            else
                m.Add("Recycle", (*) => Dashboard.DeleteSelected())
            m.Show()
            return
        }
        item := r.item
        if (item["type"] = "script") {
            m.Add("Open in editor", (*) => Editor.Open(item))
            m.Add("Open in external editor", (*) => Editor.External(item))
            m.Add(Scripts.IsRunning(item) ? "Reload" : "Start", (*) => (Scripts.Apply(item), Dashboard.RefreshSoon()))
            if Scripts.IsRunning(item)
                m.Add("Stop", (*) => (Scripts.Stop(item), Dashboard.RefreshSoon()))
            m.Add("Show file in Explorer", (*) => Files.Reveal(item["path"]))
            m.Add("Open backups folder", (*) => (DirCreate(Scripts.BackupDir(item)), Run('explorer.exe "' Scripts.BackupDir(item) '"')))
        } else {
            m.Add(item["type"] = "template" ? "New project from this" : "Run", (*) => Dashboard.RunSelected())
            if (item["type"] = "layout")
                m.Add("Preview zones", (*) => Layouts.Preview(item["slots"]))
            if (Dashboard.RowFolder(r) != "")
                m.Add("Look inside (Tab)", (*) => Dashboard.BrowseInto())
        }
        m.Add()
        m.Add("Edit…", (*) => Dialogs.EditItem(item, false))
        m.Add("Duplicate", (*) => Dashboard.Duplicate(item))
        m.Add("Remove", (*) => Dashboard.DeleteSelected())
        m.Show()
    }

    static _AddFolderShortcut(p) {
        item := Store.NewItem("folder", Files.Name(p))
        item["path"] := p
        Dialogs.EditItem(item, true)
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
