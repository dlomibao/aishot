# aishot — design

## Problem

Giving an AI coding agent visual feedback means screenshot → point at the thing
→ paste. macOS covers the screenshot; the pointing-at-it step has no fast path.
Existing tools are either licensed (Snagit), heavyweight (editor windows, save
dialogs), or want to own the capture themselves.

## Constraint that shaped everything

The app must not capture. Screen capture needs a TCC grant that is awkward on a
managed machine, and a binary run from a terminal inherits the terminal's grant,
so dev and installed behaviour diverge. Handing capture to the OS removes the
permission surface entirely: `⌃⇧⌘4` puts a region on the clipboard, and the app
starts from there.

## Shape

```
⌃⇧⌘4 ──► clipboard ──► [hotkey] ──► aishot ──► clipboard (annotated)
                                       └─────► ~/Pictures/aishots/*.png
```

One shot per launch. The app opens, edits, writes, and quits — no resident
process, no login item, no polling.

## Coordinate space

The single decision the rest of the code hangs off: **annotations are stored in
image pixel coordinates with a bottom-left origin**, and `Renderer.draw` is the
only thing that knows how to draw them.

- The canvas view is not flipped, so view↔image is a pure uniform scale with no
  axis flip.
- The view renders by scaling the context by `1/scale` and calling the same
  `Renderer.draw` the exporter calls. The preview cannot drift from the output
  because it is the output, at a different scale.
- Export allocates a bitmap at the source's exact pixel dimensions, so a Retina
  screenshot survives the round trip at full resolution.

Storing points in view space instead is what produces the classic failure here:
arrows land offset from where you drew them, and the pasted image is half
resolution.

## Modules

| | |
|---|---|
| `AIShotCore/Annotation` | the five annotation cases, `Tool`, and `AnnotationDocument` (add/undo/badge numbering) |
| `AIShotCore/CanvasTransform` | view↔image mapping, aspect-fit window sizing |
| `AIShotCore/Style` | stroke width and type size derived from image dimensions |
| `AIShotCore/Renderer` | draws annotations into any `CGContext`; encodes PNG |
| `aishot/Pasteboard` | reads PNG/TIFF/file-URL off the pasteboard, writes PNG back |
| `aishot/CanvasView` | mouse input, in-progress shape preview, inline text field |
| `aishot/EditorWindowController` | toolbar, keyboard commands, finish/cancel |

Core has no window code, which is why it is testable: every renderer test draws
onto a known canvas and asserts pixel colours.

## Decisions

**Redaction uses `.copy` blend mode.** A composited black rect would still be
recoverable through any alpha in the source. `.copy` replaces the pixels.

**Stroke and type scale with the image's short edge**, clamped to a floor, so a
4K screenshot and a 300px crop get visually comparable markup.

**The arrow shaft stops at the head's neck** rather than running to the tip, so
the head does not thicken or show a seam.

**Badge numbers derive from how many badges are currently placed**, so undo
frees a number instead of leaving a gap.

**Activation policy is `.regular`, not `.accessory`.** An accessory app gets no
menu bar, and without a menu bar the standard `⌘Z` key equivalent does not fire.
The cost is a Dock icon for the few seconds the editor is open.

**PNG is also written to disk.** Costs almost nothing and is the fallback if a
given harness rejects pasteboard images and wants a path or a drag.

## Out of scope

Colour picker, stroke weight UI, blur, redo, preferences window, capture
history, and any capture path of its own.
