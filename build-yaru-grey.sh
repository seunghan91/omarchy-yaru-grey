#!/usr/bin/env bash
# Build monochrome Yaru icon themes for Omarchy's White and Vantablack themes.
#
#   Yaru-grey  (light, for White)       derived from Yaru-blue
#   Yaru-gray  (dark,  for Vantablack)  derived from Yaru-blue-dark
#
# Only the accent-coloured variant folders are rebuilt; everything else is
# inherited from the stock Yaru theme, exactly as the coloured variants do.
#
# Usage: build-yaru-grey.sh [SOURCE_ICONS_DIR] [DEST_ICONS_DIR]
#   SOURCE_ICONS_DIR  default /usr/share/icons   (yaru-icon-theme)
#   DEST_ICONS_DIR    default ~/.local/share/icons
# Needs: imagemagick (magick), python3.
set -euo pipefail

src=${1:-/usr/share/icons}
dest=${2:-$HOME/.local/share/icons}

command -v magick >/dev/null || { echo "imagemagick (magick) is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

build() {
  local from=$1 to=$2 brightness=$3
  [[ -d $src/$from ]] || { echo "missing $src/$from (is yaru-icon-theme installed?)" >&2; exit 1; }

  rm -rf "${dest:?}/$to"
  mkdir -p "$dest"
  cp -r "$src/$from" "$dest/$to"
  # Name it, and inherit from the grey variants instead of the blue ones
  # (Yaru-blue-dark inherits Yaru-blue; Yaru-gray must inherit Yaru-grey).
  sed -i -e "s/^Name=.*/Name=$to/" \
         -e "/^Inherits=/s/\bYaru-blue\b/Yaru-grey/g" "$dest/$to/index.theme"
  rm -f "$dest/$to/icon-theme.cache"

  # Yaru links some directories to sibling themes (../../Yaru-dark/...).
  # Those relative links break once the copy lives elsewhere, so point any
  # link that leaves the variant at the installed target instead.
  local link rel target
  while IFS= read -r -d '' link; do
    rel=${link#"$dest/$to/"}
    target=$(readlink -f "$src/$from/$rel") || continue
    [[ $target == "$src/$from/"* ]] || ln -sfn "$target" "$link"
  done < <(find "$dest/$to" -type l -print0)

  # Raster icons: drop the colour, keep the shading.
  # Regular files only: never write through a link into another theme.
  find "$dest/$to" -type f -name '*.png' -print0 \
    | xargs -0 -r -n 32 -P "$(nproc)" magick mogrify -modulate "$brightness,0"

  # Vector icons: grey every colour value (fill, stroke, stop-color, ...)
  # the same way. Only colour properties are touched, so url(#id) and
  # href="#id" references stay intact; #rgb, #rrggbb, #rrggbbaa and rgb()
  # forms are handled, alpha is kept.
  python3 - "$dest/$to" "$brightness" <<'PY'
import pathlib, re, sys
root, brightness = pathlib.Path(sys.argv[1]), float(sys.argv[2]) / 100

def level(r, g, b):
    # Same as ImageMagick's -modulate B,0 on the PNGs: HSL lightness x B.
    return round(min(1.0, (max(r, g, b) + min(r, g, b)) / 2 * brightness) * 255)

def hex_grey(m):
    h = m.group(2)
    if len(h) in (3, 4):
        h = "".join(c * 2 for c in h)
    v = level(*(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)))
    return f"{m.group(1)}#{v:02x}{v:02x}{v:02x}{h[6:]}"

def rgb_grey(m):
    parts = [float(x) for x in m.group(3).split(",")[:3]]
    v = level(*(p / 255 for p in parts))
    rest = m.group(3).split(",")[3:]
    inner = ",".join([str(v)] * 3 + rest)
    return f"{m.group(1)}{m.group(2)}({inner})"

prop = r"((?:fill|stroke|stop-color|flood-color|lighting-color|color)\s*[:=]\s*[\"']?\s*)"
hex_re = re.compile(prop + r"#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})\b")
rgb_re = re.compile(prop + r"(rgba?)\(([^)]*)\)")
import os
svgs = (pathlib.Path(d) / f for d, _, fs in os.walk(root)  # does not follow links
        for f in fs if f.endswith(".svg"))
for svg in svgs:
    if svg.is_symlink():
        continue
    text = svg.read_text()
    new = rgb_re.sub(rgb_grey, hex_re.sub(hex_grey, text))
    if new != text:
        svg.write_text(new)
PY

  gtk-update-icon-cache -f -t "$dest/$to" >/dev/null 2>&1 || true
  echo "built $dest/$to"
}

build Yaru-blue      Yaru-grey 115
build Yaru-blue-dark Yaru-gray 100
