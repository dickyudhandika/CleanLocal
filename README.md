# MiniGuard

MiniGuard is a lightweight macOS menu bar app to monitor system health and clean common junk safely.

## What it does

- Menu bar live health score (CPU, memory, disk, network, zombie-process penalty)
- Monitor tab
  - live CPU / memory / disk stats
  - Quick Clean action for common developer/system caches
- Apps tab
  - scans `/Applications`
  - shows estimated app sizes + last used date
  - uninstall selected apps (with sudo warning when needed)
- Cleanup tab
  - scans high CPU processes, high memory processes, disk junk
  - selective cleanup for only checked items
  - quick actions like `Kill High CPU` and memory purge
- First-run onboarding + quick walkthrough
- GitHub release update check
  - checks latest release from `dickyudhandika/MiniGuard`
  - compares current app version vs latest tag
  - shows `Update vX` button that opens release page

## Requirements

- macOS 13+
- Xcode Command Line Tools (or full Xcode)
- Swift 5.7+

## Run locally

```bash
cd ~/Documents/MiniGuard
swift build
swift run
```

## Build distributable .app bundle

MiniGuard is a SwiftPM executable target, so `swift build` does not auto-generate a `.app` bundle. Use this:

```bash
cd ~/Documents/MiniGuard
swift build -c release

APP_NAME="MiniGuard"
APP_VERSION="0.1.0"
APP_BUNDLE="dist/${APP_NAME}.app"
BIN_PATH=".build/arm64-apple-macosx/release/${APP_NAME}"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>MiniGuard</string>
  <key>CFBundleDisplayName</key>
  <string>MiniGuard</string>
  <key>CFBundleIdentifier</key>
  <string>com.dickyudhandika.miniguard</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleExecutable</key>
  <string>MiniGuard</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
</dict>
</plist>
PLIST

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "dist/${APP_NAME}-macOS-v${APP_VERSION}.zip"
```

Output:
- `dist/MiniGuard.app`
- `dist/MiniGuard-macOS-v0.1.0.zip`

### Publish to GitHub Releases

```bash
cd ~/Documents/MiniGuard

# one-time auth (if not already logged in)
gh auth login -w -s repo
gh auth status

VERSION="v0.1.0"
ZIP="dist/MiniGuard-macOS-${VERSION}.zip"

# tag + push
git tag "$VERSION"
git push origin "$VERSION"

# create release and upload binary zip
gh release create "$VERSION" "$ZIP" \
  --repo dickyudhandika/MiniGuard \
  --title "MiniGuard ${VERSION}" \
  --notes "macOS build for MiniGuard. Download the zip, extract, and move MiniGuard.app to /Applications."
```

If you need to replace a bad asset:

```bash
gh release delete-asset v0.1.0 MiniGuard-macOS-v0.1.0.zip -R dickyudhandika/MiniGuard -y
gh release upload v0.1.0 dist/MiniGuard-macOS-v0.1.0.zip -R dickyudhandika/MiniGuard --clobber
```

## Project structure

- `Package.swift` — Swift Package definition
- `Sources/MiniGuard.swift` — main app code (status item, UI, monitor, cleanup, updater)

## Update feature details

MiniGuard checks:

`https://api.github.com/repos/dickyudhandika/MiniGuard/releases/latest`

Current behavior:

- `Check Updates` triggers GitHub API call
- if newer tag exists, footer shows `Update v<latest>`
- clicking `Update v<latest>` opens the release URL in browser
- if no newer version, shows `You’re up to date`

Note: this is a release-link updater, not in-app auto-install.

## Onboarding reset (for testing)

```bash
defaults delete miniguard miniguard.hasSeenOnboarding
```

## Troubleshooting

- Build issues:
  - make sure active developer directory is valid (`xcode-select -p`)
  - if needed, switch to full Xcode toolchain
- If multiple app instances are running from repeated `swift run`:

```bash
pkill -f '/Users/thenom4design/Documents/MiniGuard/.build/arm64-apple-macosx/debug/MiniGuard'
```

## Safety notes

- Several cleanup actions move files/directories into `~/.Trash` (safer than hard delete).
- Some operations (especially uninstalling root-owned apps) may require sudo and can fail without elevated permissions.

## License

Private/internal project unless specified otherwise.
