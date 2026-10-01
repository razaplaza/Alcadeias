; Layout engine: finds (or launches) the windows a layout needs and puts each
; one in its zone on the right monitor.
;
; A slot is: which window (exe + optional title text), how to launch it if it
; isn't open, which monitor, which zone (preset or custom %), and a state.

class Layouts {
    ; key, label, x%, y%, w%, h%  (relative to the monitor's work area, i.e. minus taskbar)
    static Zones := [
        ["full",             "Full (fill work area)", 0, 0, 100, 100],
        ["left-half",        "Left half",             0, 0, 50, 100],
        ["right-half",       "Right half",            50, 0, 50, 100],
        ["top-half",         "Top half",              0, 0, 100, 50],
        ["bottom-half",      "Bottom half",           0, 50, 100, 50],
        ["left-third",       "Left third",            0, 0, 33.33, 100],
        ["middle-third",     "Middle third",          33.33, 0, 33.34, 100],
        ["right-third",      "Right third",           66.67, 0, 33.33, 100],
        ["left-two-thirds",  "Left two thirds",       0, 0, 66.67, 100],
        ["right-two-thirds", "Right two thirds",      33.33, 0, 66.67, 100],
        ["top-left",         "Top-left quarter",      0, 0, 50, 50],
        ["top-right",        "Top-right quarter",     50, 0, 50, 50],
        ["bottom-left",      "Bottom-left quarter",   0, 50, 50, 50],
        ["bottom-right",     "Bottom-right quarter",  50, 50, 50, 50],
        ["center",           "Centered (70%)",        15, 10, 70, 80],
        ["custom",           "Custom (x/y/w/h in %)", 0, 0, 100, 100]
    ]

    static States := [["normal", "Fit to zone"], ["maximized", "Maximized"], ["fullscreen", "Fullscreen (F11)"]]

    static Browsers := Map("chrome.exe", " - Google Chrome", "msedge.exe", " - Microsoft​ Edge",
        "firefox.exe", " — Mozilla Firefox", "brave.exe", " - Brave", "opera.exe", " - Opera", "vivaldi.exe", " - Vivaldi")

    static ZoneLabel(key) {
        for z in Layouts.Zones
            if (z[1] = key)
                return z[2]
        return key
    }

    static StateLabel(key) {
        for s in Layouts.States
            if (s[1] = key)
                return s[2]
        return key
    }

    ; [x%, y%, w%, h%] for a slot.
    static ZoneRect(slot) {
        if (slot["zone"] != "custom")
            for z in Layouts.Zones
                if (z[1] = slot["zone"])
                    return [z[3], z[4], z[5], z[6]]
        return [slot["x"], slot["y"], slot["w"], slot["h"]]
    }

    ; Short description, e.g. "chrome.exe 'Claude' → M1 right half"
    static SlotText(slot) {
        who := slot["exe"] != "" ? slot["exe"] : "any app"
        if (slot["title"] != "")
            who .= " '" slot["title"] "'"
        where := "M" slot["monitor"] " " StrLower(Layouts.ZoneLabel(slot["zone"]))
        if (slot["state"] = "maximized")
            where := "M" slot["monitor"] " maximized"
        else if (slot["state"] = "fullscreen")
            where := "M" slot["monitor"] " fullscreen"
        return who " → " where
    }

    ; ---- monitors ------------------------------------------------------

    static MonitorNames() {
        out := []
        prim := MonitorGetPrimary()
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &l, &t, &r, &b)
            out.Push(A_Index " — " (r - l) "×" (b - t) (A_Index = prim ? " (primary)" : ""))
        }
        return out
    }

    static MonitorOf(hwnd) {
        try {
            WinGetPos(&x, &y, &w, &h, hwnd)
            cx := x + w // 2, cy := y + h // 2
            Loop MonitorGetCount() {
                MonitorGet(A_Index, &l, &t, &r, &b)
                if (cx >= l && cx < r && cy >= t && cy < b)
                    return A_Index
            }
        }
        return MonitorGetPrimary()
    }

    static ClampMonitor(n) {
        n := Integer(n)
        return (n >= 1 && n <= MonitorGetCount()) ? n : MonitorGetPrimary()
    }

    ; ---- window helpers --------------------------------------------------

    ; Roughly "would this window show in Alt+Tab".
    static IsAppWindow(hwnd) {
        static ownPid := DllCall("GetCurrentProcessId")
        try {
            if !DllCall("IsWindowVisible", "Ptr", hwnd)
                return false
            if (WinGetTitle(hwnd) = "")
                return false
            if (WinGetPID(hwnd) = ownPid)
                return false
            ex := WinGetExStyle(hwnd)
            if (ex & 0x80)   ; WS_EX_TOOLWINDOW
                return false
            owner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")
            if (owner && !(ex & 0x40000))   ; owned popups unless WS_EX_APPWINDOW
                return false
            cls := WinGetClass(hwnd)
            for c in ["Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Windows.UI.Core.CoreWindow"]
                if (cls = c)
                    return false
            return true
        }
        return false
    }

    ; Cloaked = on another virtual desktop (or a hidden UWP shell window).
    static IsCloaked(hwnd) {
        c := 0
        try DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "UInt*", &c, "UInt", 4)
        return c != 0
    }

    ; Invisible resize-border sizes [left, top, right, bottom] (Windows 10/11 add ~7px).
    static FrameOffsets(hwnd) {
        WinGetPos(&x, &y, &w, &h, hwnd)
        rect := Buffer(16, 0)
        try {
            if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", rect, "UInt", 16) != 0
                return [0, 0, 0, 0]
        } catch
            return [0, 0, 0, 0]
        fl := NumGet(rect, 0, "Int"), ft := NumGet(rect, 4, "Int"), fr := NumGet(rect, 8, "Int"), fb := NumGet(rect, 12, "Int")
        return [fl - x, ft - y, (x + w) - fr, (y + h) - fb]
    }

    ; Visible rectangle [x, y, w, h] (without invisible borders).
    static VisibleRect(hwnd) {
        WinGetPos(&x, &y, &w, &h, hwnd)
        o := Layouts.FrameOffsets(hwnd)
        return [x + o[1], y + o[2], w - o[1] - o[3], h - o[2] - o[4]]
    }

    static IsFullscreen(hwnd) {
        try {
            if (WinGetMinMax(hwnd) != 0)
                return false
            WinGetPos(&x, &y, &w, &h, hwnd)
            MonitorGet(Layouts.MonitorOf(hwnd), &l, &t, &r, &b)
            return (x = l && y = t && w = r - l && h = b - t)
        }
        return false
    }

    ; First matching window not already used. Prefers windows on this desktop;
    ; returns a cloaked match only if allowCloaked and nothing else fits.
    static Find(slot, used, allowCloaked := true) {
        crit := slot["exe"] != "" ? "ahk_exe " slot["exe"] : ""
        fallback := 0
        for hwnd in WinGetList(crit) {
            if used.Has(hwnd) || !Layouts.IsAppWindow(hwnd)
                continue
            if (slot["title"] != "" && !InStr(WinGetTitle(hwnd), slot["title"]))
                continue
            if Layouts.IsCloaked(hwnd) {
                if (!fallback)
                    fallback := hwnd
                continue
            }
            return hwnd
        }
        return allowCloaked ? fallback : 0
    }

    static LaunchAndWait(slot, used, timeoutMs := 15000) {
        try Run(slot["launch"])
        catch as e {
            App.Status("Couldn't launch '" slot["launch"] "': " e.Message, "error")
            return 0
        }
        deadline := A_TickCount + timeoutMs
        while (A_TickCount < deadline) {
            Sleep(150)
            if (hwnd := Layouts.Find(slot, used, false))
                return hwnd
        }
        return 0
    }

    ; Put one window where the slot says.
    static Place(hwnd, slot) {
        mon := Layouts.ClampMonitor(slot["monitor"])
        MonitorGetWorkArea(mon, &L, &T, &R, &B)
        state := slot["state"]

        ; a fullscreen window must leave fullscreen before it can move
        if Layouts.IsFullscreen(hwnd) && !(state = "fullscreen" && Layouts.MonitorOf(hwnd) = mon) {
            WinActivate(hwnd)
            Sleep(100)
            Send("{F11}")
            Sleep(350)
        }

        if (state = "maximized" || state = "fullscreen") {
            if (state = "fullscreen" && Layouts.IsFullscreen(hwnd) && Layouts.MonitorOf(hwnd) = mon)
                return
            if (WinGetMinMax(hwnd) != 0)
                WinRestore(hwnd)
            WinMove(L + 40, T + 40, (R - L) // 2, (B - T) // 2, hwnd)   ; hop onto the monitor first
            WinMaximize(hwnd)
            if (state = "fullscreen") {
                WinActivate(hwnd)
                Sleep(150)
                Send("{F11}")
            }
            return
        }

        z := Layouts.ZoneRect(slot)
        x := Round(L + (R - L) * z[1] / 100), y := Round(T + (B - T) * z[2] / 100)
        w := Round((R - L) * z[3] / 100), h := Round((B - T) * z[4] / 100)
        if (WinGetMinMax(hwnd) != 0)
            WinRestore(hwnd)
        o := Layouts.FrameOffsets(hwnd)
        WinMove(x - o[1], y - o[2], w + o[1] + o[3], h + o[2] + o[4], hwnd)
    }

    ; ---- applying a whole layout ---------------------------------------

    static Apply(item) {
        slots := item["slots"]
        if !slots.Length {
            App.Status("Layout '" item["name"] "' has no windows yet. Edit it to add some.", "warn")
            return
        }
        if (item["desktop"] > 0) {
            if VDA.Available() {
                VDA.GoTo(item["desktop"] - 1)
                Sleep(250)
            } else
                App.Status("Layout wants desktop " item["desktop"] " but VirtualDesktopAccessor.dll isn't set in Settings", "warn")
        }

        used := Map(), order := [], launched := [], missing := []
        for i, slot in slots {
            hwnd := Layouts.Find(slot, used)
            if (hwnd && Layouts.IsCloaked(hwnd)) {
                if VDA.Available()
                    VDA.MoveHere(hwnd)
                else
                    hwnd := 0
            }
            if (!hwnd && slot["launch"] != "") {
                hwnd := Layouts.LaunchAndWait(slot, used)
                if hwnd
                    launched.Push(i)
            }
            if !hwnd {
                missing.Push(slot["exe"] (slot["title"] != "" ? " '" slot["title"] "'" : ""))
                continue
            }
            used[hwnd] := i
            order.Push(hwnd)
            try Layouts.Place(hwnd, slot)
        }

        ; freshly launched apps often restore their own saved position a moment later
        ; freshly launched apps (Obsidian, Chrome) like to restore their own saved
        ; size a moment after opening, so put them back twice
        if launched.Length {
            for wait in [1000, 2000] {
                Sleep(wait)
                for hwnd, i in used
                    for li in launched
                        if (li = i)
                            try Layouts.Place(hwnd, slots[i])
            }
        }

        if item["minimizeOthers"] {
            for hwnd in WinGetList() {
                if used.Has(hwnd) || !Layouts.IsAppWindow(hwnd) || Layouts.IsCloaked(hwnd)
                    continue
                try if (WinGetMinMax(hwnd) != -1)
                    WinMinimize(hwnd)
            }
        }

        ; bring them forward; slot 1 ends up focused
        i := order.Length
        while (i >= 1) {
            try WinActivate(order[i])
            i--
        }

        msg := "Layout '" item["name"] "': " order.Length "/" slots.Length " windows placed"
        for slot in slots
            if (slot["monitor"] > MonitorGetCount()) {
                msg .= " (monitor " slot["monitor"] " isn't connected, used the primary)"
                break
            }
        if missing.Length {
            list := ""
            for m in missing
                list .= (list = "" ? "" : ", ") m
            App.Status(msg ". Not found: " list, "warn")
        } else
            App.Status(msg, "ok")
    }

    ; ---- capture -------------------------------------------------------

    ; Slots describing the windows currently on screen (this desktop, not minimized).
    static Capture() {
        out := []
        for hwnd in WinGetList() {
            if !Layouts.IsAppWindow(hwnd) || Layouts.IsCloaked(hwnd)
                continue
            try {
                mm := WinGetMinMax(hwnd)
                if (mm = -1)
                    continue
                exe := WinGetProcessName(hwnd)
                title := WinGetTitle(hwnd)
                path := ""
                try path := WinGetProcessPath(hwnd)
                mon := Layouts.MonitorOf(hwnd)
                MonitorGetWorkArea(mon, &L, &T, &R, &B)
                state := mm = 1 ? "maximized" : Layouts.IsFullscreen(hwnd) ? "fullscreen" : "normal"
                v := Layouts.VisibleRect(hwnd)
                px := Round((v[1] - L) * 100 / (R - L), 1), py := Round((v[2] - T) * 100 / (B - T), 1)
                pw := Round(v[3] * 100 / (R - L), 1), ph := Round(v[4] * 100 / (B - T), 1)
                slot := Store.SlotDefaults(Map(
                    "exe", exe, "monitor", mon, "state", state,
                    "x", px, "y", py, "w", pw, "h", ph,
                    "zone", Layouts.MatchZone(px, py, pw, ph)))
                if Layouts.Browsers.Has(StrLower(exe))
                    slot["title"] := Layouts.StableTitle(exe, title)
                slot["launch"] := path != "" ? '"' path '"' : exe
                slot["_title"] := title
                slot["_hwnd"] := hwnd
                out.Push(slot)
            }
        }
        ; browsers: read each window's web address so the layout can reopen it
        ; on its own (--new-window <url>)
        active := WinExist("A")
        for slot in out {
            if !Layouts.Browsers.Has(StrLower(slot["exe"]))
                continue
            url := Layouts.BrowserUrl(slot["_hwnd"])
            slot["_url"] := url
            ; without an address, a launch would only open an empty window
            slot["launch"] := url != "" ? slot["launch"] ' --new-window "' url '"' : ""
        }
        if active
            try WinActivate(active)
        return out
    }

    ; Address-bar URL of a browser window. Reads it through UI Automation (no
    ; keystrokes); falls back to Ctrl+L / Ctrl+C with the clipboard restored.
    static BrowserUrl(hwnd) {
        url := ""
        try url := Layouts._UrlViaUIA(hwnd)
        if (url = "")
            url := Layouts._UrlViaKeys(hwnd)
        return Layouts.NormalizeUrl(url)
    }

    ; The address bar often hides the scheme ("claude.ai/code", "C:/Users/...").
    static NormalizeUrl(url) {
        url := Trim(url)
        if (url = "" || InStr(url, " ") || InStr(url, "`n"))
            return ""
        if RegExMatch(url, "^[A-Za-z]:[/\\]")
            return "file:///" StrReplace(url, "\", "/")
        if RegExMatch(url, "i)^([a-z][\w+.-]*://|about:|chrome:|data:|mailto:)")
            return url
        if RegExMatch(url, "^[\w-]+(\.[\w-]+)+(:\d+)?(/|$)") || RegExMatch(url, "i)^localhost(:\d+)?(/|$)")
            return "https://" url
        return ""
    }

    static _UrlViaUIA(hwnd) {
        uia := ComObject("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
        el := 0, cond := 0, addr := 0, url := ""
        try {
            ComCall(6, uia, "Ptr", hwnd, "Ptr*", &el)                     ; ElementFromHandle
            v := Buffer(24, 0)
            NumPut("UShort", 3, v, 0), NumPut("Int", 50004, v, 8)       ; VT_I4, Edit control type
            ComCall(23, uia, "Int", 30003, "Ptr", v, "Ptr*", &cond)      ; CreatePropertyCondition(ControlType)
            ComCall(5, el, "Int", 4, "Ptr", cond, "Ptr*", &addr)         ; FindFirst(Descendants) = address bar
            if addr {
                out := Buffer(24, 0)
                ComCall(10, addr, "Int", 30045, "Ptr", out)              ; GetCurrentPropertyValue(Value)
                if (NumGet(out, 0, "UShort") = 8)                          ; VT_BSTR
                    url := StrGet(NumGet(out, 8, "Ptr"), "UTF-16")
                DllCall("oleaut32\VariantClear", "Ptr", out)
            }
        }
        for p in [addr, cond, el]
            if p
                ObjRelease(p)
        return url
    }

    static _UrlViaKeys(hwnd) {
        saved := ClipboardAll()
        A_Clipboard := ""
        url := ""
        try {
            WinActivate(hwnd)
            if WinWaitActive(hwnd, , 2) {
                Sleep(150)
                Send("{Ctrl down}l{Ctrl up}")
                Sleep(250)
                Send("{Ctrl down}c{Ctrl up}")
                if ClipWait(1)
                    url := Trim(A_Clipboard)
                Send("{Esc}")
                Sleep(80)
            }
        }
        A_Clipboard := saved
        return url
    }

    ; Part of a browser title that won't change much: site names usually come
    ; last ("Some video - YouTube" -> "YouTube").
    static StableTitle(exe, title) {
        t := Layouts.CleanTitle(exe, title)
        parts := StrSplit(RegExReplace(t, "\s+[-|—·]\s+", "`n"), "`n", " `t")
        return parts.Length > 1 && parts[parts.Length] != "" ? parts[parts.Length] : t
    }

    static CleanTitle(exe, title) {
        suffix := Layouts.Browsers.Get(StrLower(exe), "")
        if (suffix != "" && SubStr(title, -StrLen(suffix)) = suffix)
            title := SubStr(title, 1, StrLen(title) - StrLen(suffix))
        return title
    }

    static MatchZone(x, y, w, h, tol := 1.5) {
        for z in Layouts.Zones {
            if (z[1] = "custom")
                continue
            if (Abs(z[3] - x) <= tol && Abs(z[4] - y) <= tol && Abs(z[5] - w) <= tol && Abs(z[6] - h) <= tol)
                return z[1]
        }
        return "custom"
    }

    ; ---- previews ------------------------------------------------------

    ; Shows translucent boxes where each slot will go.
    static Preview(slots, ms := 2500) {
        overlays := []
        for i, slot in slots {
            mon := Layouts.ClampMonitor(slot["monitor"])
            if (slot["state"] = "maximized")
                MonitorGetWorkArea(mon, &L, &T, &R, &B), z := [0, 0, 100, 100]
            else if (slot["state"] = "fullscreen")
                MonitorGet(mon, &L, &T, &R, &B), z := [0, 0, 100, 100]
            else
                MonitorGetWorkArea(mon, &L, &T, &R, &B), z := Layouts.ZoneRect(slot)
            x := Round(L + (R - L) * z[1] / 100), y := Round(T + (B - T) * z[2] / 100)
            w := Round((R - L) * z[3] / 100), h := Round((B - T) * z[4] / 100)
            name := slot["title"] != "" ? slot["title"] : slot["exe"]
            sub := slot["state"] = "normal" ? Layouts.ZoneLabel(slot["zone"]) : Layouts.StateLabel(slot["state"])
            if (slot["monitor"] > MonitorGetCount())
                sub .= " · monitor " slot["monitor"] " not connected, using primary"
            overlays.Push(Layouts._Overlay(x + 6, y + 6, w - 12, h - 12, i "  " name, sub))
        }
        SetTimer(() => Layouts._Destroy(overlays), -ms)
    }

    static IdentifyMonitors(ms := 2500) {
        overlays := []
        prim := MonitorGetPrimary()
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &l, &t, &r, &b)
            w := 360, h := 220
            overlays.Push(Layouts._Overlay(l + (r - l - w) // 2, t + (b - t - h) // 2, w, h,
                "Monitor " A_Index, (r - l) "×" (b - t) (A_Index = prim ? " · primary" : "")))
        }
        SetTimer(() => Layouts._Destroy(overlays), -ms)
    }

    static _Overlay(x, y, w, h, title, sub) {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
        g.BackColor := Theme.Accent
        g.MarginX := 0, g.MarginY := 0
        g.SetFont("s28 w700 cFFFFFF", Theme.Font)
        g.Add("Text", "x0 y" (h // 2 - 50) " w" w " h56 Center BackgroundTrans", title)
        g.SetFont("s13 w400 cFFFFFF", Theme.Font)
        g.Add("Text", "x0 y" (h // 2 + 10) " w" w " h30 Center BackgroundTrans", sub)
        g.Show(Format("x{} y{} w{} h{} NoActivate", x, y, w, h))
        WinSetTransparent(170, g)
        return g
    }

    static _Destroy(list) {
        for g in list
            try g.Destroy()
    }
}

; VirtualDesktopAccessor.dll wrapper (optional; path set in Settings).
class VDA {
    static _h := 0
    static _path := ""

    static Available() {
        p := Store.Setting("vdaPath")
        if (p = "" || !FileExist(p))
            return false
        if (VDA._h && VDA._path = p)
            return true
        VDA._h := DllCall("LoadLibrary", "Str", p, "Ptr")
        VDA._path := p
        return VDA._h != 0
    }

    static _Fn(name) => DllCall("GetProcAddress", "Ptr", VDA._h, "AStr", name, "Ptr")

    static GoTo(n) {
        if VDA.Available()
            try DllCall(VDA._Fn("GoToDesktopNumber"), "Int", n)
    }

    static Current() {
        if VDA.Available()
            try return DllCall(VDA._Fn("GetCurrentDesktopNumber"), "Int")
        return -1
    }

    static MoveHere(hwnd) {
        cur := VDA.Current()
        if (cur >= 0)
            try DllCall(VDA._Fn("MoveWindowToDesktopNumber"), "Ptr", hwnd, "Int", cur)
    }
}
