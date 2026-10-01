; Minimal JSON reader/writer for Alcadeias.
; Objects load as Map, arrays as Array. true/false load as 1/0, null as "".

class JSON {
    static Load(text) {
        pos := 1
        val := JSON._Value(text, &pos)
        JSON._Ws(text, &pos)
        if (pos <= StrLen(text))
            throw Error("JSON: unexpected data at position " pos)
        return val
    }

    static Dump(val, indent := "  ", _lvl := 0) {
        pad := "", padIn := ""
        if (indent != "") {
            Loop _lvl
                pad .= indent
            padIn := pad . indent
        }
        nl := (indent != "") ? "`n" : ""
        sep := (indent != "") ? ": " : ":"
        if (val is Map) {
            if (val.Count = 0)
                return "{}"
            out := "{" nl
            for k, v in val
                out .= padIn . JSON._Str(String(k)) . sep . JSON.Dump(v, indent, _lvl + 1) . "," . nl
            return RTrim(out, ",`n") . nl . pad . "}"
        }
        if (val is Array) {
            if (val.Length = 0)
                return "[]"
            out := "[" nl
            for v in val
                out .= padIn . JSON.Dump(v, indent, _lvl + 1) . "," . nl
            return RTrim(out, ",`n") . nl . pad . "]"
        }
        if (val is Integer || val is Float)
            return String(val)
        return JSON._Str(String(val))
    }

    static _Str(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        s := StrReplace(s, "`b", "\b")
        s := StrReplace(s, "`f", "\f")
        ; remaining control characters
        while RegExMatch(s, "[\x00-\x1F]", &m)
            s := StrReplace(s, m[0], Format("\u{:04x}", Ord(m[0])))
        return '"' s '"'
    }

    static _Ws(text, &pos) {
        while (pos <= StrLen(text) && InStr(" `t`r`n", SubStr(text, pos, 1)))
            pos++
    }

    static _Value(text, &pos) {
        JSON._Ws(text, &pos)
        ch := SubStr(text, pos, 1)
        if (ch = "{")
            return JSON._Object(text, &pos)
        if (ch = "[")
            return JSON._Array(text, &pos)
        if (ch = '"')
            return JSON._String(text, &pos)
        if (SubStr(text, pos, 4) == "true") {
            pos += 4
            return 1
        }
        if (SubStr(text, pos, 5) == "false") {
            pos += 5
            return 0
        }
        if (SubStr(text, pos, 4) == "null") {
            pos += 4
            return ""
        }
        if RegExMatch(text, "-?\d+(\.\d+)?([eE][+-]?\d+)?", &m, pos) && m.Pos = pos {
            pos += m.Len
            return (m[1] != "" || m[2] != "") ? Float(m[0]) : Integer(m[0])
        }
        throw Error("JSON: unexpected '" ch "' at position " pos)
    }

    static _Object(text, &pos) {
        obj := Map()
        pos++ ; {
        JSON._Ws(text, &pos)
        if (SubStr(text, pos, 1) = "}") {
            pos++
            return obj
        }
        loop {
            JSON._Ws(text, &pos)
            if (SubStr(text, pos, 1) != '"')
                throw Error("JSON: expected key at position " pos)
            key := JSON._String(text, &pos)
            JSON._Ws(text, &pos)
            if (SubStr(text, pos, 1) != ":")
                throw Error("JSON: expected ':' at position " pos)
            pos++
            obj[key] := JSON._Value(text, &pos)
            JSON._Ws(text, &pos)
            ch := SubStr(text, pos, 1)
            pos++
            if (ch = "}")
                return obj
            if (ch != ",")
                throw Error("JSON: expected ',' or '}' at position " (pos - 1))
        }
    }

    static _Array(text, &pos) {
        arr := []
        pos++ ; [
        JSON._Ws(text, &pos)
        if (SubStr(text, pos, 1) = "]") {
            pos++
            return arr
        }
        loop {
            arr.Push(JSON._Value(text, &pos))
            JSON._Ws(text, &pos)
            ch := SubStr(text, pos, 1)
            pos++
            if (ch = "]")
                return arr
            if (ch != ",")
                throw Error("JSON: expected ',' or ']' at position " (pos - 1))
        }
    }

    static _String(text, &pos) {
        pos++ ; opening quote
        out := ""
        loop {
            ; copy the run of plain characters in one go
            if RegExMatch(text, '[^"\\]+', &m, pos) && m.Pos = pos {
                out .= m[0]
                pos += m.Len
            }
            ch := SubStr(text, pos, 1)
            if (ch = "")
                throw Error("JSON: unterminated string")
            pos++
            if (ch = '"')
                return out
            ; backslash escape
            e := SubStr(text, pos, 1)
            pos++
            switch e, true {
                case '"': out .= '"'
                case "\": out .= "\"
                case "/": out .= "/"
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "b": out .= "`b"
                case "f": out .= "`f"
                case "u":
                    out .= Chr(Integer("0x" SubStr(text, pos, 4)))
                    pos += 4
                default: throw Error("JSON: bad escape \" e)
            }
        }
    }
}
