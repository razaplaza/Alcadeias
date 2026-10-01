; What happens when an item is triggered, by hotkey or from the dashboard.

class Actions {
    static FromHotkey(id) {
        item := Store.ById(id)
        if !item
            return
        if (item["type"] = "script") {
            ; a script's hotkey switches it on/off
            if Scripts.IsRunning(item) {
                Scripts.Stop(item)
                App.Status("Stopped '" item["name"] "'", "ok", true)
            } else if Scripts.Start(item)
                App.Status("Started '" item["name"] "'", "ok", true)
            Dashboard.RefreshSoon()
            return
        }
        Actions.Run(item, WinExist("A"))
    }

    ; target = the window that was active before the dashboard opened.
    static Run(item, target := 0) {
        switch item["type"] {
            case "layout": Layouts.Apply(item)
            case "app":    Actions.FocusOrLaunch(item)
            case "folder": Actions.OpenFolder(item["path"], target)
            case "link":   Actions.OpenLink(item)
            case "script": Editor.Open(item)
            case "project": Projects.Run(item, target)
            case "template": Templates.Create(item)
        }
    }

    ; ---- apps ------------------------------------------------------------

    ; Not open -> launch. Open -> bring to front. Already in front -> next window
    ; of that app, or minimize when it only has one.
    static FocusOrLaunch(item) {
        wins := []
        crit := item["exe"] != "" ? "ahk_exe " item["exe"] : ""
        if (crit = "" && item["title"] = "") {
            App.Status("App '" item["name"] "' needs an exe or a title to look for", "warn")
            return
        }
        for hwnd in WinGetList(crit)
            if Layouts.IsAppWindow(hwnd) && (item["title"] = "" || InStr(WinGetTitle(hwnd), item["title"]))
                wins.Push(hwnd)
        if !wins.Length {
            target := item["launch"] != "" ? item["launch"] : item["exe"]
            try Run(target)
            catch as e
                App.Status("Couldn't launch '" target "': " e.Message, "error", true)
            return
        }
        active := WinExist("A")
        isActive := false
        for h in wins
            if (h = active)
                isActive := true
        if !isActive {
            WinActivate(wins[1])
            return
        }
        if (wins.Length > 1)
            WinActivate(wins[wins.Length])   ; bottom of the stack = cycle through them
        else if item["minimizeIfActive"]
            WinMinimize(active)
    }

    ; ---- folders ---------------------------------------------------------

    ; Same three behaviors as the Razer script's NavTo:
    ;   file Open/Save dialog in front -> navigate the dialog
    ;   Explorer in front              -> retarget that window (no window spam)
    ;   anything else                  -> open a new Explorer window
    static OpenFolder(path, target := 0) {
        path := Actions.Expand(path)
        if !InStr(FileExist(path), "D") {
            App.Status("Folder not found: " path, "error", true)
            return
        }
        Places.Visit(path)
        cls := ""
        try cls := WinGetClass(target)
        if (cls = "#32770") {
            try {
                WinActivate(target)
                prev := ControlGetText("Edit1", target)
                ControlSetText(path, "Edit1", target)
                ControlSend("{Enter}", "Edit1", target)
                Sleep(120)
                ControlSetText(prev, "Edit1", target)
                return
            }
        }
        if (cls = "CabinetWClass") {
            WinActivate(target)
            if WinWaitActive(target, , 1) {
                Send("^l")
                Sleep(60)
                SendText(path)
                Send("{Enter}")
                return
            }
        }
        Run('explorer.exe "' path '"')
    }

    static OpenLink(item) {
        t := Actions.Expand(item["target"])
        try Run(t)
        catch as e
            App.Status("Couldn't open '" t "': " e.Message, "error", true)
    }

    ; Expands %USERPROFILE% style variables.
    static Expand(s) {
        while RegExMatch(s, "%(\w+)%", &m) {
            v := EnvGet(m[1])
            s := StrReplace(s, m[0], v != "" ? v : "{" m[1] "}")
        }
        return s
    }
}
