; Files: auto-tracked recent places, Everything search, inbox, browsing and
; file operations (move with learned destinations, rename, recycle, undo).

; Remembers every folder you visit in Explorer and every file Windows logs as
; recently opened, ranked by how often + how recently ("frecency").
class Places {
    static File := A_ScriptDir "\data\places.json"
    static data := Map()        ; lower path -> Map(path, dir, visits, last)
    static moves := Map()       ; lower ext -> Map(dest -> count)   (learned filing)
    static _dirty := false
    static _seen := Map()       ; explorer hwnd -> last path (count a visit once)
    static _recentStamp := ""   ; newest Recent\*.lnk time already imported

    static Load() {
        try {
            d := JSON.Load(FileRead(Places.File, "UTF-8"))
            if (d.Get("places", "") is Map)
                Places.data := d["places"]
            if (d.Get("moves", "") is Map)
                Places.moves := d["moves"]
            Places._recentStamp := d.Get("recentStamp", "")
        }
        SetTimer(() => Places.PollExplorer(), 4000)
        SetTimer(() => Places.ImportRecent(), 60000)
        SetTimer(() => Places.Save(), 30000)
        SetTimer(() => Places.ImportRecent(), -3000)
        OnExit((*) => Places.Save(true))
    }

    static Save(force := false) {
        if (!Places._dirty && !force)
            return
        Places._dirty := false
        try {
            tmp := Places.File ".tmp"
            try FileDelete(tmp)
            FileAppend(JSON.Dump(Map("places", Places.data, "moves", Places.moves, "recentStamp", Places._recentStamp), ""), tmp, "UTF-8")
            FileMove(tmp, Places.File, 1)
        }
    }

    static Visit(path, when := "", count := true) {
        path := RTrim(path, "\")
        if (StrLen(path) = 2)
            path .= "\"                 ; "C:" -> "C:\"
        attr := FileExist(path)
        if (path = "" || !attr)
            return
        k := StrLower(path)
        when := when != "" ? when : A_Now
        if !Places.data.Has(k)
            Places.data[k] := Map("path", path, "dir", InStr(attr, "D") ? 1 : 0, "visits", 0, "last", when)
        p := Places.data[k]
        if count
            p["visits"] += 1
        if (when > p["last"])
            p["last"] := when
        Places._dirty := true
    }

    static Forget(path) {
        k := StrLower(RTrim(path, "\"))
        if Places.data.Has(k) {
            Places.data.Delete(k)
            Places._dirty := true
        }
    }

    static Frecency(p) {
        hours := Max(0, DateDiff(A_Now, p["last"], "Hours"))
        return (1 + Ln(Max(1, p["visits"]))) * 1000 / (12 + hours)
    }

    ; Best matches, best first. kind: "" all, "dir" folders, "file" files.
    static Top(n := 50, tokens := "", kind := "") {
        list := []
        for k, p in Places.data {
            if (kind = "dir" && !p["dir"]) || (kind = "file" && p["dir"])
                continue
            if tokens && !Files.MatchAll(k, tokens)
                continue
            list.Push({p: p, s: Places.Frecency(p) * Files.NameBoost(p["path"], tokens)})
        }
        Files.SortBy(list, "s", true)
        out := []
        for x in list {
            if !FileExist(x.p["path"])
                continue
            out.Push(x.p)
            if (out.Length >= n)
                break
        }
        return out
    }

    ; Counts the folder each Explorer window shows (once per change).
    static PollExplorer() {
        try {
            for w in ComObject("Shell.Application").Windows {
                try {
                    path := w.Document.Folder.Self.Path
                    hwnd := w.HWND
                } catch
                    continue
                if (path = "" || SubStr(path, 1, 2) = "::")
                    continue
                key := hwnd ":" path
                if Places._seen.Has(hwnd) && Places._seen[hwnd] = path
                    continue
                Places._seen[hwnd] := path
                Places.Visit(path)
            }
        }
    }

    ; Windows keeps a shortcut per recently opened file/folder in Recent\.
    static ImportRecent() {
        dir := A_AppData "\Microsoft\Windows\Recent"
        newest := Places._recentStamp
        list := []
        Loop Files dir "\*.lnk" {
            if (A_LoopFileTimeModified <= Places._recentStamp)
                continue
            list.Push([A_LoopFileFullPath, A_LoopFileTimeModified])
        }
        for x in list {
            if (x[2] > newest)
                newest := x[2]
            target := ""
            try FileGetShortcut(x[1], &target)
            if (target != "" && FileExist(target))
                Places.Visit(target, x[2])
        }
        if (newest != Places._recentStamp) {
            Places._recentStamp := newest
            Places._dirty := true
        }
    }

    ; ---- learned filing ----------------------------------------------------

    static LearnMove(srcPath, dest) {
        ext := Files.Ext(srcPath)
        if !Places.moves.Has(ext)
            Places.moves[ext] := Map()
        m := Places.moves[ext]
        m[dest] := m.Get(dest, 0) + 1
        Places.Visit(dest)
        Places._dirty := true
    }

    ; Destinations used before for this kind of file, most used first.
    static Suggest(path, n := 4) {
        ext := Files.Ext(path)
        list := []
        if Places.moves.Has(ext)
            for dest, c in Places.moves[ext]
                if DirExist(dest)
                    list.Push({d: dest, c: c})
        Files.SortBy(list, "c", true)
        out := []
        for x in list {
            out.Push(x.d)
            if (out.Length >= n)
                break
        }
        return out
    }
}

; voidtools Everything: instant whole-PC file search through its SDK dll.
class Everything {
    static _h := 0
    static _path := ""
    static LastError := ""

    static DllPath() {
        p := Store.Setting("everythingDll")
        if (p != "" && FileExist(p))
            return p
        for c in [A_ScriptDir "\tools\Everything64.dll", A_ProgramFiles "\Everything\Everything64.dll"]
            if FileExist(c)
                return c
        return ""
    }

    static Ready() {
        p := Everything.DllPath()
        if (p = "") {
            Everything.LastError := "nodll"
            return false
        }
        if (!Everything._h || Everything._path != p) {
            Everything._h := DllCall("LoadLibrary", "Str", p, "Ptr")
            Everything._path := p
        }
        return Everything._h != 0
    }

    static _Fn(name) => DllCall("GetProcAddress", "Ptr", Everything._h, "AStr", name, "Ptr")

    ; Array of {path, dir} or "" when Everything isn't available.
    ; Sorted newest first: what you're looking for is usually recent.
    static Search(query, max := 100, foldersOnly := false) {
        if !Everything.Ready()
            return ""
        q := query
        if foldersOnly
            q := "folder: " q
        ex := Store.Setting("everythingExclude", "")
        if (ex != "")
            q .= " " ex
        try {
            DllCall(Everything._Fn("Everything_SetSearchW"), "WStr", q)
            DllCall(Everything._Fn("Everything_SetMax"), "UInt", max)
            DllCall(Everything._Fn("Everything_SetRequestFlags"), "UInt", 0x4)   ; full path
            DllCall(Everything._Fn("Everything_SetSort"), "UInt", 14)            ; date modified, newest first
            if !DllCall(Everything._Fn("Everything_QueryW"), "Int", 1) {
                err := DllCall(Everything._Fn("Everything_GetLastError"), "UInt")
                Everything.LastError := err = 2 ? "notrunning" : "error " err
                return ""
            }
            n := DllCall(Everything._Fn("Everything_GetNumResults"), "UInt")
            buf := Buffer(4096 * 2)
            out := []
            Loop n {
                i := A_Index - 1
                DllCall(Everything._Fn("Everything_GetResultFullPathNameW"), "UInt", i, "Ptr", buf, "UInt", 4096)
                out.Push({path: StrGet(buf, "UTF-16"), dir: DllCall(Everything._Fn("Everything_IsFolderResult"), "UInt", i)})
            }
            Everything.LastError := ""
            return out
        } catch as e {
            Everything.LastError := e.Message
            return ""
        }
    }

    static StatusText() {
        if Everything.Ready() {
            r := Everything.Search("alcadeias-probe-xyz", 1)
            if (r is Array)
                return "ready"
            return Everything.LastError = "notrunning" ? "Everything isn't running (start it, or set it to run at login)" : "error: " Everything.LastError
        }
        return "not set up"
    }

    ; Downloads the official SDK and puts Everything64.dll in tools\.
    static InstallSdk() {
        tools := A_ScriptDir "\tools"
        tmp := A_Temp "\alcadeias-everything-sdk"
        DirCreate(tools)
        try DirDelete(tmp, true)
        DirCreate(tmp)
        ps := "$ProgressPreference='SilentlyContinue';"
            . "Invoke-WebRequest -UseBasicParsing 'https://www.voidtools.com/Everything-SDK.zip' -OutFile '" tmp "\sdk.zip';"
            . "Expand-Archive -Force '" tmp "\sdk.zip' '" tmp "\sdk'"
        RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' ps '"', , "Hide")
        found := ""
        Loop Files tmp "\Everything64.dll", "R"
            found := A_LoopFileFullPath
        if (found = "")
            return false
        FileCopy(found, tools "\Everything64.dll", 1)
        Everything._h := 0
        return true
    }
}

class Files {
    static _undo := []   ; last batch: array of [from, to]

    ; ---- small helpers -----------------------------------------------------

    static Ext(path) {
        SplitPath(path, , , &ext)
        return StrLower(ext)
    }

    static Name(path) {
        SplitPath(RTrim(path, "\"), &n)
        return n != "" ? n : path
    }

    static Parent(path) {
        SplitPath(RTrim(path, "\"), , &dir)
        return dir
    }

    static IsDir(path) => InStr(FileExist(path), "D") ? true : false

    static MatchAll(hay, tokens) {
        for t in tokens
            if !InStr(hay, t)
                return false
        return true
    }

    ; Results whose *name* matches the query rank above path-only matches.
    static NameBoost(path, tokens) {
        if !tokens
            return 1
        n := StrLower(Files.Name(path))
        q := ""
        for t in tokens
            q .= (q = "" ? "" : " ") t
        if (n = q)
            return 8
        if (InStr(n, q) = 1)
            return 5
        if InStr(n, q)
            return 3
        return Files.MatchAll(n, tokens) ? 2 : 1
    }

    ; Numbers compare as numbers, anything else alphabetically.
    static Cmp(a, b) {
        if (IsNumber(a) && IsNumber(b))
            return a < b ? -1 : a > b ? 1 : 0
        return StrCompare(String(a), String(b))
    }

    ; Stable insertion sort of objects by one property.
    static SortBy(list, prop, desc := false) {
        Loop list.Length - 1 {
            i := A_Index + 1
            r := list[i], j := i - 1
            while (j >= 1 && (desc ? Files.Cmp(list[j].%prop%, r.%prop%) < 0 : Files.Cmp(list[j].%prop%, r.%prop%) > 0)) {
                list[j + 1] := list[j]
                j--
            }
            list[j + 1] := r
        }
    }

    static Age(ts) {
        if (ts = "")
            return ""
        m := DateDiff(A_Now, ts, "Minutes")
        if (m < 1)
            return "now"
        if (m < 60)
            return m "m"
        if (m < 1440)
            return (m // 60) "h"
        if (m < 1440 * 30)
            return (m // 1440) "d"
        return FormatTime(ts, "d MMM yy")
    }

    static Kind(path, isDir) {
        if isDir
            return "Folder"
        e := Files.Ext(path)
        return e != "" ? StrUpper(e) : "File"
    }

    static Size(path) {
        try {
            s := FileGetSize(path)
            return s < 1024 ? s " B" : s < 1048576 ? Round(s / 1024) " KB" : s < 1073741824 ? Round(s / 1048576, 1) " MB" : Round(s / 1073741824, 2) " GB"
        }
        return ""
    }

    static ModTime(path) {
        try return FileGetTime(path, "M")
        return ""
    }

    ; ---- listings ------------------------------------------------------------

    static Downloads() {
        try {
            p := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders", "{374DE290-123F-4565-9164-39C4925E467B}")
            p := Actions.Expand(p)
            if DirExist(p)
                return p
        }
        return EnvGet("USERPROFILE") "\Downloads"
    }

    static InboxFolders() {
        list := Store.Setting("inboxFolders", "")
        if !(list is Array) || !list.Length
            list := ["%DOWNLOADS%", "%DESKTOP%"]
        out := []
        for f in list {
            f := StrReplace(StrReplace(f, "%DOWNLOADS%", Files.Downloads()), "%DESKTOP%", A_Desktop)
            f := Actions.Expand(f)
            if DirExist(f)
                out.Push(f)
        }
        return out
    }

    ; Loose files/folders sitting in the inbox folders, newest first.
    static Inbox() {
        out := []
        for dir in Files.InboxFolders() {
            Loop Files dir "\*", "FD" {
                n := A_LoopFileName
                if (n = "desktop.ini" || n = "Thumbs.db" || RegExMatch(n, "i)\.(lnk|url|crdownload|part|tmp|partial)$") || InStr(A_LoopFileAttrib, "H"))
                    continue
                out.Push({path: A_LoopFileFullPath, dir: InStr(A_LoopFileAttrib, "D") ? 1 : 0, time: A_LoopFileTimeModified, from: dir})
            }
        }
        Files.SortBy(out, "time", true)
        return out
    }

    static InboxCount() {
        n := 0
        for dir in Files.InboxFolders()
            Loop Files dir "\*", "FD" {
                if (A_LoopFileName = "desktop.ini" || RegExMatch(A_LoopFileName, "i)\.(lnk|url|crdownload|part|tmp|partial)$") || InStr(A_LoopFileAttrib, "H"))
                    continue
                n++
            }
        return n
    }

    ; Folder contents: folders A-Z, then files newest first.
    static List(dir, limit := 3000) {
        dirs := [], fls := []
        Loop Files RTrim(dir, "\") "\*", "FD" {
            if InStr(A_LoopFileAttrib, "H") || InStr(A_LoopFileAttrib, "S")
                continue
            x := {path: A_LoopFileFullPath, dir: InStr(A_LoopFileAttrib, "D") ? 1 : 0, time: A_LoopFileTimeModified, name: StrLower(A_LoopFileName)}
            (x.dir ? dirs : fls).Push(x)
            if (dirs.Length + fls.Length >= limit)
                break
        }
        Files.SortBy(dirs, "name")
        Files.SortBy(fls, "time", true)
        for f in fls
            dirs.Push(f)
        return dirs
    }

    ; ---- actions -------------------------------------------------------------

    ; Opens a file; if an Open/Save dialog was in front, fills it in instead
    ; (pick a file in Alcadeias -> it lands in the browser's upload dialog).
    static Open(path, target := 0) {
        if Files.IsDir(path) {
            Places.Visit(path)
            Actions.OpenFolder(path, target)
            return
        }
        Places.Visit(path)
        cls := ""
        try cls := WinGetClass(target)
        if (cls = "#32770") {
            try {
                WinActivate(target)
                ControlSetText(path, "Edit1", target)
                ControlSend("{Enter}", "Edit1", target)
                return
            }
        }
        try Run('"' path '"')
        catch as e
            App.Status("Couldn't open " Files.Name(path) ": " e.Message, "error", true)
    }

    static Reveal(path) {
        Places.Visit(Files.Parent(path))
        Run('explorer.exe /select,"' path '"')
    }

    static CopyPaths(paths) {
        s := ""
        for p in paths
            s .= (s = "" ? "" : "`r`n") p
        A_Clipboard := s
        App.Status(paths.Length = 1 ? "Copied path: " paths[1] : "Copied " paths.Length " paths", "ok")
    }

    ; Free name in dest: "clip.mp4" -> "clip (2).mp4" when taken.
    static FreeName(dest, name) {
        if !FileExist(dest "\" name)
            return dest "\" name
        SplitPath(name, , , &ext, &stem)
        i := 2
        loop {
            cand := dest "\" stem " (" i ")" (ext != "" ? "." ext : "")
            if !FileExist(cand)
                return cand
            i++
        }
    }

    ; Moves files/folders into dest. Returns number moved. Undo with Files.Undo().
    static Move(paths, dest) {
        dest := RTrim(dest, "\")
        if !DirExist(dest) {
            App.Status("Folder not found: " dest, "error")
            return 0
        }
        batch := [], failed := 0
        for p in paths {
            if (StrLower(Files.Parent(p)) = StrLower(dest))
                continue
            to := Files.FreeName(dest, Files.Name(p))
            try {
                if Files.IsDir(p)
                    DirMove(p, to)
                else
                    FileMove(p, to)
                batch.Push([p, to])
                Places.LearnMove(p, dest)
                Places.Forget(p)
            } catch
                failed++
        }
        if batch.Length
            Files._undo := batch
        msg := "Moved " batch.Length " item" (batch.Length = 1 ? "" : "s") " to " Files.Name(dest)
        if failed
            msg .= " (" failed " failed: in use?)"
        App.Status(msg (batch.Length ? "   ·   Ctrl+Z to undo" : ""), failed ? "warn" : "ok")
        return batch.Length
    }

    static Rename(path, newName) {
        to := Files.Parent(path) "\" newName
        if FileExist(to) {
            App.Status("'" newName "' already exists there", "error")
            return ""
        }
        try {
            if Files.IsDir(path)
                DirMove(path, to)
            else
                FileMove(path, to)
        } catch as e {
            App.Status("Couldn't rename: " e.Message, "error")
            return ""
        }
        Files._undo := [[path, to]]
        Places.Forget(path)
        App.Status("Renamed to " newName "   ·   Ctrl+Z to undo", "ok")
        return to
    }

    static Recycle(paths) {
        n := 0
        for p in paths
            try {
                FileRecycle(p)
                Places.Forget(p)
                n++
            }
        App.Status("Moved " n " item" (n = 1 ? "" : "s") " to the Recycle Bin", "ok")
        return n
    }

    static Undo() {
        if !Files._undo.Length {
            App.Status("Nothing to undo", "")
            return false
        }
        n := 0
        i := Files._undo.Length
        while (i >= 1) {
            x := Files._undo[i]
            try {
                if Files.IsDir(x[2])
                    DirMove(x[2], x[1])
                else
                    FileMove(x[2], x[1])
                n++
            }
            i--
        }
        Files._undo := []
        App.Status("Undone: " n " item" (n = 1 ? "" : "s") " put back", "ok")
        return true
    }
}
