; Colors, dark-mode helpers and the flat button / toggle controls used everywhere.

class Theme {
    static Bg       := "131418"   ; window background
    static Panel    := "1C1D22"   ; cards, list
    static Panel2   := "26272E"   ; inputs, buttons
    static Hover    := "33343D"
    static Text     := "E7E7EC"
    static Muted    := "8C8E9A"
    static Accent   := "7C6CF2"   ; Alcadeias violet
    static AccentHi := "9488F7"
    static Danger   := "F06A6A"
    static Ok       := "4ADE80"
    static Warn     := "F5B544"
    static Font     := "Segoe UI"
    static Mono     := "Consolas"

    ; Call once at startup: dark context menus and tray menu where Windows supports it.
    static InitApp() {
        try {
            ux := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
            setMode := DllCall("GetProcAddress", "Ptr", ux, "Ptr", 135, "Ptr")
            flush := DllCall("GetProcAddress", "Ptr", ux, "Ptr", 136, "Ptr")
            if setMode
                DllCall(setMode, "Int", 2)   ; ForceDark
            if flush
                DllCall(flush)
        }
    }

    ; New themed window.
    static NewGui(title, opts := "") {
        g := Gui(opts, title)
        g.BackColor := Theme.Bg
        g.MarginX := 0, g.MarginY := 0
        g.SetFont("s10 c" Theme.Text, Theme.Font)
        return g
    }

    ; Dark title bar. Must run after the window exists (any time before Show is fine).
    static DarkTitle(g) {
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", 20, "Int*", 1, "Int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
    }

    static SetTheme(hwnd, name) {
        try DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", name, "Ptr", 0)
    }

    ; Text label.
    static Label(g, opts, text, color := "", size := 10, bold := false) {
        c := g.Add("Text", opts " BackgroundTrans", text)
        c.SetFont("s" size " c" (color != "" ? color : Theme.Text) (bold ? " w600" : " w400"), Theme.Font)
        return c
    }

    ; Single-line or multi-line input.
    static Edit(g, opts, text := "", mono := false) {
        c := g.Add("Edit", opts " -E0x200 Background" Theme.Panel2, text)
        c.SetFont("s10 c" Theme.Text, mono ? Theme.Mono : Theme.Font)
        Theme.SetTheme(c.Hwnd, "DarkMode_CFD")
        return c
    }

    static Cue(edit, text) {
        ; EM_SETCUEBANNER, show even while focused
        SendMessage(0x1501, 1, StrPtr(text), edit)
    }

    static DDL(g, opts, items) {
        c := g.Add("DropDownList", opts " Background" Theme.Panel2, items)
        c.SetFont("s10 c" Theme.Text, Theme.Font)
        Theme.SetTheme(c.Hwnd, "DarkMode_CFD")
        return c
    }

    ; Dark list view with roomy rows.
    static ListView(g, opts, cols, rowHeight := 30, multi := false) {
        lv := g.Add("ListView", opts (multi ? "" : " -Multi") " -E0x200 +LV0x10000 Background" Theme.Panel, cols)
        lv.SetFont("s10 c" Theme.Text, Theme.Font)
        Theme.SetTheme(lv.Hwnd, "DarkMode_Explorer")
        hdr := SendMessage(0x101F, 0, 0, lv)   ; LVM_GETHEADER
        if hdr
            Theme.SetTheme(hdr, "DarkMode_ItemsView")
        ; a 1px-wide image list is the standard trick to get taller rows
        il := DllCall("comctl32\ImageList_Create", "Int", 1, "Int", rowHeight, "UInt", 0x21, "Int", 1, "Int", 1, "Ptr")
        lv.SetImageList(il, 1)
        return lv
    }

    ; Horizontal divider line.
    static Line(g, x, y, w, color := "") {
        return g.Add("Text", Format("x{} y{} w{} h1 Background{}", x, y, w, color != "" ? color : Theme.Panel2))
    }
}

; A flat, clickable text "button" with hover highlight.
class FlatButton {
    static Registry := Map()
    static Hot := 0
    static _watchFn := ObjBindMethod(FlatButton, "_Watch")

    __New(g, opts, text, onClick, kind := "normal") {
        this.kind := kind
        this.active := false
        this.SetColors(kind)
        this.ctrl := g.Add("Text", opts " 0x200 Center Background" this.bg, text)
        this.ctrl.SetFont("s10 c" this.fg " w600", Theme.Font)
        this.onClick := onClick
        this.ctrl.OnEvent("Click", (*) => this.onClick.Call(this))
        FlatButton.Registry[this.ctrl.Hwnd] := this
        static hooked := false
        if !hooked {
            OnMessage(0x200, ObjBindMethod(FlatButton, "_OnMouseMove"))
            hooked := true
        }
    }

    SetColors(kind) {
        switch kind {
            case "accent":  this.bg := Theme.Accent, this.bgHover := Theme.AccentHi, this.fg := "FFFFFF"
            case "danger":  this.bg := Theme.Panel2, this.bgHover := Theme.Hover, this.fg := Theme.Danger
            case "nav":     this.bg := Theme.Bg, this.bgHover := Theme.Panel2, this.fg := Theme.Muted
            case "tab":     this.bg := Theme.Bg, this.bgHover := Theme.Panel, this.fg := Theme.Muted
            default:        this.bg := Theme.Panel2, this.bgHover := Theme.Hover, this.fg := Theme.Text
        }
    }

    Text {
        get => this.ctrl.Text
        set => this.ctrl.Text := value
    }

    Visible {
        get => this.ctrl.Visible
        set => this.ctrl.Visible := value
    }

    ; For nav items: highlight the selected one.
    SetActive(on) {
        this.active := on
        if (this.kind = "nav") {
            this.ctrl.SetFont("c" (on ? Theme.Text : Theme.Muted))
            this._Paint(on ? Theme.Panel2 : this.bg)
        } else if (this.kind = "tab") {
            this.ctrl.SetFont("c" (on ? Theme.Text : Theme.Muted))
            this.ctrl.Redraw()
        }
    }

    Move(x?, y?, w?, h?) => this.ctrl.Move(x?, y?, w?, h?)

    _Paint(color) {
        this.ctrl.Opt("Background" color)
        this.ctrl.Redraw()
    }

    _Rest() => (this.active && this.kind = "nav") ? Theme.Panel2 : this.bg

    static _OnMouseMove(wParam, lParam, msg, hwnd) {
        if (hwnd = FlatButton.Hot)
            return
        FlatButton._Leave()
        if FlatButton.Registry.Has(hwnd) {
            b := FlatButton.Registry[hwnd]
            b._Paint(b.bgHover)
            FlatButton.Hot := hwnd
            SetTimer(FlatButton._watchFn, 60)
        }
    }

    static _Watch() {
        MouseGetPos(, , , &ctl, 2)
        if (ctl != FlatButton.Hot)
            FlatButton._Leave()
    }

    static _Leave() {
        if (FlatButton.Hot && FlatButton.Registry.Has(FlatButton.Hot)) {
            b := FlatButton.Registry[FlatButton.Hot]
            try b._Paint(b._Rest())
        }
        FlatButton.Hot := 0
        SetTimer(FlatButton._watchFn, 0)
    }

    ; Call when a window is destroyed so stale handles don't linger.
    static Forget(g) {
        dead := []
        for hwnd, b in FlatButton.Registry
            if (b.ctrl.Gui.Hwnd = g.Hwnd)
                dead.Push(hwnd)
        for hwnd in dead
            FlatButton.Registry.Delete(hwnd)
        if !FlatButton.Registry.Has(FlatButton.Hot)
            FlatButton.Hot := 0
    }
}

; A checkbox drawn as text so it looks right on the dark background.
class Toggle {
    __New(g, opts, text, value := false, onChange := "") {
        this.label := text
        this.v := value ? 1 : 0
        this.onChange := onChange
        this.ctrl := g.Add("Text", opts " 0x200 BackgroundTrans", "")
        this.ctrl.SetFont("s10 c" Theme.Text, "Segoe UI Symbol")
        this.ctrl.OnEvent("Click", (*) => this.Set(!this.v, true))
        this._Draw()
    }

    Set(v, fire := false) {
        this.v := v ? 1 : 0
        this._Draw()
        if (fire && this.onChange)
            this.onChange.Call(this)
    }

    Value => this.v

    _Draw() => this.ctrl.Text := (this.v ? "☑  " : "☐  ") . this.label
}
