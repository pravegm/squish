# Sourced by ci/screenshots.sh and ci/store-set.sh: `store_frame <args>` runs ci/store-frame.swift (the host-side
# caption compositor), compiled once per shell into a temporary binary, or interpreted with `xcrun swift` if the
# compile fails. Returns the tool's status; callers treat a failure as a warning.
STORE_FRAME_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/store-frame.swift"
STORE_FRAME_BIN=""
STORE_FRAME_TRIED=0

store_frame() {
  if (( STORE_FRAME_TRIED == 0 )); then
    STORE_FRAME_TRIED=1
    local dir bin
    dir="$(mktemp -d)"; bin="$dir/store-frame"
    if xcrun swiftc -O -swift-version 5 -module-name StoreFrame "$STORE_FRAME_SRC" -o "$bin" >"$dir/build.log" 2>&1; then
      STORE_FRAME_BIN="$bin"
    else
      echo "warning: could not compile ci/store-frame.swift (falling back to xcrun swift):" >&2
      tail -20 "$dir/build.log" >&2 || true
    fi
  fi
  if [[ -n "$STORE_FRAME_BIN" ]]; then
    "$STORE_FRAME_BIN" "$@"
  else
    xcrun swift "$STORE_FRAME_SRC" "$@"
  fi
}

# png_size <file>: "<width>x<height> alpha=<yes|no>" via sips, or "?" when unreadable.
png_size() {
  local w h a
  w=$(sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth/ {print $2}' || true)
  h=$(sips -g pixelHeight "$1" 2>/dev/null | awk '/pixelHeight/ {print $2}' || true)
  a=$(sips -g hasAlpha "$1" 2>/dev/null | awk '/hasAlpha/ {print $2}' || true)
  if [[ -z "$w" || -z "$h" ]]; then echo "?"; else echo "${w}x${h} alpha=${a:-?}"; fi
}
