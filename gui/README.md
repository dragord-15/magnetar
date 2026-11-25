# GUI drawing library

The `gui` directory contains a framebuffer UI library for Magnetar. `gui_main.mg`
loads the framebuffer layer, drawing primitives, window manager, widgets, and
input handler in dependency order.

## Rich drawing helpers

`gfx_primitives.mg` provides these helpers in addition to lines, circles,
rectangles, and bitmap text:

| Function | Purpose |
| --- | --- |
| `draw_gradient_rect(x, y, w, h, r0, g0, b0, r1, g1, b1)` | Vertical RGB gradient; colors are packed for the active framebuffer format. |
| `draw_gradient_rounded_rect(x, y, w, h, radius, r0, g0, b0, r1, g1, b1)` | Gradient that follows rounded corners without square edge leaks. |
| `draw_rounded_rect(x, y, w, h, radius, color)` | Clipped filled rounded rectangle; dimensions and radius are validated. |
| `draw_rounded_outline(x, y, w, h, radius, border, surface)` | Rounded border with a solid inner surface. |
| `draw_soft_shadow(x, y, w, h, depth, color)` | Layered offset shadow. Use a dark, muted color for a soft-looking result. |
| `draw_progress_bar(x, y, w, h, value, track, fill)` | Rounded progress indicator; `value` is clamped to 0–100. |
| `draw_badge(x, y, w, h, text, background, foreground)` | Rounded status badge with centered bitmap text. |
| `draw_checkbox(x, y, size, checked, surface, accent, border)` | Draws a checkbox in checked or unchecked state. |
| `draw_toggle(x, y, w, h, enabled, off, on, knob)` | Draws an on/off switch. |
| `draw_slider(x, y, w, h, value, track, fill, knob)` | Draws a slider with `value` clamped to 0–100. |
| `draw_char_scale(x, y, ch, scale, color)` | Draws one character at bitmap scale 1–4. |
| `draw_string_scale(x, y, text, scale, color)` | Draws text at bitmap scale 1–4. |
| `draw_text_width(text, scale)` | Measures text in pixels at scale 1–4. |
| `draw_string_centered(cx, y, text, scale, color)` | Draws text centered around `cx`. |
| `draw_string_right(right, y, text, scale, color)` | Right-aligns text at `right`. |
| `draw_string_clipped(x, y, text, max_width, color)` | Draws only whole 8-pixel characters that fit. |
| `draw_string_window(x, y, text, start, max_width, color)` | Draws a clipped, horizontally scrolled window of text. |

Example, after `fb_init()` and `gfx_font_init()`:

```magnetar
int panel = rgb_pack(25, 30, 48);
int track = rgb_pack(48, 56, 78);
int accent = rgb_pack(95, 140, 245);
draw_soft_shadow(32, 32, 260, 120, 3, rgb_pack(12, 14, 25));
draw_rounded_rect(32, 32, 260, 120, 14, panel);
draw_progress_bar(52, 96, 220, 10, 72, track, accent);
draw_badge(208, 46, 64, 20, "READY", rgb_pack(35, 90, 75), rgb_pack(220, 255, 240));
```

The stock widgets use rounded surfaces and state-aware button gradients. They
remain interactive through the existing `widgets.mg` event handling APIs.
`wdg_create_heading(parent, x, y, text, color, scale)` creates a larger label
(scale 2–4). Text fields now clip their displayed text and cursor to their
available width so long input cannot spill into neighboring controls.
