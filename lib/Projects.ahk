; Projects (one key opens a project's folder, files, links and layout),
; templates (copy a skeleton folder into a new project) and the folder picker.

class Projects {
    ; Opens everything that belongs to a project.
    static Run(item, target := 0) {
        root := Actions.Expand(item["root"])
        if (root != "" && !DirExist(root)) {
            App.Status("Project folder not found: " root, "error", true)
            return
        }
        item["lastOpened"] := A_Now
        Store.Save()
        if (root != "") {
            Places.Visit(root)
            if item["openFolder"]
                Actions.OpenFolder(root, target)
        }
        for line in StrSplit(item["open"], "`n", " `r`t") {
            if (line = "" || SubStr(line, 1, 1) = ";")
                continue
            p := Actions.Expand(line)
            ; relative paths are relative to the project folder
            if (root != "" && !RegExMatch(p, "i)^([a-z]:\\|\\\\|[a-z][\w+.-]*:)") && FileExist(root "\" p))
                p := root "\" p
            try {
                Run(p, root != "" ? root : A_WorkingDir)
                if FileExist(p)
                    Places.Visit(p)
            } catch as e
                App.Status("Couldn't open '" line "': " e.Message, "warn", true)
        }
        if (item["layout"] != "") {
            lay := Store.ById(item["layout"])
            if lay {
                Sleep(400)
                Layouts.Apply(lay)
            }
        }
        App.Status("Opened project '" item["name"] "'", "ok")
    }

    static Recent(n := 6) {
        list := []
        for item in Store.OfType("project")
            list.Push({item: item, t: item.Get("lastOpened", "")})
        Files.SortBy(list, "t", true)
        out := []
        for x in list {
            out.Push(x.item)
            if (out.Length >= n)
                break
        }
        return out
    }

    ; Project whose folder contains path (deepest match), or "".
    static Containing(path) {
        best := "", bestLen := 0
        p := StrLower(path) "\"
        for item in Store.OfType("project") {
            r := StrLower(RTrim(Actions.Expand(item["root"]), "\")) "\"
            if (r != "\" && InStr(p, r) = 1 && StrLen(r) > bestLen)
                best := item, bestLen := StrLen(r)
        }
        return best
    }

    static FromFolder(path) {
        item := Store.NewItem("project", Files.Name(path))
        item["root"] := path
        return item
    }
}

class Templates {
    static Placeholders(name) {
        return Map("{name}", name, "{date}", FormatTime(, "yyyy-MM-dd"), "{yyyy}", A_YYYY,
            "{MM}", A_MM, "{dd}", A_DD, "{month}", FormatTime(, "MMMM"))
    }

    static Fill(text, ph) {
        for k, v in ph
            text := StrReplace(text, k, v)
        return text
    }

    ; Asks for a name, copies the template folder, fills in {name}/{date}
    ; in file names and text files, registers a project and opens it.
    static Create(tpl) {
        src := Actions.Expand(tpl["source"])
        if !DirExist(src) {
            App.Status("Template folder not found: " src, "error")
            return
        }
        name := Dialogs.AskText("New " tpl["name"], "Name:", "")
        if (name = "")
            return
        name := RegExReplace(name, '[\\/:*?"<>|]', "_")
        ph := Templates.Placeholders(name)
        destRoot := Actions.Expand(tpl["dest"])
        if (destRoot = "")
            destRoot := Files.Parent(src)
        DirCreate(destRoot)
        folderName := Templates.Fill(tpl["pattern"] != "" ? tpl["pattern"] : "{name}", ph)
        dest := destRoot "\" folderName
        if FileExist(dest) {
            App.Status("'" dest "' already exists", "error")
            return
        }
        try DirCopy(src, dest)
        catch as e {
            App.Status("Couldn't copy the template: " e.Message, "error")
            return
        }
        ; rename placeholders, deepest first so parent paths stay valid
        all := []
        Loop Files dest "\*", "FDR"
            if InStr(A_LoopFileName, "{")
                all.Push({path: A_LoopFileFullPath, depth: StrLen(A_LoopFileFullPath) - StrLen(StrReplace(A_LoopFileFullPath, "\"))})
        Files.SortBy(all, "depth", true)
        for x in all {
            n := Templates.Fill(Files.Name(x.path), ph)
            to := Files.Parent(x.path) "\" n
            try (Files.IsDir(x.path) ? DirMove(x.path, to) : FileMove(x.path, to))
        }
        ; fill placeholders inside small text files
        Loop Files dest "\*", "FR" {
            if !RegExMatch(A_LoopFileExt, "i)^(md|txt|json|csv|ahk|html)$") || A_LoopFileSize > 1048576
                continue
            try {
                enc := Editor.DetectEncoding(A_LoopFileFullPath)
                t := FileRead(A_LoopFileFullPath, enc)
                t2 := Templates.Fill(t, ph)
                if (t2 != t) {
                    f := FileOpen(A_LoopFileFullPath, "w", enc)
                    f.Write(t2)
                    f.Close()
                }
            }
        }
        Places.Visit(dest)
        proj := Store.NewItem("project", name)
        proj["root"] := dest
        proj["layout"] := tpl["layout"]
        proj["open"] := Templates.Fill(tpl["open"], ph)
        proj["template"] := tpl["id"]
        proj["lastOpened"] := A_Now
        Store.Add(proj)
        Hotkeys.Rebuild()
        Dashboard.Refresh()
        App.Status("Created project '" name "' in " destRoot, "ok")
        Projects.Run(proj)
    }

    ; A ready-to-use example template in data\templates\.
    static MakeStarter() {
        root := Store.Dir "\templates\Video project"
        if DirExist(root)
            return root
        for d in ["01_Footage", "02_Audio", "03_Graphics", "04_Project", "05_Exports", "06_Thumbnails"]
            DirCreate(root "\" d)
        f := FileOpen(root "\{name} notes.md", "w", "UTF-8")
        f.Write("# {name}`r`n`r`nStarted {date}`r`n`r`n## Idea`r`n`r`n## To do`r`n- [ ] `r`n`r`n## Links`r`n")
        f.Close()
        return root
    }
}

; Small search-as-you-type folder chooser ("Move to…", "Where should this go?").
; Suggests learned destinations first, then projects and their subfolders,
; folder shortcuts, recent folders, and (with Everything) any folder on the PC.
class Picker {
    static Choose(title, forPath := "", owner := "") {
        f := Form(title, owner, 760)
        q := Theme.Edit(f.g, Format("x24 y{} w712 h32", f.y))
        q.SetFont("s11")
        SendMessage(0xD3, 1, 10, q)
        Theme.Cue(q, "Type to find a folder (project, recent, any folder with Everything) or paste a path")
        f.y += 42
        lv := Theme.ListView(f.g, Format("x24 y{} w712 h360", f.y), ["Folder", "Where", "Why"], 28)
        lv.ModifyCol(1, 200), lv.ModifyCol(2, 400), lv.ModifyCol(3, 90)
        f.y += 370
        rows := []
        fill := () => Picker._Fill(lv, rows, q.Value, forPath)
        q.OnEvent("Change", (*) => SetTimer(fill, -120))
        lv.OnEvent("DoubleClick", (*) => f.onSave.Call())
        result := ""
        pick := () => (
            r := lv.GetNext(0),
            r && r <= rows.Length ? (result := rows[r], f.Close(true)) : 0)
        f.Buttons(pick, "Choose")
        ; arrows move the list while typing
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

    static _Move(lv, d) {
        n := lv.GetCount()
        if !n
            return
        r := Max(1, Min(n, lv.GetNext(0) + d))
        lv.Modify(0, "-Select")
        lv.Modify(r, "Select Focus Vis")
    }

    static _Fill(lv, rows, query, forPath) {
        q := Trim(StrLower(query))
        tokens := q = "" ? "" : StrSplit(RegExReplace(q, "\s+", " "), " ")
        seen := Map()
        rows.Length := 0
        add(path, why) {
            path := RTrim(path, "\")
            k := StrLower(path)
            if (path = "" || seen.Has(k) || !DirExist(path))
                return
            if tokens && !Files.MatchAll(k, tokens)
                return
            seen[k] := 1
            rows.Push(path)
            lv.Add(, Files.Name(path), Files.Parent(path), why)
        }
        lv.Opt("-Redraw")
        lv.Delete()
        ; pasted / typed full path
        typed := Trim(query, " `t`"")
        if RegExMatch(typed, "^([A-Za-z]:\\|\\\\)") && DirExist(typed)
            add(typed, "typed")
        if (forPath != "")
            for d in Places.Suggest(forPath)
                add(d, "suggested")
        for p in Projects.Recent(50) {
            root := Actions.Expand(p["root"])
            if (root = "")
                continue
            add(root, "project")
            Loop Files root "\*", "D"
                add(A_LoopFileFullPath, "project")
        }
        for it in Store.OfType("folder")
            add(Actions.Expand(it["path"]), "shortcut")
        for pl in Places.Top(40, tokens, "dir")
            add(pl["path"], "recent")
        if (StrLen(q) >= 2) {
            r := Everything.Search(q, 60, true)
            if (r is Array)
                for x in r
                    add(x.path, "on PC")
        }
        lv.Opt("+Redraw")
        if rows.Length
            lv.Modify(1, "Select Focus Vis")
    }
}
