#!/bin/bash
# Slices a 1024x1024 source PNG into every macOS AppIcon slot.
# Usage: scripts/make-appicon.sh path/to/icon-1024.png
set -euo pipefail

src="${1:?usage: make-appicon.sh <1024x1024.png>}"
out="$(dirname "$0")/../yazar/Assets.xcassets/AppIcon.appiconset"

entries=()
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    px=$((size * scale))
    name="icon_${size}x${size}$([ "$scale" = 2 ] && echo @2x).png"
    sips -s format png -z "$px" "$px" "$src" --out "$out/$name" >/dev/null
    entries+=("{\"idiom\":\"mac\",\"scale\":\"${scale}x\",\"size\":\"${size}x${size}\",\"filename\":\"$name\"}")
  done
done

printf '{"images":[%s],"info":{"author":"xcode","version":1}}' \
  "$(IFS=,; echo "${entries[*]}")" \
  | python3 -m json.tool > "$out/Contents.json"

echo "wrote $out"
