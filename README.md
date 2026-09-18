# aishot

Mark up the screenshot on your clipboard and paste it into an AI coding session.

macOS already takes the screenshot. This is the missing second half: arrows,
boxes, text, numbered steps, and redaction on top of whatever image is on the
clipboard — then the annotated PNG replaces it.

## Use

1. `⌃⇧⌘4` — drag a region. macOS copies it to the clipboard.
2. Your hotkey — the editor opens on that image.
3. Mark it up. `⏎` copies the result back. `Esc` cancels and leaves the clipboard alone.
4. Paste into your session.

| Key | |
|---|---|
| `1`–`5` | arrow, box, text, number badge, redact |
| `⌘Z` | undo last annotation |
| `⏎` | copy annotated image, quit |
| `Esc` | cancel |

Arrows, boxes and redactions are drag; text and badges are click. Badges number
themselves in placement order, and undoing one frees its number again.

Redaction writes solid black into the output pixels rather than laying an
overlay on top, so the original content is genuinely gone from what you paste.

Every result is also written to `~/Pictures/aishots/` as a fallback for targets
that take a file but not a pasteboard image.

## Install

```sh
./scripts/install.sh
```

Builds, bundles `AIShot.app` into `~/Applications`, and drops a Raycast script
command in `~/.raycast-scripts`. Add that folder under Raycast → Extensions →
Script Directory, then bind a hotkey to "Annotate Clipboard Screenshot".

Shortcuts.app or skhd work equally well — anything that can run
`open -a ~/Applications/AIShot.app`.

## Develop

```sh
swift build          # app
./scripts/test.sh    # core tests (needs Xcode's toolchain for XCTest)
```

`AIShotCore` holds the annotation model, the coordinate transform and the
renderer, with no window code — that is where the tests live. `aishot` is the
AppKit shell around it.

Annotations are stored in **image pixel coordinates**, never view points, and
one `Renderer.draw` call renders both the on-screen canvas and the exported
PNG. That is what keeps the editor WYSIWYG on a Retina display and the output
at full source resolution.
