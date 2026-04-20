# CleanLocal — Smart Cleanup Feature

## The Pitch
CleanLocal becomes the "you probably don't need that anymore" app. It watches what you don't use, finds junk you forgot about, and cleans it — all from your menu bar.

---

## Feature 1: Unused App Detector

### The idea
Scan apps you haven't opened in a week (or more). Show them. Let you decide.

### How it works
- Checks `kMDItemLastUsedDate` (Spotlight metadata) for every `.app` in `/Applications`
- Shows: app name, size, last opened date
- Sorted by "least recently used" first
- Default filter: apps not opened in 7+ days
- User picks what to trash → CleanLocal handles everything

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
  "protectedApps": ["Bitdefender", "CleanLocal", "Raycast"],
  "cleanupPreferences": {
    "autoCleanCaches": false,
    "downloadAgeThreshold": 14,
    "appUnusedThreshold": 30
  }
}
```

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
- Local config at `~/.cleanlocal/config.json` for preferences + whitelist
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
- Rebranded project from MiniGuard to CleanLocal (local folder + GitHub repo)
- Renamed GitHub repo to `dickyudhandika/CleanLocal` and confirmed it is public
- Updated local remote URL to `https://github.com/dickyudhandika/CleanLocal.git`
- Updated README for CleanLocal naming, paths, release commands, and updater endpoint
- Full codebase rename sweep completed:
  - `Package.swift` package/product/target renamed to `CleanLocal`
  - `Sources/MiniGuard.swift` -> `Sources/CleanLocal.swift`
  - `Tests/MiniGuardTests/...` -> `Tests/CleanLocalTests/...`
  - internal app types/labels (`MiniGuardApp`, tabs, UI strings) renamed to CleanLocal
  - config/storage prefixes changed from `miniguard` to `cleanlocal`
  - updater repo switched to `dickyudhandika/CleanLocal`
- Updated docs and marketing files (`README.md`, `docs/index.html`, `plan.md`) to CleanLocal branding
- Rebuilt app after rename and fixed stale module cache issue via reset/clean rebuild
- Built distributable app bundle locally:
  - `dist/CleanLocal.app`
  - `dist/CleanLocal-macOS-v0.1.0.zip`
- Changes pushed to GitHub (`main`) including rebrand commit (`e489833`)

Last updated: 2026-04-20 09:18:27 WIB
