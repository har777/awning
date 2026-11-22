# QuickNotes

A drop-down scratchpad for macOS, in the style of the Quake console. Press **⌥ Space** anywhere and a plain-text notepad slides down from under the menu bar. Type, hit **esc**, and you're back where you were. Your notes are one plain file, `~/.quicknotes/notes.txt`.

It's native Swift + AppKit with no dependencies. The app is about 400 KB and needs no permissions.

## Install

```bash
./build.sh install     # builds, copies to /Applications, launches
```

Other targets: `./build.sh` (build only, to `build/QuickNotes.app`), `./build.sh run`, `./build.sh test`. `make` wraps the same commands. Set `UNIVERSAL=1` for an arm64 + x86_64 build.

Requires macOS 13+ and Xcode (or the Swift toolchain).

## Shortcuts

| Keys | Action |
| :--- | :--- |
| `⌥ Space` | Show / hide the visor (configurable from the menu bar icon) |
| `esc` · `⌘W` | Hide |
| `⌘⏎` | Save and hide |
| `⌘D` | Insert a `--- [2026-11-22 09:30] ---` separator |
| `⌘L` | Toggle a checkbox on the current line(s): `x` → `- [ ] x` → `- [x] x` |
| `⏎` on a list line | Continue the list (`-`, `*`, `1.`, `- [ ]`, `>`); on an empty item, end it |
| `Tab` / `⇧Tab` | Indent / outdent (two spaces); works on multi-line selections |
| `⌘F` · `⌘G` · `⇧⌘G` · `⌘E` | Find bar, next, previous, use selection |
| `⌘+` · `⌘-` · `⌘0` | Bigger / smaller / default text |
| `⌘S` | Save now (it autosaves anyway) |
| `⌘O` | Open the file in your default editor |
| `⌘Q` | Quit |

Right-click the menu bar icon (or ⌥/⌃-click it) for the menu: choose the notes file, change the hotkey, keep the visor open when focus leaves, launch at login. Drag the visor's bottom edge to change its height; the height is remembered.

## Where things live

```
~/.quicknotes/
  notes.txt        your notes
  conflicts/       other programs' versions that lost a conflict (only created when needed)
```

Preferences (hotkey, visor height, text size) are kept in macOS preferences, not in this folder. You can switch to a different notes file from the menu bar icon; conflict backups still go to `~/.quicknotes/conflicts/`.

## How it treats your file

- **Plain text, always.** Headings (`# …`), separators, list markers, done tasks, `` `code` `` and links are styled in the editor, but nothing extra is ever written to the file.
- **Autosave.** Saves 0.4 s after you stop typing, and at least every 3 s while you keep typing. It also saves on hide, quit, sleep and shutdown.
- **Appends stay appends.** If you only added text at the end, only those bytes are appended, so `tail -f ~/.quicknotes/notes.txt` keeps working. Other edits are written atomically (temp file + rename), so a crash can't leave the file half-written.
- **Symlinks are followed.** Point `~/.quicknotes/notes.txt` (or the whole `~/.quicknotes` folder) at Dropbox, iCloud or a git repo and it stays a link.
- **Live external changes.** The file is watched while the app runs. `echo "idea" >> ~/.quicknotes/notes.txt` shows up immediately, even with the visor open and unsaved typing in progress. If another program rewrites the file while you have unsaved edits, your version is kept and theirs is saved in `~/.quicknotes/conflicts/`. The status line tells you, and clicking it reveals the backup.
- **Never corrupts.** A file that isn't valid UTF-8, or can't be read, opens read-only instead of being overwritten.

## Layout

```
Sources/QuickNotesCore/   pure logic, unit tested
  NoteFile.swift          read / append / atomic write, conflict backups
  SyncResolver.swift      what to do when disk and editor disagree
  TextOps.swift           list continuation, checkboxes, indent, timestamps, stats
Sources/QuickNotes/       the app
  AppDelegate.swift       menu bar item, menu, hotkey selection, launch at login
  VisorController.swift   glue + all visor shortcuts
  VisorPanel.swift        non-activating drop-down panel + animation
  NoteSession.swift       dirty tracking, debounced save, disk sync
  FileWatcher.swift       kqueue watcher that survives atomic saves / missing files
  EditorView.swift        header, editor, footer
  NoteTextView.swift      editing behaviour
  Highlighter.swift       incremental styling
  HotKey.swift            Carbon global hotkey (no permissions needed)
Tests/QuickNotesCoreTests/
```
