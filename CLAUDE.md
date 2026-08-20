# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

JsonLayer — a Flutter **Windows desktop** JSON workspace editor. The user picks a disk directory as a workspace; the app manages a tree of `.json` / `.log` documents inside it, opened as tabs with two interchangeable editor modes (JSON source / object tree).

Windows is the only supported target. Web is impossible as-is (`dart:io` dependency); macOS/Linux are unverified (one hardcoded `Process.run('explorer', ...)` and one manual path-separator heuristic remain).

## Commands

```bash
flutter pub get
flutter run -d windows                       # dev run (windows is the only working device)
flutter analyze                              # must be warning-free before a PR
flutter test                                 # all tests
flutter test test/stores/tab_store_test.dart # single file
flutter test --plain-name "文件夹重命名时更新子标签路径"  # single test by name
dart format lib test
flutter build windows --release              # → build/windows/x64/runner/Release/
```

Installer: compile `installer/json_layer.iss` with Inno Setup (not part of the Flutter build).

Note the app runs as a single window with `titleBarStyle: hidden` — a stale `json_layer.exe` from a previous run can block a rebuild; `taskkill //F //IM json_layer.exe` clears it.

## Layer structure and dependency direction

```
pages/ ──> components/ ──> model/            (UI; no dart:io, no direct file access)
       ──> stores/      ──> services/, model/ (ChangeNotifier state + persistence)
                         ──> services/        (WorkspaceService interface → FileWorkspaceService impl)
       ──> utils/, contants/                  (infrastructure; no business deps)
```

- `services/WorkspaceService.dart` is the **only** sanctioned filesystem boundary. UI code must not call `dart:io` directly for workspace files — go through `WorkspaceStore` → `WorkspaceService`. (Exceptions in tree today: `ThemeStore` writes background images to the app-support dir, and `WorkspaceTree` shells out to Explorer.)
- State is `provider` + `ChangeNotifier`, all four stores injected once in `main.dart` via `MultiProvider`. `ThemeStore` is constructed and `loadFromPrefs()`-awaited **before** `runApp` so `MaterialApp` has a theme on frame one.
- Child components take plain value props + closure callbacks (`content`, `onChanged`, `onSave`, `onNavigate`), never store references. Keep it that way — editors are meant to be store-agnostic.

## Store responsibilities

| Store | Owns |
| :-- | :-- |
| `WorkspaceStore` | file tree (`DocumentItem` root), CRUD delegation, expand/collapse, the `locatePath`/`locateTick` signal |
| `TabStore` | open `DocumentTab` list, active tab, dirty flags, path rewriting after rename |
| `EditorStore` | current document's mode/content (largely superseded by per-tab state on `DocumentTab`) |
| `ThemeStore` | `SkinMode` (light / builtInBg / customBg), theme data, background-image persistence |

`DocumentItem` and `DocumentTab` are immutable with `copyWith`; the tree is rebuilt structurally (`_toggleExpandInTree`) rather than mutated. Preserve this — `WorkspaceStore` relies on identity-free rebuilds.

## Non-obvious invariants (breaking these causes real bugs)

- **`_SkinBackgroundWrapper` root must always be a `Stack`** (`lib/main.dart:177`). Swapping the root node type between `Container`/`Stack` per skin mode unmounts the whole `MaterialApp` subtree and trips `_dependents.isEmpty` / "wrong build scope" assertions.
- **Editor mode switching uses `IndexedStack`, not `TabBarView`** (`RequestResponsePanel`). Both editors stay alive so switching JSON ↔ object never re-decodes the JSON or loses scroll/selection. It listens to the `TabController` itself, not `controller.animation!` (null on first frame).
- **`Ctrl+S` is global**, registered via `CallbackShortcuts` around the whole `Scaffold.body` in `HomePage` so it fires regardless of focus. `Ctrl+F` / `Ctrl+Z` / `Ctrl+L` are editor-local (`Focus.onKeyEvent`); `Ctrl+Z` intentionally prefers the search bar's own `UndoHistoryController` when the search bar has focus.
- **Rename must re-append the original extension.** `WorkspaceTree._showRenameDialog` hides `.json`/`.log` as a non-editable `suffixText`; `_confirmRename` strips any suffix the user typed back in and restores the original. After renaming, `TabStore.updateTabPath(old, new, title)` must be called — it also rewrites descendants via `p.isWithin`, otherwise open tabs point at dead paths.
- **Locate is a tick, not a value.** `WorkspaceStore.requestLocate(path)` bumps `locateTick`; `WorkspaceTree` reacts, expands ancestors, highlights for ~3s (highlight state is local to the widget), then calls `clearLocate()`. Repeated locates to the same path only work because the tick changes.
- **Toasts go through `SafeSnackBar.show`**, never `ScaffoldMessenger` directly. It de-duplicates within a 1.5s window keyed by message text or an explicit `idempotencyKey` — pass a semantic key when the message interpolates variables.
- **Editor toolbar buttons are `EditorActionButton`**, and **content-area right-click menus are `EditorContextMenu`** (both in `components/common/`). Don't hand-roll an `InkWell` + `Icon` toolbar button, and don't fall back to Flutter's default `AdaptiveTextSelectionToolbar` — it renders an untranslated system toolbar that clashes with the `showMenu`-based menus elsewhere. Cut/copy/paste/select-all availability must keep coming from `contextMenuButtonItems`; a null `onTap` renders the entry grayed out.
- Use `package:path` (`p.join`, `p.basename`, `p.isWithin`) for all path work. Tests assert platform-correct separators (`test/services/file_workspace_service_test.dart`).

## Editors

- `JsonEditor` — `flutter_code_editor` `CodeController` subclass with a custom `buildTextSpan` for search highlighting, plus a hand-rolled line-number gutter. Owns format/compress (via `JsonUtil`) and the "copy with preset prompt" action (`CommonConstants.presetPromptKey` in `SharedPreferences`, edited from the HomePage settings dialog).
- `ObjectTreeEditor` — fully custom rendering (no editor package), collapsible `{}` tree inside a `SelectionArea`, manual content-width measurement.

The two duplicate their search/undo logic. When touching search behavior, check both — a fix in one is almost always needed in the other.

## Conventions

- **File names are PascalCase** (`WorkspaceStore.dart`, `JsonEditor.dart`). The `file_names` lint is deliberately disabled in `analysis_options.yaml`; don't re-enable it or rename files to snake_case. Test files are the exception and use snake_case.
- `lib/contants/` is a legacy misspelling of "constants" — kept for consistency, don't rename.
- Suffix conventions: `XxxPage` / `XxxStore` / `XxxService` / `XxxUtil`. Constants live in `CommonConstants` — no magic colors, sizes, or prefs keys inline. That includes animation durations, hover alphas, and the per-action semantic colors (`action*ColorValue`).
- Comments, UI strings, and error messages are Chinese. Match that.
- `ARCHITECTURE.md` is a **generic team-wide Flutter packaging convention doc**, not a description of this repo — it documents `api/`, `domain/req/`, `domain/vo/`, GetX, and Dio, none of which exist here. Take its naming/immutability rules as binding; ignore its directory listing.
