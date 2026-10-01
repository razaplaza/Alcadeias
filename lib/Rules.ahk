; Inbox auto-sort rules: "files like X -> do Y", run on demand (Sort now)
; or automatically as files arrive in Downloads/Desktop.
;
; A rule: name, match ("mp4 mov" = extensions, "IMG_*" = name pattern),
; action (move | unzip | recycle), dest folder, auto (0/1), olderDays.

class Rules {
    static Actions := [["move", "Move to a folder"], ["unzip", "Unzip into a folder, then recycle the .zip"], ["recycle", "Move to the Recycle Bin"]]

    static List() => Store.Data["rules"]

    static Start() => SetTimer(() => Rules.AutoTick(), 20000)

    static ActionLabel(key) {
        for a in Rules.Actions
            if (a[1] = key)
                return a[2]
        return key
    }

    static Describe(r) {
        s := r["action"] = "recycle" ? "Recycle" : r["action"] = "unzip" ? "Unzip → " Rules._DestName(r) : "→ " Rules._DestName(r)
        if (r["olderDays"] > 0)
            s .= "  (after " r["olderDays"] " days)"
        return s
    }

    static _DestName(r) => r["dest"] != "" ? Files.Name(Actions.Expand(r["dest"])) : "same folder"

    static Matches(r, path) {
        name := Files.Name(path)
        ext := Files.Ext(path)
        hit := false
        for pat in StrSplit(RegExReplace(r["match"], "[;,]", " "), " ") {
            if (pat = "")
                continue
            if (pat = "*")
                hit := true
            else if (InStr(pat, "*") || InStr(pat, "?"))
                hit := RegExMatch(name, "i)^" Rules._Wild(pat) "$") ? true : false
            else
                hit := StrLower(LTrim(pat, ".")) = ext
            if hit
                break
        }
        if !hit
            return false
        if (r["olderDays"] > 0) {
            t := Files.ModTime(path)
            if (t = "" || DateDiff(A_Now, t, "Days") < r["olderDays"])
                return false
        }
        return true
    }

    ; "IMG_*.mov" -> regex
    static _Wild(pat) {
        p := RegExReplace(pat, "[.+^$(){}\[\]|\\]", "\$0")
        return StrReplace(StrReplace(p, "*", ".*"), "?", ".")
    }

    ; First rule that wants this file, or "".
    static For(path, autoOnly := false) {
        for r in Rules.List()
            if (r["enabled"] && (!autoOnly || r["auto"]) && Rules.Matches(r, path))
                return r
        return ""
    }

    ; Applies rules to inbox files. Returns the number of files handled.
    static Run(autoOnly := false, quiet := false) {
        if !Rules.List().Length
            return 0
        groups := Map(), unzip := [], recycle := []
        for x in Files.Inbox() {
            if x.dir
                continue
            ; leave files alone while they may still be downloading
            if (DateDiff(A_Now, x.time, "Seconds") < 15)
                continue
            r := Rules.For(x.path, autoOnly)
            if !r
                continue
            switch r["action"] {
                case "recycle": recycle.Push(x.path)
                case "unzip":
                    if (Files.Ext(x.path) = "zip")
                        unzip.Push([x.path, r])
                default:
                    d := Actions.Expand(r["dest"])
                    if (d = "")
                        continue
                    if !groups.Has(d)
                        groups[d] := []
                    groups[d].Push(x.path)
            }
        }
        n := 0
        Files._undo := []
        for dest, paths in groups {
            DirCreate(dest)
            n += Files.Move(paths, dest, true, true)
        }
        for z in unzip
            n += Rules.Unzip(z[1], z[2]) ? 1 : 0
        if recycle.Length
            n += Files.Recycle(recycle, true)
        if (n && !quiet)
            App.Status("Auto-sorted " n " file" (n = 1 ? "" : "s") (groups.Count ? "   ·   Ctrl+Z in Alcadeias undoes the moves" : ""), "ok", true)
        if n
            Dashboard.RefreshSoon()
        return n
    }

    static Unzip(zip, r) {
        root := Actions.Expand(r["dest"])
        if (root = "")
            root := Files.Parent(zip)
        DirCreate(root)
        SplitPath(zip, , , , &stem)
        target := Files.FreeName(root, stem)
        ps := "Expand-Archive -LiteralPath '" StrReplace(zip, "'", "''") "' -DestinationPath '" StrReplace(target, "'", "''") "'"
        RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' ps '"', , "Hide")
        if !DirExist(target)
            return false
        try FileRecycle(zip)
        Places.Visit(target)
        return true
    }

    static AutoTick() {
        if !Store.Setting("autoSort", 1)
            return
        for r in Rules.List()
            if (r["enabled"] && r["auto"]) {
                Rules.Run(true)
                return
            }
    }

    static New(match := "", dest := "") {
        return Map("name", "", "match", match, "action", "move", "dest", dest, "auto", 0, "olderDays", 0, "enabled", 1)
    }
}
