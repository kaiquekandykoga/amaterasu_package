#!/bin/sh
# Installs the latest Amaterasu into /Applications:
#
#   curl -fsSL https://raw.githubusercontent.com/kaiquekandykoga/amaterasu_package/master/install.sh | sh
#
# It downloads the same disk image as the site's Download button, checks it, and copies the app out
# of it. Read it before you run it: https://github.com/kaiquekandykoga/amaterasu_package
set -eu

dmg_url=https://github.com/kaiquekandykoga/amaterasu_package/releases/latest/download/Amaterasu.dmg
applications=/Applications
app="$applications/Amaterasu.app"

fail() {
  echo "Amaterasu wasn't installed: $*" >&2
  exit 1
}

# Everything runs from here, so a script cut short in the download does nothing.
main() {
  [ "$(uname -s)" = Darwin ] || fail "it runs on macOS only."
  macos=$(sw_vers -productVersion)
  [ "${macos%%.*}" -ge 15 ] || fail "it needs macOS 15 or later, and this Mac has macOS $macos."
  if pgrep -xq Amaterasu; then
    fail "it's open. Quit Amaterasu, then run this again."
  fi
  [ -w "$applications" ] || fail "you can't write to $applications."
  # The app's own architecture, even when this shell runs under Rosetta.
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then arch=arm64; else arch=x86_64; fi

  tmp=$(mktemp -d)
  mount="$tmp/mount"
  # Stopped between moving the old app aside and putting the new one in place (Ctrl-C, or the
  # window closed), the old app goes back, so the Mac is never left without one.
  # Only this run's own copy goes back: an older Amaterasu.app.old left by an earlier run is never
  # brought back in place of an app the user removed.
  moved_aside=0
  # set +e: under set -e the trap would stop at its first failing step (nothing mounted yet, say)
  # and skip the rest of the clean-up, or putting the old app back.
  trap 'set +e; hdiutil detach -quiet "$mount" 2>/dev/null; rm -rf "$tmp" "$app.installing"; if [ "$moved_aside" = 1 ] && [ ! -e "$app" ] && [ -e "$app.old" ]; then mv "$app.old" "$app"; fi' EXIT
  trap 'exit 130' INT TERM HUP

  echo "Downloading Amaterasu..."
  curl -fL --progress-bar -o "$tmp/Amaterasu.dmg" "$dmg_url" || fail "the download didn't finish."
  hdiutil verify -quiet "$tmp/Amaterasu.dmg" </dev/null || fail "the download is damaged. Run this again."
  mkdir "$mount"
  hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$mount" "$tmp/Amaterasu.dmg" </dev/null ||
    fail "the disk image wouldn't open."

  new="$mount/Amaterasu.app"
  [ -d "$new" ] || fail "the disk image doesn't hold Amaterasu."
  codesign --verify --deep --strict "$new" 2>/dev/null || fail "Amaterasu's signature doesn't check out."
  lipo "$new/Contents/MacOS/Amaterasu" -verify_arch "$arch" 2>/dev/null ||
    fail "this version isn't built for this Mac ($arch)."
  version=$(plutil -extract CFBundleShortVersionString raw -o - "$new/Contents/Info.plist")

  # Copy beside the old app first, so a failed copy leaves the old one in place.
  rm -rf "$app.installing"
  ditto "$new" "$app.installing" || fail "it couldn't be copied to $applications."
  # The old app is moved aside, not deleted, until the new one is in place: a removal that failed
  # part-way would leave a broken app behind.
  rm -rf "$app.old" || fail "an earlier $app.old couldn't be removed."
  if [ -e "$app" ]; then
    mv "$app" "$app.old" || fail "the installed Amaterasu couldn't be moved aside."
    moved_aside=1
  fi
  if ! mv "$app.installing" "$app"; then
    [ -e "$app.old" ] && mv "$app.old" "$app"
    fail "it couldn't be moved into $applications."
  fi
  rm -rf "$app.old" 2>/dev/null || echo "Left the previous version at $app.old; delete it when you like." >&2

  echo "Installed Amaterasu $version in $applications. Open it from Applications or Launchpad."
}

main "$@"
