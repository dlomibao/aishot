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

One shot per launch, but the window can be kept open: `⌘V` re-reads the
clipboard and swaps in a newer screenshot. That is a full window rebuild rather
than a mutated image, because the next grab is rarely the same size and the
canvas geometry is fixed at construction. No resident process, no login item,
no polling — the app still quits when you finish or cancel.

`⌘V` is overloaded deliberately: inside a text field it pastes text, everywhere
else it loads the clipboard image. Replacing an image you have already marked up
asks first.

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

## Style is per-annotation

`Renderer.draw` walks `[StyledAnnotation]` and uses each item's own style rather
than taking one style for the whole call. A global style would have meant that
changing the colour restyled everything already drawn, which defeats the point
of a colour picker — you want a yellow box next to a red arrow.

`SizeClass` multiplies a base measured in **screen points**, not a fraction of
the image. Scaling by the image's short edge seemed reasonable and was wrong in
practice: a 1688x202 toolbar strip got a 2px stroke and 11px text while a
2528x1772 window grab got 16px and 60px — an 8x swing driven by nothing but
crop shape, and the strip is the common case when pointing at a single row.

A screenshot is always viewed at 1:1 against the display it came from, so the
markup should be a constant size on screen. The only image-dependent part left
is a ceiling, so markup cannot swamp a very small crop.

Redaction ignores the selected colour. It is a privacy operation, not markup,
and a "blue redaction" would be a misleading thing to offer.

Last colour and size persist in `UserDefaults`. The app quits after every
screenshot, so without persistence you would re-pick your preference each time.

## Cropping is an undoable operation, not a destructive edit

The undo stack holds `Operation` values — either an annotation or a crop — so
`⌘Z` walks back through both. Annotations stay in the **original** image's
coordinates and the renderer translates the context by the crop origin, rather
than rewriting every annotation when you crop. That is what makes undo cheap:
there is nothing to move back.

Crops are stored absolute, so the one in effect is simply the last one in the
stack and nested crops need no composition logic.

A crop is confirmed rather than applied on mouse-up. Everything outside the
selection dims, and ✓ / ✕ appear beside it. `C` confirms while a crop is
pending, which means colour cycling is suppressed until the crop resolves —
worth the overload, because confirming is the only thing you want at that
moment.

## Text wraps inside a box

`Annotation.text` carries a `CGRect`, not a point. The renderer uses
`CTFramesetter` to flow text from the box's top edge downward, so the height is
where you started typing rather than a clip — long text grows past the box
instead of disappearing. The editor asks the renderer for the height as you
type and grows the input field to match, so the field shows what will be drawn.

`⏎` commits the text, so a line break needs a modifier. macOS binds
`insertNewlineIgnoringFieldEditor:` to ⌥⏎ and `insertLineBreak:` to ⌃⏎ in
`StandardKeyBinding.dict`; ⇧⏎ has no system binding at all and is a chat-app
convention. All three are accepted, because which one someone reaches for
depends on what they used last, and being wrong costs them a committed
annotation.

Line breaking is set to word wrapping explicitly. CoreText still breaks a token
too long to fit on its own line, which a test pins, since a pasted URL would
otherwise run past the box edge.

## Decisions

**Redaction uses `.copy` blend mode.** A composited black rect would still be
recoverable through any alpha in the source. `.copy` replaces the pixels.

**Stroke and type scale with the image's short edge**, clamped to a floor, so a
4K screenshot and a 300px crop get visually comparable markup.

**The arrow shaft stops at the head's neck** rather than running to the tip, so
the head does not thicken or show a seam.

**Badge numbers derive from how many badges are currently placed**, so undo
frees a number instead of leaving a gap.

**The window floors at a measured width, not a constant.** It used to size
purely to the image, so a narrow crop produced a window with a clipped toolbar.
The floor now comes from the toolbar's own `fittingSize`, because a hardcoded
number goes stale the moment a button is added — the first guess of 660pt was
already 200pt short. Keyboard hints live in tooltips rather than button titles
for the same reason: the titles set the floor, and a small crop should not open
a needlessly wide window.

**The Save panel always opens in `~/Downloads`**, rather than remembering the
last folder used. A fixed destination is predictable — you know where the file
went without reading the panel — and `~/Pictures/aishots` still archives every
copy regardless.

**Closing asks before it throws markup away.** Esc, Cancel and the window's
close button all confirm when there is something drawn, and the dialog maps esc
to "Keep Editing" so pressing esc twice cannot discard the work the first press
asked about. The key monitor also ignores keys aimed at a sheet or alert: the
save panel is an in-process window in this unsandboxed app, so without that
check, esc in the Save dialog closed the whole editor.

**Save is not a terminal action.** Copy closes the editor; Save leaves it open,
so you can save a PNG and carry on annotating or save a second copy elsewhere.

**Activation policy is `.regular`, not `.accessory`.** An accessory app gets no
menu bar, and without a menu bar the standard `⌘Z` key equivalent does not fire.
The cost is a Dock icon for the few seconds the editor is open.

**PNG is also written to disk.** Costs almost nothing and is the fallback if a
given harness rejects pasteboard images and wants a path or a drag.

## Out of scope

Colour picker, stroke weight UI, blur, redo, preferences window, capture
history, and any capture path of its own.
