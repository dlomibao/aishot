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
| `C` | cycle colour |
| `[` `]` | smaller / larger stroke and text |
| `⌘V` | load the screenshot now on the clipboard |
| `⌘Z` | undo last annotation |
| `⌘S` | save a PNG somewhere and keep editing |
| `⏎` | copy annotated image, quit |
| `Esc` | cancel |

Arrows, boxes and redactions are drag; text and badges are click. Badges number
themselves in placement order, and undoing one frees its number again.

Leave the window open and keep shooting: `⌃⇧⌘4` again, then `⌘V` (or the
**Reload** button) swaps in the new screenshot without relaunching. If you have
already drawn something it asks before discarding it. Inside a text field `⌘V`
pastes text as usual.

Colour and size apply to what you draw **next** — each shape keeps the style it
was drawn with, so you can put a yellow box beside a red arrow. Six swatches,
picked to stay legible on light and dark screenshots, and one S/M/L control that
scales stroke and text together. Size is relative to the image, so "large" on a
4K grab and on a small crop both look large. Your last colour and size are
remembered between launches.

Redaction is always solid black regardless of the selected colour, and writes
into the output pixels rather than laying an
overlay on top, so the original content is genuinely gone from what you paste.

`⌘S` opens a save panel and writes a PNG wherever you point it, then leaves the
window open so you can keep annotating or save a second copy elsewhere. It
always opens in `~/Downloads`.

Every result you copy is also written to `~/Pictures/aishots/` automatically —
a fallback for targets that take a file but not a pasteboard image, and a
record of shots you only pasted.

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
