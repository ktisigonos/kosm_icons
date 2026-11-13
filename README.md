# kosm_icons

Icons for kosm: an icon theme in the kosmos' colors, or a theme installed on the system, picked
by name. GTK, KDE and other desktops pick it by `App.themeName`; `kosm_base` passes that on.

- **BeautyLine** (the default, Garuda Linux's outline icons, GPL-3.0, fetched as a pinned
  dependency): written whole to `~/.local/share/icons/kosm`, every SVG recolored. Its most
  used gradients become exact theme colors (fields named after the hues they go between,
  `blue_cyan`, `orange_yellow`, ...); every other color follows `rest`, or `all` recolors
  everything one way.
- **A system theme** (`.system = .{ .name = "Papirus-Dark" }`): used as is, nothing written.
  With `recolor` set it is copied into `directory` recolored, and picked from there.

Icons named or filed `symbolic` are never recolored: GTK and KDE color them. Links stay links;
a relative link pointing outside the theme becomes an absolute one. A diff shows the theme as
one line. After an apply, `gtk-update-icon-cache` refreshes GTK's cache of the folder; a
failure is a warning. Running programs may keep the old icons until restarted.

Colors are found as `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, and `white` or `black`
as a color property's value; other named colors stay as they are. Alpha never changes.

## Recolor

| Mode | What each color becomes |
|---|---|
| `.palette` (`Nearest.from(theme)`) | the palette color of its wheel position (nearest by hue to the pure sRGB wheel: `#ff0000` red, `#ff8000` orange, ...), with its own lightness; grays (chroma below `gray_chroma`, 0.04) fall between the palette's black and white |
| `.tint = color` | `color`'s hue, with its own lightness and chroma; grays stay gray |
| `.flat = color` | `color` |

## Fields

| Field | Default |
|---|---|
| `icons` | `from`: `.beautyline`; null writes nothing and picks no theme |
| `directory` | `~/.local/share/icons/kosm`; its last folder is the theme's name. Files an earlier apply wrote there and this one doesn't are left |
| `name` | the theme's `name`, or the name kosm applies the kosmos under: `Name` in index.theme |

`System`: `name`, `recolor` (null: used as is), `path` (null: `/usr/share/icons/<name>`).

`BeautyLine`: one `Gradient` (`start`, `end`) per gradient, each listing BeautyLine's colors it
replaces, then `rest` (`.palette` from the theme) and `all` (null).

## Optional dependencies

- `gtk-update-icon-cache` (Arch package `gtk-update-icon-cache`), for the cache refresh.
