# Alcadeias

One dashboard for everything that speeds up your desktop: your AutoHotkey scripts, window layouts, apps, folders and links. Press **Ctrl+Alt+D** from anywhere to show or hide it.

- **Find anything, without keeping things tidy**: Alcadeias remembers every folder you visit and every file you open, ranked by how often and how recently you used them. Type a few letters and the right place is at the top. With *Everything* installed it also searches the whole PC, newest first.
- **Inbox**: Downloads and Desktop as a to-do list. **Ctrl+M** moves files to the right folder. It learns where each kind of file goes, suggests that next time, and **Ctrl+Z** undoes.
- **Projects**: one item per project (its folder, files and links to open, a layout). One key or search opens all of it.
- **Templates**: "New Video project…" copies your skeleton folder, fills in the name and date, and opens the result as a project.
- **Browse in the dashboard**: Tab into any folder, type to filter, Backspace to go up. Newest files first.
- **Scripts**: create, edit and run all your `.ahk` files from one place. Press **Ctrl+S** in the editor and the running copy is replaced right away. If you made a mistake, Alcadeias shows the error and the line, and **the old version keeps running**.
- **Layouts**: one hotkey puts a set of apps in exact positions across your monitors (for example Obsidian on the left half of monitor 1, Claude on the right half, YouTube Studio fullscreen on monitor 2). Apps that aren't open get launched first.
- **Apps**: focus-or-launch hotkeys. Press `Alt+O` and Obsidian comes to the front, or opens if it's closed.
- **Folders**: jump to a folder. If a Save/Open dialog or an Explorer window is in front, that window goes there instead of a new one opening (same trick as the numpad warps in your Razer script).
- **Links**: URLs, files or commands.
- **Search**: one search box over all of it, including the hotkeys defined *inside* your scripts. Search `F8` and you'll find the script that uses it.

---

## Setup (5 minutes)

1. **Install AutoHotkey v2** from <https://www.autohotkey.com>. Alcadeias itself runs on v2.
   Your existing scripts are v1 and **don't need converting**. Alcadeias runs each script with the right version. If v1 isn't installed yet, the AutoHotkey v2 installer offers to add it, or you can grab v1.1 from the same site.
2. **Get Alcadeias**: on GitHub press **Code → Download ZIP** and unzip it somewhere permanent, e.g. `Documents\Alcadeias`. You can also `git clone` it.
3. Double-click **`Start Alcadeias.cmd`**. The dashboard opens and an icon appears in the tray.
   (Use this rather than double-clicking `Alcadeias.ahk`. If `.ahk` files open with v1 on your PC, which is normal when you have v1 scripts, v1 can't run Alcadeias. The `.cmd` always uses v2, and your v1 scripts keep opening the way they do now.)
4. Open **Settings** and turn on **Start Alcadeias with Windows**.

## First things to do

**Bring in your scripts**
1. Click **Scripts** on the left, then **+ New → Add existing .ahk files…** and pick your scripts (you can select several at once).
2. For each one you always want running, select it, press **Edit** and turn on **Start this script when Alcadeias starts**.
3. If those scripts are also in your Windows Startup folder (`Win+R` → `shell:startup`), remove them from there so Alcadeias is the one place that starts them.

**Make your first layout**

The easy way is to capture what's already on screen:
1. Arrange your windows by hand exactly how you want them.
2. In Alcadeias: **+ New → Layout…**, give it a name, press **Record** and hit the hotkey you want (e.g. `Ctrl+Alt+1`).
3. Press **Capture screen**, untick any windows you don't want, then **Use these**.
   Capture also records how to **reopen** each window, so later the layout works even when everything is closed. Apps get their program path. For Chrome, Alcadeias briefly flips to each window and reads its web address, so it can reopen that exact page (your clipboard is restored afterwards).
4. Press **Test it now**, then **Save**.

You can fine-tune each window afterwards (double-click it in the list):

| Field | What it means |
|---|---|
| Program (exe) | Which app, e.g. `obsidian.exe`. **Pick…** grabs it from an open window. |
| Title contains | Tells windows of the same app apart. Two Chrome windows? Use `Claude` for one and `YouTube Studio` for the other. |
| Launch if closed | What to run when it isn't open. Leave it empty to skip that window. |
| Monitor | 1, 2, … Use **Identify monitors** to see which is which. |
| Size | *Fit to zone*, *Maximized*, or *Fullscreen (F11)*. |
| Position | Left half, right third, top-right quarter, … or *Custom* (x/y/width/height in % of the screen, so it survives resolution changes). |

**Tip: Claude as its own window.** Set *Launch if closed* to
`chrome.exe --app=https://claude.ai` and *Title contains* to `Claude`.
You get a separate Claude window without tabs or an address bar, and the layout can always find it.

**Tip: a specific Chrome page on monitor 2.** Use *Launch if closed*
`chrome.exe --new-window https://studio.youtube.com`, *Title contains* `YouTube Studio`, *Size* `Fullscreen (F11)`.

---

## Your files, the low-effort way

Nothing needs setting up to start, because Alcadeias learns as you go.

1. **Just use your PC.** Folders you open in Explorer and files you open in any app are remembered automatically (Windows already logs them).
2. **Ctrl+Alt+D, type, Enter.** *Home* searches everything; *Files* shows your most-used places and, with Everything, every file on the PC (newest first). If a browser's upload dialog or any Save/Open dialog was in front, Enter puts the file or folder straight into it.
3. **Tab** looks inside a folder or project; **Backspace** goes up; **Esc** goes back.
4. **Inbox** shows loose files in Downloads and on the Desktop. Select one or several (Shift+Up/Down), press **Ctrl+M** and type where it goes. Next time that kind of file gets a suggestion. **Ctrl+Z** undoes a move or rename.

**Whole-PC search (recommended):** install the free [Everything](https://www.voidtools.com/downloads/) app, then Settings → *Set up for me*. That downloads Everything's official search connector into `tools\`.

**Templates:** + New → Template… → *Make a starter one* creates `data\templates\Video project` (footage/audio/graphics/project/exports/thumbnails + a notes file). Drop your `.prproj` / `.aep` templates into it, and name files with `{name}` / `{date}` to have them filled in. Set *New projects go in* to where your projects live. After that, + New → New Video project… asks for a name and does the rest.

## Keys

| Where | Key | Does |
|---|---|---|
| Anywhere | **Ctrl+Alt+D** | Show / hide Alcadeias (change it in Settings) |
| Dashboard | just type | Search everything |
| | ↑ ↓ PgUp PgDn | Pick a row |
| | **Enter** / double-click | Run it (layout applies, app focuses, folder opens; a script opens in the editor) |
| | F2 or Ctrl+E | Edit the selected item |
| | Ctrl+N | New item |
| | Delete | Remove the selected item |
| | Ctrl+1 … Ctrl+7 | Switch category |
| | Tab / Backspace | Look inside a folder / go up |
| | Ctrl+M | Move selected file(s) to… |
| | Ctrl+Z | Undo the last move or rename |
| | Ctrl+R / Ctrl+Shift+C | Show in Explorer / copy path |
| | Shift+Up/Down | Select several |
| | Esc | Clear the search, leave a folder, then hide |
| | Right-click a row | More: duplicate, show file, backups, … |
| Dialogs | Enter / Esc | Save / cancel |
| Script editor | **Ctrl+S** | Save, check for errors, swap in the new version |
| | Ctrl+Shift+S | Save without applying |
| | Ctrl+F, F3 | Find, find next |
| | Ctrl+G | Go to line |

A **script's own hotkey** (set via Edit) turns that script on and off, like your `F8::Suspend`, but for any script.

---

## Good to know

- **Your scripts are separate programs.** Closing Alcadeias, or Alcadeias crashing, doesn't stop them.
- **Prefer VS Code or another editor?** Set it in Settings → *External editor*. When you save a file there, Alcadeias picks it up and applies it automatically (*Auto-apply*, on by default per script). The same error check applies.
- **Backups:** every save from the editor keeps the previous version in `data\backups\<script name>\` (the last 30). Right-click a script → *Open backups folder*.
- **Your setup lives in `data\config.json`.** It's plain text, so you can back it up or copy it to another PC. New scripts go in `scripts\` by default (changeable in Settings). Both folders are git-ignored, so updating Alcadeias never touches them.
- **Encodings are preserved.** The editor writes files back the way they were (UTF-8 with or without BOM, ANSI, CRLF or LF), so v1 scripts with special characters stay intact.
- **Virtual desktops (optional):** point Settings → *VirtualDesktop dll* at the same `VirtualDesktopAccessor.dll` your Win_Hotkeys script uses. Layouts can then switch to a desktop first, and pull a needed window over from another desktop.
- **Admin windows:** Windows doesn't let normal programs move windows that run as administrator. If a layout can't move one, that's why.
- **Hotkey conflicts:** when you record a hotkey, Alcadeias warns if it's already used by another item or inside one of your scripts. The header shows problems such as an invalid hotkey; click it for details.

## Files

```
Alcadeias.ahk        start here
lib\                 the app (Dashboard, Editor, Layouts, Scripts, ...)
assets\              icon
data\                your setup + backups (created on first run, not in git)
scripts\             default home for new scripts (not in git)
```

## Coming next

Snippets, clipboard history, Razer key map, a daily start routine, window tools (throw to other monitor, snap, always on top), a hotkey map page, backup/sync, usage stats and auto-sort rules for the inbox.
