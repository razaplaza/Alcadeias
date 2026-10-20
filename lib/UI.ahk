; The interface: the main window and the idea-capture box are WebView2 pages
; (ui\*.html). AutoHotkey does the real work; pages talk to it with small
; JSON messages:
;   page -> host  {id, cmd, ...}         host -> page  {reply: id, result}
;                                        host -> page  {event, value}
; If WebView2 can't start, Alcadeias falls back to the classic window.

class UI {
    static env := ""
    static main := ""
    static cap := ""
    static failed := false
    static _changedFn := ObjBindMethod(UI, "_PostChanged")

    static Start() {
        if Store.Setting("classicUI", 0) {
            UI.failed := true
            return
        }
        try {
            UI.main := WebWin("main", "index.html", "+Resize +MinSize900x560", "Alcadeias")
            UI.cap := WebWin("capture", "capture.html", "+AlwaysOnTop -Caption +ToolWindow", "Alcadeias idea")
            dataDir := EnvGet("LOCALAPPDATA") "\Alcadeias\WebView2"
            DirCreate(dataDir)
            WebView2.CreateEnvironmentAsync(0, dataDir).then(
                (env) => UI._OnEnv(env),
                (err) => UI._Fail(err))
        } catch as e
            UI._Fail(e)
    }

    static _OnEnv(env) {
        UI.env := env
        UI.main.Attach(env)
        UI.cap.Attach(env)
    }

    static _Fail(err) {
        UI.failed := true
        msg := (err is Error) ? err.Message : String(err)
        try UI.main.g.Destroy()
        try UI.cap.g.Destroy()
        App.Status("Using the classic window (WebView2 didn't start: " msg ")", "warn", true)
    }

    static Live() => !UI.failed && UI.main

    ; ---- main window ---------------------------------------------------------

    static Show(tab := "") {
        if !UI.Live() {
            if (tab != "")
                Dashboard.ShowTab(tab)
            else
                Dashboard.Show()
            return
        }
        g := UI.main.g
        active := WinExist("A")
        if (active && active != g.Hwnd)
            Dashboard.prevWindow := active
        if !UI.main.shown {
            pos := Store.Setting("winMain", "")
            g.Show(pos != "" ? pos : "w1180 h760 Center")
            UI.main.shown := true
        } else
            g.Show()
        try WinActivate(g)
        UI.main.Focus()
        UI.main.Post(Map("event", "shown", "value", tab))
    }

    static ShowTab(tab) => UI.Show(tab)

    static Toggle() {
        if (UI.Live() && WinActive("ahk_id " UI.main.g.Hwnd))
            UI.HideMain()
        else if !UI.Live() && Dashboard.IsActive()
            Dashboard.Hide()
        else
            UI.Show()
    }

    static HideMain() {
        if !UI.Live() || !UI.main.shown
            return
        g := UI.main.g
        if DllCall("IsWindowVisible", "Ptr", g.Hwnd) && WinGetMinMax(g) = 0 {
            WinGetPos(&x, &y, , , g)
            g.GetClientPos(, , &w, &h)
            pos := Format("x{} y{} w{} h{}", x, y, w, h)
            if (Store.Setting("winMain", "") != pos) {
                Store.Settings["winMain"] := pos
                Store.Save()
            }
        }
        g.Hide()
    }

    static IsMainVisible() => UI.Live() && UI.main.shown && DllCall("IsWindowVisible", "Ptr", UI.main.g.Hwnd)

    static OwnerGui() {
        if UI.IsMainVisible()
            return UI.main.g
        if (Dashboard.g && Dashboard.IsVisible())
            return Dashboard.g
        return ""
    }

    static OwnerHwnd() {
        g := UI.OwnerGui()
        return g ? g.Hwnd : A_ScriptHwnd
    }

    static Event(name, value := "") {
        if UI.Live()
            UI.main.Post(Map("event", name, "value", value))
    }

    ; Something changed (items, files…): the page re-asks for its list.
    static Changed() {
        if UI.Live()
            SetTimer(UI._changedFn, -40)
    }

    static _PostChanged() => UI.Event("refresh")

    static Status(text, kind) {
        if UI.IsMainVisible()
            UI.main.Post(Map("event", "status", "value", Map("text", text, "kind", kind)))
    }

    ; ---- idea capture --------------------------------------------------------

    static Capture() {
        if !UI.Live() {
            t := Dialogs.AskText("New idea", "Idea:", "")
            if (t != "")
                Plan.AddIdea(Map("text", t, "tier", "B", "tags", []))
            return
        }
        g := UI.cap.g
        ; centre on the monitor with the active window
        mon := MonitorGetPrimary()
        try mon := Layouts.MonitorOf(WinExist("A"))
        MonitorGetWorkArea(mon, &l, &t, &r, &b)
        w := 600, h := 236
        g.Show(Format("x{} y{} w{} h{}", l + (r - l - w) // 2, t + Round((b - t) * 0.28), w, h))
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", 33, "Int*", 2, "Int", 4)   ; rounded corners
        try WinActivate(g)
        UI.cap.Focus()
        UI.cap.Post(Map("event", "open", "value", Plan.Doc("ideas")))
    }

    static HideCapture() {
        if UI.Live()
            UI.cap.g.Hide()
    }

    static Broadcast(msg, except := "") {
        if !UI.Live()
            return
        for w in [UI.main, UI.cap]
            if (w != except)
                w.Post(msg)
    }
}

; One window with a WebView2 page in it.
class WebWin {
    __New(name, page, opts, title) {
        this.name := name
        this.page := page
        this.ready := false
        this.shown := false
        this.queue := []
        this.ctrl := ""
        this.wv := ""
        g := Gui(opts, title)
        g.BackColor := Theme.Bg
        g.MarginX := 0, g.MarginY := 0
        Theme.DarkTitle(g)
        this.g := g
        g.OnEvent("Size", ObjBindMethod(this, "_OnSize"))
        g.OnEvent("Close", ObjBindMethod(this, "_OnClose"))
        g.Show("Hide w900 h600")
    }

    Attach(env) {
        env.CreateCoreWebView2ControllerAsync(this.g.Hwnd).then(
            (c) => this._OnController(c),
            (err) => UI._Fail(err))
    }

    _OnController(c) {
        this.ctrl := c
        try c.DefaultBackgroundColor := 0x181413FF   ; #131418 (A,R,G,B bytes)
        wv := c.CoreWebView2
        this.wv := wv
        s := wv.Settings
        try s.AreDefaultContextMenusEnabled := false
        try s.IsStatusBarEnabled := false
        try s.IsZoomControlEnabled := false
        try s.AreDevToolsEnabled := Store.Setting("devTools", 0) ? true : false
        try s.AreBrowserAcceleratorKeysEnabled := false
        wv.SetVirtualHostNameToFolderMapping("alcadeias.local", A_ScriptDir "\ui", 1)
        this.msgToken := wv.add_WebMessageReceived(ObjBindMethod(this, "_OnMessage"))
        wv.Navigate("https://alcadeias.local/" this.page)
        c.Fill()
    }

    _OnSize(g, minMax, w, h) {
        if !this.ctrl
            return
        try {
            if (minMax = -1)
                this.ctrl.IsVisible := false
            else {
                this.ctrl.IsVisible := true
                this.ctrl.Fill()
            }
        }
    }

    _OnClose(*) {
        if (this.name = "main")
            UI.HideMain()
        else
            this.g.Hide()
        return true
    }

    Focus() {
        if this.ctrl
            try this.ctrl.MoveFocus(0)
    }

    _OnMessage(sender, args) {
        text := ""
        try text := args.WebMessageAsJson
        if (text = "")
            return
        ; never block inside a WebView2 callback: handle it on the next tick
        SetTimer(Hub.Process.Bind(Hub, this, text), -1)
    }

    Post(m) {
        text := JSON.Dump(m, "")
        if !this.ready || !this.wv {
            this.queue.Push(text)
            return
        }
        try this.wv.PostWebMessageAsJson(text)
    }

    Flush() {
        this.ready := true
        for t in this.queue
            try this.wv.PostWebMessageAsJson(t)
        this.queue := []
    }

    Reply(id, result) => this.Post(Map("reply", id, "result", result))
}

; Answers page requests, reusing the dashboard's logic for rows and actions.
class Hub {
    static lastRows := Map()    ; category -> last rows built for the page

    static Process(win, text) {
        try msg := JSON.Load(text)
        catch
            return
        if !(msg is Map)
            return
        id := msg.Get("id", 0)
        cmd := msg.Get("cmd", "")
        result := ""
        try result := Hub.Do(win, cmd, msg)
        catch as e {
            result := Map("error", e.Message)
            App.Status("Interface error in '" cmd "': " e.Message, "error")
        }
        if id
            win.Reply(id, result)
    }

    static Do(win, cmd, m) {
        switch cmd {
            case "hello":
                win.Flush()
                return Map("version", App.Version, "calendar", Plan.Doc("calendar"), "ideas", Plan.Doc("ideas"),
                    "ideaHotkey", Hotkeys.Pretty(Store.Setting("ideaHotkey", "^+s")))
            case "rows":
                return Hub.Rows(m.Get("cat", "find"), m.Get("q", ""), m.Get("browse", ""))
            case "act":
                return Hub.Act(m.Get("cat", "find"), m.Get("browse", ""), m.Get("action", ""), m.Get("rows", []))
            case "new":
                Dashboard.category := m.Get("cat", "find")
                Dashboard.browse := m.Get("browse", "")
                Dashboard.NewItem()
                return ""
            case "undo":
                Files.Undo()
                UI.Changed()
                return ""
            case "settings":
                Dialogs.Settings()
                return ""
            case "hide":
                UI.HideMain()
                return ""
            case "plan.save":
                Plan.Save(m["name"], m["doc"], win)
                return ""
            case "idea.add":
                Plan.AddIdea(m["card"], m.Get("newTags", []))
                if (win.name = "capture")
                    UI.HideCapture()
                return ""
            case "capture.hide":
                UI.HideCapture()
                return ""
            case "open":
                try Run(m["target"])
                return ""
        }
        return ""
    }

    ; ---- lists ---------------------------------------------------------------

    static Rows(cat, q, browse) {
        Dashboard.category := cat
        Dashboard.browse := browse
        Dashboard.queryText := q
        ql := Trim(StrLower(q))
        tokens := ql = "" ? "" : StrSplit(RegExReplace(ql, "\s+", " "), " ")
        running := Scripts.Running()
        rows := Dashboard.BuildRows(ql, tokens, running)
        Hub.lastRows[cat] := rows
        out := []
        for r in rows {
            a := Hub.ActionsFor(r)
            out.Push(Map("kind", r.kind, "cols", r.cols, "folder", Dashboard.RowFolder(r) != "" ? 1 : 0,
                "buttons", a.buttons, "menu", a.menu, "edit", a.edit, "del", a.del,
                "src", r.HasOwnProp("src") ? r.src : ""))
        }
        return Map("rows", out, "browse", browse)
    }

    ; Buttons (up to 3) and the right-click menu for a row: [id, label] pairs.
    static ActionsFor(r) {
        b := [], m := [], editL := "", del := ""
        switch r.kind {
            case "item":
                item := r.item
                editL := "Edit", del := "Remove"
                switch item["type"] {
                    case "script":
                        running := Scripts.IsRunning(item)
                        if (KeyMap.IniFor(item) != "")
                            b.Push(["keymap", "Key map"])
                        b.Push(["code", "Edit code"])
                        b.Push(["start", running ? "Reload" : "Start"])
                        m.Push(["code", "Open in editor"], ["external", "Open in external editor"], ["start", running ? "Reload" : "Start"])
                        if running
                            m.Push(["stop", "Stop"])
                        m.Push(["reveal", "Show file in Explorer"], ["backups", "Open backups folder"])
                    case "layout":
                        b.Push(["open", "Apply"], ["preview", "Preview"])
                        m.Push(["open", "Apply"], ["preview", "Preview zones"])
                    case "project":
                        b.Push(["open", "Open project"], ["browse", "Look inside"])
                        m.Push(["open", "Open project"], ["browse", "Look inside"])
                    case "template":
                        b.Push(["open", "New project"], ["browse", "Template files"])
                        m.Push(["open", "New project from this"], ["browse", "Look inside"])
                    case "app":
                        b.Push(["open", "Focus / open"])
                        m.Push(["open", "Run"])
                    case "snippet":
                        b.Push(["open", "Paste"], ["copy", "Copy"])
                        m.Push(["open", "Paste"], ["copy", "Copy"])
                    case "folder":
                        b.Push(["open", "Open"], ["browse", "Look inside"])
                        m.Push(["open", "Open"], ["browse", "Look inside"])
                    default:
                        b.Push(["open", "Open"])
                        m.Push(["open", "Run"])
                }
                m.Push("-", ["edit", "Edit…"], ["dup", "Duplicate"], ["delete", "Remove"])
            case "file":
                editL := "Rename", del := r.src = "recent" ? "Forget" : "Recycle"
                if (r.src = "inbox")
                    b.Push(["move", "Move to…"], ["open", "Open"], ["reveal", "Show in folder"])
                else if r.dir
                    b.Push(["open", "Open"], ["browse", "Look inside"], ["move", "Move to…"])
                else
                    b.Push(["open", "Open"], ["move", "Move to…"], ["reveal", "Show in folder"])
                m.Push(["open", "Open"])
                if r.dir
                    m.Push(["browse", "Look inside"])
                m.Push(["reveal", "Show in Explorer"], ["move", "Move to…"], ["edit", "Rename"], ["copypath", "Copy path"])
                if r.dir
                    m.Push("-", ["makeproject", "Make this folder a project"], ["addshortcut", "Add as folder shortcut"])
                if (r.src = "inbox" && !r.dir) {
                    ext := Files.Ext(r.path)
                    sug := Places.Suggest(r.path, 1)
                    m.Push("-")
                    if sug.Length
                        m.Push(["quickrule", "Always move ." ext " files to " Files.Name(sug[1])])
                    m.Push(["makerule", "Make a rule for ." ext " files…"])
                }
                m.Push("-", ["delete", r.src = "recent" ? "Forget from recent" : "Recycle"])
            case "clip":
                del := "Forget", editL := "Save as snippet"
                b.Push(["open", "Paste"], ["copy", "Copy"], ["edit", "Save as snippet"])
                m.Push(["open", "Paste"], ["copy", "Copy"], ["edit", "Save as snippet…"], "-", ["delete", "Forget"], ["clearclips", "Clear all history…"])
            case "goto":
                b.Push(["open", "Go"])
        }
        return {buttons: b, menu: m, edit: editL, del: del}
    }

    static Act(cat, browse, action, idx) {
        rows := Hub.lastRows.Get(cat, [])
        sel := []
        for i in idx
            if (i >= 1 && i <= rows.Length)
                sel.Push(rows[i])
        if !sel.Length && action != "undo"
            return ""
        Dashboard.category := cat
        Dashboard.browse := browse
        Dashboard._webSel := sel
        out := Map()
        try {
            r := sel[1]
            item := r.kind = "item" ? r.item : ""
            switch action {
                case "open":     Dashboard.RunSelected()
                case "browse":
                    p := Dashboard.RowFolder(r)
                    if (p != "") {
                        Places.Visit(p)
                        out["browse"] := p
                    }
                case "edit":     Dashboard.EditSelected()
                case "delete":   Dashboard.DeleteSelected()
                case "move":     Dashboard.MoveSelected()
                case "reveal":   Dashboard.RevealSelected()
                case "copypath": Dashboard.CopySelectedPaths()
                case "code":     Editor.Open(item)
                case "external": Editor.External(item)
                case "start":    Scripts.Apply(item)
                case "stop":     Scripts.Stop(item), App.Status("Stopped '" item["name"] "'", "ok")
                case "keymap":   KeyMap.Open(item)
                case "backups":  DirCreate(Scripts.BackupDir(item)), Run('explorer.exe "' Scripts.BackupDir(item) '"')
                case "preview":  Layouts.Preview(item["slots"])
                case "dup":      Dashboard.Duplicate(item)
                case "copy":     Clips.CopyText(r.kind = "clip" ? r.text : Clips.Expand(item["text"]))
                case "makeproject": Dialogs.EditItem(Projects.FromFolder(r.path), true)
                case "addshortcut": Dashboard._AddFolderShortcut(r.path)
                case "quickrule":
                    sug := Places.Suggest(r.path, 1)
                    if sug.Length
                        Dashboard.QuickRule(Files.Ext(r.path), sug[1])
                case "makerule": Dialogs.EditRule(Rules.New(Files.Ext(r.path)), UI.OwnerGui(), true)
                case "clearclips":
                    if (MsgBox("Clear the whole clipboard history? Snippets stay.", "Alcadeias", "YesNo Icon? Owner" UI.OwnerHwnd()) = "Yes")
                        Clips.Clear()
            }
        } finally
            Dashboard._webSel := ""
        return out
    }
}

; Calendar + idea cards, stored as data\calendar.json and data\ideas.json.
; The pages own the structure; AutoHotkey stores it and keeps windows in sync.
class Plan {
    static _cache := Map()

    static Path(name) => Store.Dir "\" name ".json"

    static Default(name) {
        if (name = "calendar")
            return '{"version":1,"dayStart":480,"dayEnd":1440,"view":"week","labels":[],"tasks":[]}'
        return '{"version":1,"lastTier":"B","tags":[],"cards":[]}'
    }

    ; Raw JSON text of a document.
    static Doc(name) {
        if Plan._cache.Has(name)
            return Plan._cache[name]
        t := ""
        try t := FileRead(Plan.Path(name), "UTF-8")
        if (Trim(t) = "")
            t := Plan.Default(name)
        Plan._cache[name] := t
        return t
    }

    static Save(name, text, fromWin := "") {
        if (name != "calendar" && name != "ideas")
            return
        Plan._cache[name] := text
        Plan._Write(name, text)
        UI.Broadcast(Map("event", "plan", "value", Map("name", name, "doc", text)), fromWin)
    }

    static _Write(name, text) {
        p := Plan.Path(name)
        DirCreate(Store.Dir)
        tmp := p ".tmp"
        try FileDelete(tmp)
        FileAppend(text, tmp, "UTF-8")
        if FileExist(p)
            FileCopy(p, p ".bak", 1)
        FileMove(tmp, p, 1)
    }

    ; From the capture box (or the classic fallback).
    static AddIdea(card, newTags := "") {
        doc := ""
        try doc := JSON.Load(Plan.Doc("ideas"))
        if !(doc is Map)
            doc := JSON.Load(Plan.Default("ideas"))
        if !(doc.Get("cards", "") is Array)
            doc["cards"] := []
        if !(doc.Get("tags", "") is Array)
            doc["tags"] := []
        if (newTags is Array)
            for t in newTags {
                if !(t is Map)
                    continue
                dup := false
                for old in doc["tags"]
                    if (old is Map && old.Get("id", "") = t.Get("id", "x"))
                        dup := true
                if !dup
                    doc["tags"].Push(t)
            }
        c := Map("id", "i" A_Now Random(1000, 9999), "text", card.Get("text", ""), "tier", card.Get("tier", "B"),
            "tags", card.Get("tags", []), "created", FormatTime(, "yyyy-MM-ddTHH:mm:ss"), "done", 0, "archived", 0,
            "order", A_TickCount)
        doc["cards"].Push(c)
        doc["lastTier"] := c["tier"]
        Plan.Save("ideas", JSON.Dump(doc, ""))
    }
}
