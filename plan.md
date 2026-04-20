# skwish-my-mac — Smart Cleanup Feature

## The Pitch
skwish-my-mac becomes the "you probably don't need that anymore" app. It watches what you don't use, finds junk you forgot about, and cleans it — all from your menu bar.

---

## Feature 1: Unused App Detector

### The idea
Scan apps you haven't opened in a week (or more). Show them. Let you decide.

### How it works
- Checks `kMDItemLastUsedDate` (Spotlight metadata) for every `.app` in `/Applications`
- Shows: app name, size, last opened date
- Sorted by "least recently used" first
- Default filter: apps not opened in 7+ days
- User picks what to trash → skwish-my-mac handles everything

### UI
- Section: **"Apps"**
- Dropdown: "Not used in..." → 7 days / 14 days / 30 days / 60 days
- List: [app icon] name — size — last used: "3 weeks ago"
- "Uninstall Selected" button
- Confirmation shows total space to reclaim

### Uninstall flow (per app, general)
1. Kill running processes
2. Remove login items if any
3. Move .app to Trash
4. Scan and clean common leftover locations:
   - `~/Library/Application Support/[AppName]`
   - `~/Library/Caches/[bundle-id]`
   - `~/Library/Preferences/[bundle-id].plist`
   - `~/Library/Containers/[bundle-id]`
   - `~/Library/Logs/[AppName]`
5. Report what was freed

### Scan command
```bash
# Get last used date for all apps
mdls -name kMDItemLastUsedDate -name kMDItemDisplayName /Applications/*.app

# Get app sizes
du -sh /Applications/*.app 2>/dev/null | sort -rh
```

---

## Feature 2: Junk Finder (by domain)

### The idea
Three categories — CPU, Memory, Disk. Each one finds different types of junk and lets you clean them independently.

### UI
- Section: **"Cleanup"**
- Three expandable cards:
  - 🖥️ **CPU** — runaway processes
  - 🧠 **Memory** — memory hogs
  - 💾 **Disk** — space reclamation
- Each card shows what it found + estimated savings
- "Clean" button per category (or "Clean All")

---

### 🖥️ CPU — Process Cleanup
Finds processes consuming abnormal CPU.

**What it detects:**
- Zombie/stuck processes (>50% CPU sustained)
- Orphaned helper processes from apps that aren't open
- Browser tab processes eating CPU (Chrome/Edge/Firefox helpers)

**UI shows:**
- Process name, CPU %, memory usage
- "Kill" button per process
- "Kill All High CPU" bulk action

**Scan:**
```bash
# Top CPU consumers (exclude system-critical)
ps aux | sort -k3 -rn | head -20 | awk '$3 > 20.0 {print}'
```

---

### 🧠 Memory — Memory Optimization
Finds what's hogging RAM.

**What it detects:**
- Apps using disproportionate memory relative to usefulness
- Browser tabs with high memory footprint
- Cached data that could be purged
- Inactive memory that can be flushed

**UI shows:**
- Memory breakdown (active, wired, compressed, cached)
- Top memory consumers list
- "Purge Memory" button (flushes inactive cache)
- "Clear App Caches" button (safe, rebuilds on next launch)

**Scan:**
```bash
# Memory stats
vm_stat

# Top memory consumers
ps aux | sort -k4 -rn | head -20

# Size of user caches
du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh | head -10
```

---

### 💾 Disk — Space Reclamation
The big one. Finds forgotten files, stale caches, old downloads.

**What it scans (general, no hardcoded paths):**

| Category | What it finds | Typical savings |
|----------|--------------|----------------|
| App Caches | `~/Library/Caches/*` — all app caches | 2-10 GB |
| Old Downloads | `~/Downloads` files older than 7/14/30 days | 1-5 GB |
| Browser Caches | Chrome/Safari/Firefox cached data | 1-4 GB |
| Trash | `~/.Trash` — stuff you already deleted | varies |
| Dev Build Artifacts | `node_modules`, `.next`, `__pycache__`, `DerivedData` | 2-20 GB |
| Large Old Files | Files >100MB not touched in 30+ days | varies |
| App Leftovers | Library data from apps no longer installed | 1-5 GB |
| System Logs | `~/Library/Logs`, `/var/log` | 0.5-2 GB |
| iOS Backups | `~/Library/Application Support/MobileSync` | 5-50 GB |

**Scan approach — generic, not hardcoded:**
```bash
# Caches
du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh

# Old downloads
find ~/Downloads -maxdepth 1 -type f -mtime +7 -size +100k

# Large files
find ~ -maxdepth 4 -type f -size +100M -mtime +30 2>/dev/null

# Dev artifacts (node_modules, .next, __pycache__)
find ~ -maxdepth 5 \( -name "node_modules" -o -name ".next" -o -name "__pycache__" \) -type d 2>/dev/null

# Orphaned app data (Library entries for apps not in /Applications)
# Compare ~/Library/Application Support dirs against /Applications

# Trash size
du -sh ~/.Trash/
```

**UI shows:**
- Category cards with size found
- Expand to see individual items
- Check/uncheck items before cleaning
- "Clean Selected" with total space estimate

---

## Feature 3: Whitelist / Protected Apps (future)

Let users mark apps as "never suggest removing." Stored in a local JSON config.

```json
{
  "protectedApps": ["Bitdefender", "SkwishMyMac", "Raycast"],
  "cleanupPreferences": {
    "autoCleanCaches": false,
    "downloadAgeThreshold": 14,
    "appUnusedThreshold": 30
  }
}
```

---

## Feature 4: True background / menu-bar-only app

### The idea
When skwish-my-mac launches, it should behave like a real background utility:
- lives in the macOS menu bar
- no Dock icon
- no normal app window required
- opening/closing the popover should feel like show/hide, not launch/quit noise

### Expected behavior
- Launching the app shows the status item in the menu bar
- The app does not appear in the Dock during normal use
- The app can be "closed" back to the menu bar without quitting
- Quit remains an explicit action from the menu bar

### Likely implementation
- Set app activation policy to accessory/agent so it behaves as a menu-bar utility
- Add `LSUIElement` to the app bundle plist so macOS hides the Dock icon
- Keep Settings/Preferences optional, not as a regular window scene
- Verify update flow, alerts, and popovers still work correctly without a Dock presence

### Notes / caveats
- This is absolutely doable
- If we hide the Dock icon, we should make sure there is still an obvious `Quit` action in the menu bar
- Any future settings/about screen may need explicit open/focus behavior since there is no Dock app to click back to

---

## Implementation Order

1. **Disk Junk Finder** (biggest value, most general)
2. **Unused App Detector** (high value, general use case)
3. **CPU + Memory sections** (quick wins, simpler)
4. **Whitelist** (polish, nice to have)

## Architecture

- All destructive ops: `mv ~/.Trash/` (never `rm -rf`)
- Everything async via `Process()` (existing pattern)
- Popover stays 320px wide, scrollable
- Local config at `~/.skwishmymac/config.json` for preferences + whitelist
- No telemetry, no network calls — everything stays local

## Key Design Decisions
- **General over specific** — no hardcoded app names or paths (except common Apple locations)
- **User confirms everything** — nothing gets deleted without showing what + how much
- **Safe by default** — caches and trash first, apps require explicit selection
- **Time-based thresholds** — "not used in X days" is more useful than raw size sorting
- **Categories matter** — CPU vs Memory vs Disk are different problems, different solutions

---

## Activity Log

### 2026-04-20 (WIB)
- Rebranded project from MiniGuard to skwish-my-mac (local folder + GitHub repo)
- Renamed GitHub repo to `dickyudhandika/skwish-my-mac` and confirmed it is public
- Updated local remote URL to `https://github.com/dickyudhandika/skwish-my-mac.git`
- Updated README for skwish-my-mac naming, paths, release commands, and updater endpoint
- Full codebase rename sweep completed:
  - `Package.swift` package/product/target renamed to `skwish-my-mac`
  - `Sources/MiniGuard.swift` -> `Sources/skwish-my-mac.swift`
  - `Tests/MiniGuardTests/...` -> `Tests/skwish-my-macTests/...`
  - internal app types/labels (`MiniGuardApp`, tabs, UI strings) renamed to skwish-my-mac
  - config/storage prefixes changed from `miniguard` to `skwishmymac`
  - updater repo switched to `dickyudhandika/skwish-my-mac`
- Updated docs and marketing files (`README.md`, `docs/index.html`, `plan.md`) to skwish-my-mac branding
- Rebuilt app after rename and fixed stale module cache issue via reset/clean rebuild
- Built distributable app bundle locally:
  - `dist/skwish-my-mac.app`
  - `dist/skwish-my-mac-macOS-v0.1.0.zip`
- Changes pushed to GitHub (`main`) including rebrand commit (`e489833`)
- Implemented Quick Clean v2 phased flow for real users + dev-aware cleanup:
  - Phase 1: public-safe auto cleanup candidates
  - Phase 2: app leftover detection (review-first)
  - Phase 3: dev cleanup only when signals exist (`npm`, `pip`, `homebrew`, dev artifacts)
  - Phase 4: risky actions as suggestions only (no auto execute)
- Removed personalized/risky Quick Clean defaults:
  - Removed `~/.hermes/*` cleanup from Quick Clean
  - Removed blanket `python3.11` kill from Quick Clean
  - Removed DNS flush from Quick Clean
- Added Quick Clean policy + tests and verified green:
  - `swift build` ✅
  - `swift test` ✅ (4 tests passing)
- Local commit created for phased Quick Clean:
  - `f686b1b` — `feat: implement phased quick clean with safe public + dev-aware flow`
- Rebuilt local dist artifacts for manual testing before push:
  - `dist/skwish-my-mac.app` (~976K)
  - `dist/skwish-my-mac-macOS-v0.1.0.zip` (~256K)
- Planned next updater improvement before coding:
  - show a clearer in-app `new update available` state
  - show current version vs latest version
  - keep updates optional/manual so user can stay on current version
  - add visible update banner/card instead of relying only on footer text
  - plan saved at `.hermes/plans/2026-04-20_124157-update-banner-and-optional-manual-update.md`
- Implemented optional/manual updater UX:
  - added structured `UpdateState` + `UpdatePolicy`
  - update check now distinguishes `checking`, `up to date`, `update available`, and `error`
  - visible update banner now shows `current` vs `latest` version
  - user can choose `Update Now`, `Later`, or `Check Again`
  - keeping old version is explicitly supported; no forced update flow
  - footer kept as secondary status/check area
- Added updater tests and verified green:
  - `swift test` ✅ (7 tests passing)
  - `swift build` ✅
- Rebuilt dist artifacts after updater UI implementation:
  - `dist/skwish-my-mac.app` (~1.0M)
  - `dist/skwish-my-mac-macOS-v0.1.0.zip` (~264K)
- Updated README with GitHub-based updater test instructions:
  - documented top update banner behavior
  - added exact release-tag flow to test `Check Updates`
  - clarified that GitHub must have a higher version than the running app
- Rebranded project end-to-end to `skwish-my-mac`:
  - GitHub repo renamed to `dickyudhandika/skwish-my-mac`
  - local folder renamed to `~/Documents/skwish-my-mac`
  - git remote updated to `https://github.com/dickyudhandika/skwish-my-mac.git`
  - Swift package/target/test names migrated to `SkwishMyMac`
  - source/test paths renamed to `Sources/SkwishMyMac.swift` and `Tests/SkwishMyMacTests/...`
  - docs/README/release/update-check references switched to new brand/repo
- Published GitHub Release for rebranded app:
  - tag: `v0.1.1`
  - asset: `dist/skwish-my-mac-macOS-v0.1.1.zip`
  - URL: `https://github.com/dickyudhandika/skwish-my-mac/releases/tag/v0.1.1`
- Added drag-to-Applications DMG installer UX for real users:
  - built `dist/skwish-my-mac-macOS-v0.1.1.dmg`
  - DMG includes `SkwishMyMac.app` + `Applications` shortcut for drag-install flow
  - uploaded DMG to release `v0.1.1`
- Updated `v0.1.1` release notes with human install steps:
  - recommended DMG flow (open DMG -> drag app to Applications)
  - kept ZIP fallback steps
  - included Gatekeeper first-launch fallback command:
    - `xattr -dr com.apple.quarantine /Applications/SkwishMyMac.app`
- Added next feature to the product plan:
  - make skwish-my-mac a true background/menu-bar-only app
  - hide Dock icon during normal use
  - keep explicit Quit from the menu bar
- Implemented menu-bar-only runtime launch policy:
  - app now sets activation policy at launch (`.accessory` for background/menu-bar mode)
  - added `AppLaunchPolicy` with env override `SKWISH_SHOW_DOCK=1` for dev/debug
  - default behavior is menu-bar-only even when `LSUIElement` is missing
- Added tests for launch policy behavior:
  - default menu-bar-only mode
  - `LSUIElement` true/false handling
  - Dock override environment handling
  - `swift test` ✅ (10 tests passing)
- Updated packaging docs + bundle metadata for Dockless app UX:
  - `README.md` Info.plist template now sets `LSUIElement=true`
  - corrected `CFBundleExecutable` to `SkwishMyMac`
  - rebuilt `dist/SkwishMyMac.app` and `dist/skwish-my-mac-macOS-v0.1.1.zip` with `LSUIElement=true`
- Prepared new release artifacts for Dockless/menu-bar-only launch fix:
  - built `dist/skwish-my-mac-macOS-v0.1.2.zip`
  - built `dist/skwish-my-mac-macOS-v0.1.2.dmg`
  - bundle version set to `0.1.2` with `LSUIElement=true`

Last updated: 2026-04-20 18:33:52 WIB
