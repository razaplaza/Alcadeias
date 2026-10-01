; Loads and saves data\config.json. Everything Alcadeias knows lives in there.

class Store {
    static Dir := A_ScriptDir "\data"
    static File := A_ScriptDir "\data\config.json"
    static Data := ""

    static Types := ["project", "template", "script", "layout", "app", "folder", "link"]
    static TypeNames := Map("project", "Project", "template", "Template", "script", "Script", "layout", "Layout",
        "app", "App", "folder", "Folder", "link", "Link")

    static Load() {
        DirCreate(Store.Dir)
        data := ""
        if FileExist(Store.File) {
            try data := JSON.Load(FileRead(Store.File, "UTF-8"))
            catch as e {
                bad := Store.Dir "\config.broken-" A_Now ".json"
                FileCopy(Store.File, bad, 1)
                MsgBox("data\config.json could not be read:`n" e.Message "`n`nA copy was saved as`n" bad "`nand Alcadeias will start with an empty setup.", "Alcadeias", "Icon!")
                data := ""
            }
        }
        if !(data is Map)
            data := Map()
        Store.Data := data
        Store._Defaults()
        return data
    }

    static _Defaults() {
        d := Store.Data
        if !d.Has("version")
            d["version"] := 1
        if !(d.Get("settings", "") is Map)
            d["settings"] := Map()
        if !(d.Get("items", "") is Array)
            d["items"] := []
        defaults := Map(
            "dashboardHotkey", "^!d",
            "ahkV1Path", "",
            "ahkV2Path", "",
            "editorPath", "",
            "scriptsDir", A_ScriptDir "\scripts",
            "vdaPath", "",
            "defaultVersion", "1",
            "startWithWindows", 0,
            "startHidden", 0,
            "everythingDll", "",
            "everythingExclude", "!\AppData\ !\$Recycle.Bin\ !\Windows\ !\node_modules\ !\.git\ !\Program Files",
            "inboxFolders", ["%DOWNLOADS%", "%DESKTOP%"]
        )
        for k, v in defaults
            if !d["settings"].Has(k)
                d["settings"][k] := v
        for item in d["items"]
            Store._ItemDefaults(item)
    }

    static _ItemDefaults(item) {
        if !item.Has("id")
            item["id"] := Store.NewId()
        for k in ["type", "name", "hotkey"]
            if !item.Has(k)
                item[k] := ""
        switch item["type"] {
            case "script":
                for k, v in Map("path", "", "ahkVersion", "auto", "autostart", 0, "autoApply", 1)
                    if !item.Has(k)
                        item[k] := v
            case "layout":
                for k, v in Map("minimizeOthers", 0, "desktop", 0)
                    if !item.Has(k)
                        item[k] := v
                if !(item.Get("slots", "") is Array)
                    item["slots"] := []
                for s in item["slots"]
                    Store.SlotDefaults(s)
            case "app":
                for k, v in Map("exe", "", "title", "", "launch", "", "minimizeIfActive", 1)
                    if !item.Has(k)
                        item[k] := v
            case "folder":
                if !item.Has("path")
                    item["path"] := ""
            case "link":
                if !item.Has("target")
                    item["target"] := ""
            case "project":
                for k, v in Map("root", "", "open", "", "layout", "", "openFolder", 1, "lastOpened", "", "template", "")
                    if !item.Has(k)
                        item[k] := v
            case "template":
                for k, v in Map("source", "", "dest", "", "pattern", "{date} {name}", "open", "", "layout", "")
                    if !item.Has(k)
                        item[k] := v
        }
    }

    static SlotDefaults(s) {
        for k, v in Map("exe", "", "title", "", "launch", "", "monitor", 1, "zone", "full",
                "x", 0, "y", 0, "w", 100, "h", 100, "state", "normal")
            if !s.Has(k)
                s[k] := v
        return s
    }

    static Save() {
        DirCreate(Store.Dir)
        tmp := Store.File ".tmp"
        try FileDelete(tmp)
        FileAppend(JSON.Dump(Store.Data), tmp, "UTF-8")
        if FileExist(Store.File)
            FileCopy(Store.File, Store.File ".bak", 1)
        FileMove(tmp, Store.File, 1)
    }

    static Settings => Store.Data["settings"]
    static Items => Store.Data["items"]

    static Setting(key, default := "") => Store.Data["settings"].Get(key, default)

    static NewId() {
        static n := 0
        n++
        return Format("{}{:04x}{:04x}", A_Now, Random(0, 0xFFFF), n)
    }

    static NewItem(type, name := "") {
        item := Map("id", Store.NewId(), "type", type, "name", name, "hotkey", "")
        Store._ItemDefaults(item)
        return item
    }

    static Add(item) {
        Store._ItemDefaults(item)
        Store.Items.Push(item)
        Store.Save()
        return item
    }

    static ById(id) {
        for item in Store.Items
            if (item["id"] = id)
                return item
        return ""
    }

    static Remove(id) {
        for i, item in Store.Items
            if (item["id"] = id) {
                Store.Items.RemoveAt(i)
                Store.Save()
                return true
            }
        return false
    }

    static OfType(type) {
        out := []
        for item in Store.Items
            if (item["type"] = type)
                out.Push(item)
        return out
    }

    ; Deep copy, so dialogs can edit without touching the live item until Save.
    static Clone(v) {
        if (v is Map) {
            m := Map()
            for k, x in v
                m[k] := Store.Clone(x)
            return m
        }
        if (v is Array) {
            a := []
            for x in v
                a.Push(Store.Clone(x))
            return a
        }
        return v
    }

    ; Replace a live item's contents with an edited copy (keeps the same object so references stay valid).
    static Replace(item, edited) {
        keys := []
        for k in item
            keys.Push(k)
        for k in keys
            item.Delete(k)
        for k, v in edited
            item[k] := v
        Store.Save()
    }
}
