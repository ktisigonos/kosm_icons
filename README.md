# kosm_icons

Icons for kosm: an icon theme in the kosmos' colors, or a theme installed on the system, picked
by name. GTK, KDE and other desktops pick it by `App.themeName`; `kosm_base` passes that on.

- **BeautyLine** (the default, Garuda Linux's outline icons, GPL-3.0, fetched as a pinned
  dependency): written whole to `~/.local/share/icons/kosm`, every SVG recolored. Its most
  used gradients become exact theme colors (fields named after the hues they go between,
  `blue_cyan`, `orange_yellow`, ...); every other color follows `rest`, or `all` recolors
  everything one way, by default the theme's accent and secondary.
- **A system theme** (`.system = .{ .name = "Papirus-Dark" }`): used as is, nothing written.
  With `recolor` set it is copied into `directory` recolored, and picked from there.

Symbolic icons are recolored too: BeautyLine draws most of them in its own colors, and GTK or
KDE, where they color one, override the file's colors anyway. Links stay links;
a relative link pointing outside the theme becomes an absolute one. A diff shows the theme as
one line. After an apply, `gtk-update-icon-cache` refreshes GTK's cache of the folder; a
failure is a warning. Running programs may keep the old icons until restarted.

Colors are found as `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, and `white` or `black`
as a color property's value; other named colors stay as they are. Alpha never changes.

## Recolor

`Recolor.from(theme)` is the theme's accent and secondary: each color becomes the one it looks
nearest, grays a ramp. Each color matches one of `colors` and becomes what `mode` makes of it;
alpha never changes.

```zig
icons.icons.?.beautyline.all = .{ .theme = theme, .colors = .{ .roles = &.{ .accent, .link } }, .mode = .hue };
icons.icons.?.beautyline.all = .{ .theme = theme, .colors = .{ .except = &.{ .yellow } } };
```

| Field | Default |
|---|---|
| `theme` | the theme whose hues and roles `colors` names, and whose black and white grays fall between |
| `colors` | `.all`, the palette's twelve hues (`from`: the accent and secondary); `.{ .except = &.{ .yellow } }` all but those; `.{ .roles = &.{ .accent } }` these roles; `.{ .only = &.{ ... } }` these colors, the first listed winning a tie |
| `mode` | `.nearest` (`.hue_and_chroma` when built without `from`) |
| `grays` | `.ramp` |
| `gray_chroma` | 0.04: below this OKLCH chroma a color is gray |

| `mode` | Matches by | The color becomes |
|---|---|---|
| `.hue_and_chroma` | hue | the match's hue and chroma, its own lightness: shading stays |
| `.hue` | hue | the match's hue, its own lightness and chroma |
| `.nearest` | how near it looks (OKLab) | the match exactly |
| `.{ .blend = amount }` | hue | partway to the match, 0..1 |
| `.{ .custom = function }` | hue | `function(color, match)` |

Matching by hue goes to the color whose wheel position (the pure sRGB hue nearest it:
`#ff0000` red, `#ff8000` orange, ...) is nearest: icons are drawn in sRGB colors picked by
name, whatever the palette's own hues. A listed color counts as the position nearest its hue.

`grays`: `.ramp` between the palette's black and white by lightness, `.keep` as they are,
`.match` like any color. One color with `.hue` and `.keep` tints the icons; with `.nearest`
and `.match` it makes them flat. No colors to pick, or a blend outside 0..1, is an error.

## Fields

| Field | Default |
|---|---|
| `icons` | `from`: `.beautyline`; null writes nothing and picks no theme |
| `directory` | `~/.local/share/icons/kosm`; its last folder is the theme's name. Files an earlier apply wrote there and this one doesn't are left |
| `name` | the theme's `name`, or the name kosm applies the kosmos under: `Name` in index.theme |

`System`: `name`, `recolor` (null: used as is), `path` (null: `/usr/share/icons/<name>`).

`BeautyLine`: one `Gradient` (`start`, `end`) per gradient, each listing BeautyLine's colors it
replaces and defaulting to the palette's colors of the hues it names, then `rest`
(`Recolor.from(theme)`) and `all` (`Recolor.from(theme)`; null uses the gradients and `rest`).

## Optional dependencies

- `gtk-update-icon-cache` (Arch package `gtk-update-icon-cache`), for the cache refresh.
