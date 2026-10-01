; Starts, stops and hot-swaps your .ahk scripts. Each script runs as its own
; process, so if Alcadeias is closed or crashes your scripts keep running.

class Scripts {
    static _mtimes := Map()   ; path -> last seen modified time (for auto-apply)
    static LastError := Map() ; item id -> last validation error text

    ; ---- interpreters ----------------------------------------------------

    static V2Path() {
        p := Store.Setting("ahkV2Path")
        if (p != "" && FileExist(p))
            return p
        if (SubStr(A_AhkVersion, 1, 1) = "2")
            return A_AhkPath
        return ""
    }

    static V1Path() {
        p := Store.Setting("ahkV1Path")
        if (p != "" && FileExist(p))
            return p
        return Scripts.FindV1()
    }

    ; Looks in the usual install folders (the v2 installer puts v1 in a v1.1.x subfolder).
    static FindV1() {
        roots := []
        SplitPath(A_AhkPath, , &ahkDir)
        roots.Push(ahkDir, ahkDir "\..", A_ProgramFiles "\AutoHotkey")
        try roots.Push(EnvGet("ProgramFiles(x86)") "\AutoHotkey")
        try roots.Push(EnvGet("LOCALAPPDATA") "\Programs\AutoHotkey")
        best := ""
        for root in roots {
            Loop Files root "\v1*", "D" {
                for exe in ["AutoHotkeyU64.exe", "AutoHotkeyU32.exe", "AutoHotkey.exe"]
                    if FileExist(A_LoopFileFullPath "\" exe) && (best = "" || A_LoopFileFullPath > best) {
                        best := A_LoopFileFullPath "\" exe
                        break
                    }
            }
            if (best != "")
                return best
            for exe in ["AutoHotkeyU64.exe", "AutoHotkeyU32.exe"]
                if FileExist(root "\" exe)
                    return root "\" exe
        }
        return ""
    }

    ; "1" or "2" for a script item.
    static Version(item) {
        v := item.Get("ahkVersion", "auto")
        if (v = "1" || v = "2")
            return v
        return Scripts.DetectVersion(item["path"])
    }

    static DetectVersion(path) {
        head := ""
        try {
            f := FileOpen(path, "r")
            Loop 60 {
                if f.AtEOF
                    break
                head .= f.ReadLine() "`n"
            }
            f.Close()
        }
        if RegExMatch(head, "im)^\s*#Requires\s+AutoHotkey\s+(?:>=?\s*)?v?(\d)", &m)
            return m[1]
        return Store.Setting("defaultVersion", "1")
    }

    static Interpreter(item) => (Scripts.Version(item) = "2") ? Scripts.V2Path() : Scripts.V1Path()

    ; ---- running instances -----------------------------------------------

    ; Map of lowercased script path -> {hwnd, pid} for every running AHK script.
    static Running() {
        out := Map()
        prev := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            for hwnd in WinGetList("ahk_class AutoHotkey") {
                try {
                    title := WinGetTitle(hwnd)
                    path := RegExReplace(title, "\s+-\s+AutoHotkey v[\w.\-+]+$")
                    if (path = A_ScriptFullPath)
                        continue
                    out[StrLower(path)] := {hwnd: hwnd, pid: WinGetPID(hwnd)}
                }
            }
        }
        DetectHiddenWindows(prev)
        return out
    }

    static IsRunning(item, running := "") {
        running := running ? running : Scripts.Running()
        return running.Has(StrLower(item["path"]))
    }

    static Start(item) {
        if !FileExist(item["path"])
            return Scripts._Fail(item, "file not found: " item["path"])
        exe := Scripts.Interpreter(item)
        if (exe = "")
            return Scripts._Fail(item, "AutoHotkey v" Scripts.Version(item) " not found. Set its path in Settings.")
        SplitPath(item["path"], , &dir)
        try Run('"' exe '" "' item["path"] '"', dir)
        catch as e
            return Scripts._Fail(item, e.Message)
        Scripts._mtimes[item["path"]] := FileGetTime(item["path"], "M")
        return true
    }

    static Stop(item) {
        r := Scripts.Running()
        key := StrLower(item["path"])
        if !r.Has(key)
            return true
        info := r[key]
        prev := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try WinClose(info.hwnd)
        DetectHiddenWindows(prev)
        if ProcessWaitClose(info.pid, 2)
            try ProcessClose(info.pid)
        return true
    }

    ; Syntax-check, then replace the running copy. If the check fails the old
    ; copy keeps running untouched. Returns true on success.
    static _busy := Map()   ; path -> true while an apply is in progress

    static Apply(item, startIfStopped := true) {
        ; the syntax check waits on a process, which lets timers (the
        ; auto-apply watcher) run; never let two applies of one script overlap
        key := StrLower(item["path"])
        if Scripts._busy.Has(key)
            return false
        Scripts._busy[key] := true
        try return Scripts._Apply(item, startIfStopped)
        finally Scripts._busy.Delete(key)
    }

    static _Apply(item, startIfStopped) {
        Scripts.MarkSeen(item)   ; this version is being handled now
        err := Scripts.Validate(item)
        if (err != "") {
            Scripts.LastError[item["id"]] := err
            App.Status("'" item["name"] "' has an error, old version still running: " Scripts.FirstLine(err), "error")
            return false
        }
        if Scripts.LastError.Has(item["id"])
            Scripts.LastError.Delete(item["id"])
        wasRunning := Scripts.IsRunning(item)
        if (!wasRunning && !startIfStopped)
            return true
        Scripts.Stop(item)
        ok := Scripts.Start(item)
        if ok
            App.Status((wasRunning ? "Reloaded '" : "Started '") item["name"] "'", "ok")
        return ok
    }

    ; Returns "" if the script loads cleanly, otherwise the error text.
    static Validate(item) {
        exe := Scripts.Interpreter(item)
        if (exe = "")
            return "AutoHotkey v" Scripts.Version(item) " not found. Set its path in Settings."
        if !FileExist(item["path"])
            return "file not found: " item["path"]
        flag := (Scripts.Version(item) = "2") ? "/Validate" : '/iLib "NUL"'
        out := A_Temp "\alcadeias-validate.txt"
        try FileDelete(out)
        SplitPath(item["path"], , &dir)
        cmd := A_ComSpec ' /c ""' exe '" /ErrorStdOut=UTF-8 ' flag ' "' item["path"] '" 2>"' out '""'
        code := RunWait(cmd, dir, "Hide")
        text := ""
        try text := Trim(FileRead(out, "UTF-8"), " `t`r`n")
        try FileDelete(out)
        if (code = 0)
            return ""
        return text != "" ? text : "AutoHotkey reported an error (exit code " code ")"
    }

    ; "C:\x.ahk (12) : ==> Missing ")"`n  Specifically: foo(" -> "Line 12: Missing ")" (foo()"
    static FirstLine(text) {
        lines := StrSplit(Trim(text, " `r`n`t"), "`n", " `r`t")
        first := lines.Length ? lines[1] : ""
        if RegExMatch(first, "\((\d+)\)\s*:\s*==>\s*(.*)$", &m)
            first := "Line " m[1] ": " m[2]
        for l in lines
            if RegExMatch(l, "^Specifically:\s*(.+)$", &m) {
                first .= "  (" (StrLen(m[1]) > 60 ? SubStr(m[1], 1, 60) "…" : m[1]) ")"
                break
            }
        return first
    }

    ; Line number out of an AutoHotkey error message, or 0.
    static ErrorLine(text) {
        if RegExMatch(text, "\((\d+)\)\s*:", &m)
            return Integer(m[1])
        return 0
    }

    static _Fail(item, msg) {
        Scripts.LastError[item["id"]] := msg
        App.Status("'" item["name"] "': " msg, "error")
        return false
    }

    ; ---- files -----------------------------------------------------------

    ; Copy the current file into data\backups\<name>\ before overwriting it.
    static Backup(item) {
        if !FileExist(item["path"])
            return
        SplitPath(item["path"], , , , &stem)
        dir := Store.Dir "\backups\" stem
        DirCreate(dir)
        FileCopy(item["path"], dir "\" stem "_" A_Now ".ahk", 1)
        ; keep the newest 30
        backups := []
        Loop Files dir "\*.ahk"
            backups.Push(A_LoopFileFullPath)
        if (backups.Length > 30) {
            sorted := ""
            for f in backups
                sorted .= f "`n"
            sorted := Sort(RTrim(sorted, "`n"))
            for i, f in StrSplit(sorted, "`n")
                if (i <= backups.Length - 30)
                    try FileDelete(f)
        }
    }

    static BackupDir(item) {
        SplitPath(item["path"], , , , &stem)
        return Store.Dir "\backups\" stem
    }

    static Templates := Map(
        "Blank (AutoHotkey v2)", "#Requires AutoHotkey v2.0`n#SingleInstance Force`n`n; Your hotkeys go here, for example:`n; ^!t::MsgBox `"Hello from Alcadeias`"`n",
        "Blank (AutoHotkey v1)", "#Requires AutoHotkey v1.1`n#NoEnv`n#SingleInstance Force`n`n; Your hotkeys go here, for example:`n; ^!t::MsgBox, Hello from Alcadeias`n",
        "App-specific hotkeys (v1)", "#Requires AutoHotkey v1.1`n#NoEnv`n#SingleInstance Force`n`n#IfWinActive ahk_exe chrome.exe`n; hotkeys here only work in Chrome`n`n#IfWinActive`n"
    )

    ; Auto-apply: called on a timer. Reloads running scripts whose file changed on disk.
    static Watch() {
        running := ""
        for item in Store.OfType("script") {
            path := item["path"]
            if !FileExist(path)
                continue
            t := FileGetTime(path, "M")
            if !Scripts._mtimes.Has(path) {
                Scripts._mtimes[path] := t
                continue
            }
            if (Scripts._mtimes[path] = t || Scripts._busy.Has(StrLower(path)))
                continue
            Scripts._mtimes[path] := t
            if !item["autoApply"]
                continue
            running := running ? running : Scripts.Running()
            if running.Has(StrLower(path))
                Scripts.Apply(item, false)
        }
    }

    static MarkSeen(item) {
        if FileExist(item["path"])
            Scripts._mtimes[item["path"]] := FileGetTime(item["path"], "M")
    }

    static StartAutostart() {
        running := Scripts.Running()
        for item in Store.OfType("script")
            if item["autostart"] && !running.Has(StrLower(item["path"]))
                Scripts.Start(item)
    }
}
