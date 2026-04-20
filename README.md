# CleanLocal

CleanLocal is a lightweight macOS menu bar app to monitor system health and clean common junk safely.

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
  - checks latest release from `dickyudhandika/CleanLocal`
  - compares current app version vs latest tag
  - shows `Update vX` button that opens release page

## Requirements

- macOS 13+
- Xcode Command Line Tools (or full Xcode)
- Swift 5.7+

## Run locally

```bash
cd ~/Documents/CleanLocal
swift build
swift run
```

## Build distributable .app bundle

CleanLocal is a SwiftPM app project. Current executable target name is still `CleanLocal`, so `swift build` does not auto-generate a `.app` bundle. Use this:

```bash
cd ~/Documents/CleanLocal
swift build -c release

APP_NAME="CleanLocal"
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
  <string>CleanLocal</string>
  <key>CFBundleDisplayName</key>
  <string>CleanLocal</string>
  <key>CFBundleIdentifier</key>
  <string>com.dickyudhandika.cleanlocal</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleExecutable</key>
  <string>CleanLocal</string>
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
- `dist/CleanLocal.app`
- `dist/CleanLocal-macOS-v0.1.0.zip`

### Publish to GitHub Releases

```bash
cd ~/Documents/CleanLocal

# one-time auth (if not already logged in)
gh auth login -w -s repo
gh auth status

VERSION="v0.1.0"
ZIP="dist/CleanLocal-macOS-${VERSION}.zip"

# tag + push
git tag "$VERSION"
git push origin "$VERSION"

# create release and upload binary zip
gh release create "$VERSION" "$ZIP" \
  --repo dickyudhandika/CleanLocal \
  --title "CleanLocal ${VERSION}" \
  --notes "macOS build for CleanLocal. Download the zip, extract, and move CleanLocal.app to /Applications."
```

If you need to replace a bad asset:

```bash
gh release delete-asset v0.1.0 CleanLocal-macOS-v0.1.0.zip -R dickyudhandika/CleanLocal -y
gh release upload v0.1.0 dist/CleanLocal-macOS-v0.1.0.zip -R dickyudhandika/CleanLocal --clobber
```

## Project structure

- `Package.swift` — Swift Package definition
- `Sources/CleanLocal.swift` — main app code (status item, UI, monitor, cleanup, updater)

## Update feature details

CleanLocal checks:

`https://api.github.com/repos/dickyudhandika/CleanLocal/releases/latest`

Current behavior:

- `Check Updates` triggers GitHub API call
- if newer tag exists, app shows a visible update banner at the top
- the banner shows `current` vs `latest` version
- user can choose `Update Now`, `Later`, or `Check Again`
- clicking `Update Now` opens the release URL in browser
- if no newer version, shows `You’re up to date`

Note: this is a release-link updater, not in-app auto-install.

### How to test `Check Updates`

Fastest way:

1. Keep your local app on an older version (example: `0.1.0`).
2. Create a newer GitHub release tag (example: `v0.1.1`).
3. Upload any zip asset to that release.
4. Open CleanLocal and click `Check Updates`.
5. You should see the update banner at the top with:
   - current version
   - latest version
   - `Update Now`
   - `Later`
   - `Check Again`

Example release test flow:

```bash
cd ~/Documents/CleanLocal
VERSION="v0.1.1"
ZIP="dist/CleanLocal-macOS-${VERSION}.zip"

git tag "$VERSION"
git push origin "$VERSION"

gh release create "$VERSION" "$ZIP" \
  --repo dickyudhandika/CleanLocal \
  --title "CleanLocal ${VERSION}" \
  --notes "Test release for updater UI."
```

Important:
- `Check Updates` compares the app bundle version against the latest GitHub release tag.
- If your local app is already the same version as the latest release, you will only see `You’re up to date`.
- So to test the banner properly, GitHub must have a higher version than the app you are running.

## Onboarding reset (for testing)

```bash
defaults delete cleanlocal cleanlocal.hasSeenOnboarding
```

## Troubleshooting

- Build issues:
  - make sure active developer directory is valid (`xcode-select -p`)
  - if needed, switch to full Xcode toolchain
- If multiple app instances are running from repeated `swift run`:

```bash
pkill -f '/Users/thenom4design/Documents/CleanLocal/.build/arm64-apple-macosx/debug/CleanLocal'
```

## Safety notes

- Several cleanup actions move files/directories into `~/.Trash` (safer than hard delete).
- Some operations (especially uninstalling root-owned apps) may require sudo and can fail without elevated permissions.

## License

Private/internal project unless specified otherwise.
