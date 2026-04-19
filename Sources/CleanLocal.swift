import SwiftUI
import AppKit

@main
struct CleanLocalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }
}

// MARK: - Models
enum CleanLocalTab: String, CaseIterable, Identifiable {
    case monitor = "Monitor"
    case apps = "Apps"
    case cleanup = "Cleanup"

    var id: String { rawValue }
}

struct InstalledApp: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let sizeGB: Double
    let lastUsed: Date?
    let needsSudo: Bool
    var isSelected: Bool = false
}

struct ProcessItem: Identifiable {
    let id = UUID()
    let pid: Int
    let user: String
    let cpu: Double
    let memPercent: Double
    let rssMB: Double
    let command: String
}

enum JunkDomain: String {
    case disk = "Disk"
    case cpu = "CPU"
    case memory = "Memory"
}

struct CleanableItem: Identifiable {
    let id = UUID()
    let domain: JunkDomain
    let title: String
    let path: String
    let sizeGB: Double
    var isChecked: Bool = true
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

// MARK: - Status Bar Controller
class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var monitor: SystemMonitor!
    private var timer: Timer?

    init() {
        monitor = SystemMonitor()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 620)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(monitor: monitor))

        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }

        updateStatus()
        monitor.refresh()
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            monitor.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateStatus() {
        monitor.refresh()

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }

            let health = self.monitor.overallHealth
            let (icon, color) = Self.healthIcon(for: health)

            let attachment = NSTextAttachment()
            attachment.image = Self.createDot(color: color, size: 10)
            let dotString = NSAttributedString(attachment: attachment)

            let textString = NSAttributedString(
                string: " \(icon) \(health)%",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: color
                ]
            )

            let combined = NSMutableAttributedString()
            combined.append(dotString)
            combined.append(textString)
            button.attributedTitle = combined
        }
    }

    private static func healthIcon(for health: Int) -> (String, NSColor) {
        switch health {
        case 80...100: return ("●", NSColor.systemGreen)
        case 50..<80:  return ("◐", NSColor.systemYellow)
        default:       return ("○", NSColor.systemRed)
        }
    }

    private static func createDot(color: NSColor, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        color.set()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

// MARK: - System Monitor
class SystemMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var diskUsage: Double = 0
    @Published var diskUsedGB: Double = 0
    @Published var diskTotalGB: Double = 0
    @Published var diskFreeGB: Double = 0
    @Published var networkUp: Bool = true
    @Published var energyHigh: Bool = false
    @Published var zombieProcessCount: Int = 0
    @Published var cleanableDiskGB: Double = 0
    @Published var overallHealth: Int = 100
    @Published var isCleaning: Bool = false
    @Published var lastCleaned: String = "Never"
    @Published var cleanupLog: [String] = []

    @Published var selectedTab: CleanLocalTab = .monitor

    // Apps tab
    @Published var installedApps: [InstalledApp] = []
    @Published var appUnusedThresholdDays: Int = 7
    @Published var isScanningApps: Bool = false
    @Published var isUninstallingApps: Bool = false
    @Published var uninstallLog: [String] = []

    // Cleanup tab
    @Published var highCPUProcesses: [ProcessItem] = []
    @Published var highMemoryProcesses: [ProcessItem] = []
    @Published var diskJunkItems: [CleanableItem] = []
    @Published var isScanningCleanup: Bool = false
    @Published var cleanupDomainLog: [String] = []

    // Updates
    @Published var isCheckingUpdates: Bool = false
    @Published var updateStatusMessage: String = ""
    @Published var updateAvailableVersion: String? = nil
    @Published var latestReleaseURL: String? = nil
    @Published var lastUpdateCheckedAt: Date? = nil

    // GitHub repo for releases: owner/repo
    private let updateRepo = "dickyudhandika/CleanLocal"

    func refresh() {
        updateCPU()
        updateMemory()
        updateDisk()
        updateNetwork()
        updateZombieProcesses()
        updateCleanableCache()
        calculateHealth()
    }

    var filteredInstalledApps: [InstalledApp] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -appUnusedThresholdDays, to: Date()) ?? Date()
        return installedApps
            .filter { app in
                guard let lastUsed = app.lastUsed else { return true }
                return lastUsed < cutoff
            }
            .sorted { lhs, rhs in
                switch (lhs.lastUsed, rhs.lastUsed) {
                case let (l?, r?):
                    return l < r
                case (nil, _?):
                    return true
                case (_?, nil):
                    return false
                case (nil, nil):
                    return lhs.sizeGB > rhs.sizeGB
                }
            }
    }

    var selectedAppsCount: Int {
        filteredInstalledApps.filter { $0.isSelected }.count
    }

    var selectedAppsEstimatedGB: Double {
        filteredInstalledApps.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeGB }
    }

    var selectedDiskEstimatedGB: Double {
        diskJunkItems.filter { $0.isChecked }.reduce(0) { $0 + $1.sizeGB }
    }

    // MARK: Core Metrics
    private func updateCPU() {
        var cpuInfo: processor_info_array_t!
        var cpuInfoSize: mach_msg_type_number_t = 0
        var numCpuInfo: natural_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpuInfo, &cpuInfo, &cpuInfoSize)
        guard result == KERN_SUCCESS else { return }

        let cpuCount = Int(numCpuInfo) / Int(CPU_STATE_MAX)
        var totalUsage: Double = 0

        for i in 0..<cpuCount {
            let user   = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_USER)])
            let system = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_SYSTEM)])
            let idle   = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_IDLE)])
            let nice   = Double(cpuInfo[Int(CPU_STATE_MAX) * i + Int(CPU_STATE_NICE)])
            let total  = user + system + idle + nice
            if total > 0 {
                totalUsage += ((user + system + nice) / total) * 100.0
            }
        }

        DispatchQueue.main.async {
            self.cpuUsage = min(totalUsage / Double(max(cpuCount, 1)), 100)
        }

        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(cpuInfoSize))
    }

    private func updateMemory() {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let pageSize = Double(vm_kernel_page_size)
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let usedBytes = Double(vmStats.active_count + vmStats.wire_count + vmStats.compressor_page_count) * pageSize

        DispatchQueue.main.async {
            self.memoryTotalGB = totalBytes / 1_073_741_824
            self.memoryUsedGB = usedBytes / 1_073_741_824
            self.memoryUsage = (usedBytes / totalBytes) * 100
        }
    }

    private func updateDisk() {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let totalSize = attrs[.systemSize] as? Int64,
              let freeSize = attrs[.systemFreeSize] as? Int64 else { return }

        let usedSize = totalSize - freeSize
        let gb = 1_073_741_824.0

        DispatchQueue.main.async {
            self.diskTotalGB = Double(totalSize) / gb
            self.diskFreeGB = Double(freeSize) / gb
            self.diskUsedGB = Double(usedSize) / gb
            self.diskUsage = (Double(usedSize) / Double(totalSize)) * 100
        }
    }

    private func updateNetwork() {
        let task = Process()
        task.launchPath = "/sbin/ping"
        task.arguments = ["-c", "1", "-t", "2", "1.1.1.1"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.launch()
        task.waitUntilExit()

        DispatchQueue.main.async {
            self.networkUp = (task.terminationStatus == 0)
        }
    }

    private func updateZombieProcesses() {
        let output = shell("ps aux | grep python3.11 | grep -v grep | wc -l")
        let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        DispatchQueue.main.async {
            self.zombieProcessCount = count
        }
    }

    private func updateCleanableCache() {
        let output = shell("""
            total=0
            for dir in ~/.npm/_cacache ~/Library/Caches/Homebrew ~/.hermes/sessions ~/.hermes/logs ~/Library/Caches/pip; do
                size=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
                size=${size:-0}
                total=$((total + size))
            done
            echo $total
        """)

        let kb = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        DispatchQueue.main.async {
            self.cleanableDiskGB = kb / 1_048_576
        }
    }

    private func calculateHealth() {
        let cpuScore = max(0, 100 - cpuUsage)
        let memScore = max(0, 100 - memoryUsage)
        let diskScore = max(0, 100 - diskUsage)
        let netScore: Double = networkUp ? 100 : 0
        let zombiePenalty = Double(min(zombieProcessCount * 10, 50))

        let raw = (cpuScore * 0.25) + (memScore * 0.25) + (diskScore * 0.3) + (netScore * 0.1) + (100 - zombiePenalty) * 0.1
        let clamped = max(0, min(100, Int(raw)))

        DispatchQueue.main.async {
            self.overallHealth = clamped
            self.energyHigh = self.cpuUsage > 60
        }
    }

    // MARK: Quick Clean
    func cleanNow() {
        guard !isCleaning else { return }

        DispatchQueue.main.async {
            self.isCleaning = true
            self.cleanupLog = []
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let script = """
            echo "1/6 Nuking npm cache..."
            npm cache clean --force 2>/dev/null
            mv ~/.npm/_cacache ~/.Trash/cleanlocal-npm-cacache-$(date +%s) 2>/dev/null
            mv ~/.npm/_logs ~/.Trash/cleanlocal-npm-logs-$(date +%s) 2>/dev/null

            echo "2/6 Wiping Homebrew cache..."
            mv ~/Library/Caches/Homebrew ~/.Trash/cleanlocal-homebrew-cache-$(date +%s) 2>/dev/null

            echo "3/6 Clearing Hermes sessions..."
            mv ~/.hermes/sessions ~/.Trash/cleanlocal-hermes-sessions-$(date +%s) 2>/dev/null
            mv ~/.hermes/logs ~/.Trash/cleanlocal-hermes-logs-$(date +%s) 2>/dev/null
            mv ~/.hermes/.cache ~/.Trash/cleanlocal-hermes-cache-$(date +%s) 2>/dev/null
            mv ~/.hermes/tools-cache ~/.Trash/cleanlocal-hermes-tools-cache-$(date +%s) 2>/dev/null

            echo "4/6 Purging pip cache..."
            mv ~/Library/Caches/pip ~/.Trash/cleanlocal-pip-cache-$(date +%s) 2>/dev/null

            echo "5/6 Killing zombie python3.11..."
            pids=$(ps aux | grep python3.11 | grep -v grep | awk '{print $2}')
            if [ -n "$pids" ]; then
              echo "$pids" | xargs kill -9 2>/dev/null
              echo "Zombies: zapped"
            else
              echo "Zombies: none found"
            fi

            echo "6/6 Flushing DNS..."
            dscacheutil -flushcache 2>/dev/null
            killall -HUP mDNSResponder 2>/dev/null
            """

            let output = self.shell(script)
            let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

            DispatchQueue.main.async {
                self.isCleaning = false
                self.cleanupLog = lines
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                self.lastCleaned = formatter.string(from: Date())
                self.refresh()
            }
        }
    }

    // MARK: Apps Tab
    func scanInstalledApps() {
        guard !isScanningApps else { return }

        isScanningApps = true
        uninstallLog = ["Scanning /Applications..."]

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let appRoot = "/Applications"

            guard let paths = try? fm.contentsOfDirectory(atPath: appRoot).filter({ $0.hasSuffix(".app") }) else {
                DispatchQueue.main.async {
                    self.isScanningApps = false
                    self.uninstallLog.append("Failed to read /Applications")
                }
                return
            }

            var apps: [InstalledApp] = []
            let total = max(paths.count, 1)

            for (idx, name) in paths.enumerated() {
                let path = appRoot + "/" + name
                let appName = name.replacingOccurrences(of: ".app", with: "")

                let sizeKBOutput = self.shell("du -sk \(self.sh(path)) 2>/dev/null | awk '{print $1}'")
                let sizeKB = Double(sizeKBOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let sizeGB = sizeKB / 1_048_576

                let mdlsRaw = self.shell("mdls -raw -name kMDItemLastUsedDate \(self.sh(path)) 2>/dev/null")
                let lastUsed = self.parseMDLSDate(mdlsRaw.trimmingCharacters(in: .whitespacesAndNewlines))

                let attrs = try? fm.attributesOfItem(atPath: path)
                let owner = attrs?[.ownerAccountName] as? String
                let needsSudo = (owner == "root")

                apps.append(
                    InstalledApp(
                        name: appName,
                        path: path,
                        sizeGB: sizeGB,
                        lastUsed: lastUsed,
                        needsSudo: needsSudo,
                        isSelected: false
                    )
                )

                if idx % 10 == 0 || idx == total - 1 {
                    DispatchQueue.main.async {
                        self.uninstallLog = ["Scanning apps... \(idx + 1)/\(total)"]
                    }
                }
            }

            DispatchQueue.main.async {
                self.installedApps = apps
                self.isScanningApps = false
                self.uninstallLog = ["Found \(apps.count) apps. Showing not-used >= \(self.appUnusedThresholdDays) days."]
            }
        }
    }

    func toggleAppSelection(id: UUID) {
        guard let idx = installedApps.firstIndex(where: { $0.id == id }) else { return }
        installedApps[idx].isSelected.toggle()
    }

    func uninstallSelectedApps() {
        guard !isUninstallingApps else { return }

        let idsToRemove = Set(filteredInstalledApps.filter { $0.isSelected }.map { $0.id })
        let apps = installedApps.filter { idsToRemove.contains($0.id) }

        guard !apps.isEmpty else {
            uninstallLog = ["Select at least one app first."]
            return
        }

        isUninstallingApps = true
        uninstallLog = ["Starting uninstall for \(apps.count) app(s)..."]

        DispatchQueue.global(qos: .userInitiated).async {
            var logs: [String] = []

            for app in apps {
                logs.append("--- \(app.name) ---")

                _ = self.shell("killall \(self.sh(app.name)) 2>/dev/null")
                _ = self.shell("osascript -e 'tell application \"System Events\" to delete login item \"\(self.escapeAppleScript(app.name))\"' 2>/dev/null")

                let appTarget = "~/.Trash/cleanlocal-\(self.slug(app.name))-app-$(date +%s).app"
                let moveOutput = self.shell("mv \(self.sh(app.path)) \(appTarget) 2>&1")

                if moveOutput.lowercased().contains("operation not permitted") || moveOutput.lowercased().contains("permission denied") || app.needsSudo {
                    logs.append("needs sudo to move app bundle: \(app.path)")
                } else {
                    logs.append("moved app to Trash")
                }

                let leftovers: [String] = [
                    "~/Library/Application Support/\(app.name)",
                    "~/Library/Caches/*\(self.slug(app.name))*",
                    "~/Library/Preferences/*\(self.slug(app.name))*",
                    "~/Library/Containers/*\(self.slug(app.name))*",
                    "~/Library/Logs/*\(self.slug(app.name))*"
                ]

                for pattern in leftovers {
                    _ = self.shell("for p in \(pattern); do [ -e \"$p\" ] && mv \"$p\" ~/.Trash/cleanlocal-\(self.slug(app.name))-$(basename \"$p\")-$(date +%s) 2>/dev/null; done")
                }

                logs.append(String(format: "estimated reclaimed: %.2f GB", app.sizeGB))
            }

            DispatchQueue.main.async {
                self.uninstallLog = logs
                self.installedApps.removeAll { idsToRemove.contains($0.id) }
                self.isUninstallingApps = false
                self.refresh()
            }
        }
    }

    // MARK: Cleanup Tab
    func scanCleanupDomains() {
        guard !isScanningCleanup else { return }
        isScanningCleanup = true
        cleanupDomainLog = ["Scanning CPU, Memory, Disk junk..."]

        DispatchQueue.global(qos: .userInitiated).async {
            let cpu = self.scanHighCPUProcesses()
            let mem = self.scanHighMemoryProcesses()
            let disk = self.scanDiskJunk()

            DispatchQueue.main.async {
                self.highCPUProcesses = cpu
                self.highMemoryProcesses = mem
                self.diskJunkItems = disk
                self.isScanningCleanup = false
                self.cleanupDomainLog = [
                    "CPU candidates: \(cpu.count)",
                    "Memory hogs: \(mem.count)",
                    String(format: "Disk junk found: %.2f GB", disk.reduce(0) { $0 + $1.sizeGB })
                ]
            }
        }
    }

    private func scanHighCPUProcesses() -> [ProcessItem] {
        let output = shell("ps aux | sort -k3 -rn | head -30")
        let lines = output.split(separator: "\n").dropFirst()

        var items: [ProcessItem] = []
        for line in lines {
            let raw = String(line)
            let parts = raw.split(omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 11 else { continue }

            let user = String(parts[0])
            let pid = Int(parts[1]) ?? 0
            let cpu = Double(parts[2]) ?? 0
            let memPercent = Double(parts[3]) ?? 0
            let rssKB = Double(parts[5]) ?? 0
            let command = parts[10...].joined(separator: " ")

            guard cpu >= 20 else { continue }
            guard !command.contains("CleanLocal") else { continue }
            guard !command.contains("kernel_task") else { continue }

            items.append(
                ProcessItem(
                    pid: pid,
                    user: user,
                    cpu: cpu,
                    memPercent: memPercent,
                    rssMB: rssKB / 1024,
                    command: command
                )
            )
        }

        return items
    }

    private func scanHighMemoryProcesses() -> [ProcessItem] {
        let output = shell("ps aux | sort -k4 -rn | head -30")
        let lines = output.split(separator: "\n").dropFirst()

        var items: [ProcessItem] = []
        for line in lines {
            let raw = String(line)
            let parts = raw.split(omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 11 else { continue }

            let user = String(parts[0])
            let pid = Int(parts[1]) ?? 0
            let cpu = Double(parts[2]) ?? 0
            let memPercent = Double(parts[3]) ?? 0
            let rssKB = Double(parts[5]) ?? 0
            let command = parts[10...].joined(separator: " ")

            guard memPercent >= 2 else { continue }
            guard !command.contains("CleanLocal") else { continue }

            items.append(
                ProcessItem(
                    pid: pid,
                    user: user,
                    cpu: cpu,
                    memPercent: memPercent,
                    rssMB: rssKB / 1024,
                    command: command
                )
            )
        }

        return items
    }

    private func scanDiskJunk() -> [CleanableItem] {
        var items: [CleanableItem] = []

        // Top cache folders
        let cacheOut = shell("du -sk ~/Library/Caches/* 2>/dev/null | sort -rn | head -12")
        for line in cacheOut.split(separator: "\n") {
            let s = String(line)
            let comps = s.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard comps.count == 2 else { continue }
            let kb = Double(comps[0]) ?? 0
            let path = String(comps[1])
            let sizeGB = kb / 1_048_576
            guard sizeGB > 0.05 else { continue }
            items.append(CleanableItem(domain: .disk, title: "Cache: \((path as NSString).lastPathComponent)", path: path, sizeGB: sizeGB, isChecked: true))
        }

        // Old downloads files
        let downloadsOut = shell("find ~/Downloads -maxdepth 1 -type f -mtime +7 -size +100k -print0 2>/dev/null | xargs -0 du -sk 2>/dev/null | sort -rn | head -20")
        for line in downloadsOut.split(separator: "\n") {
            let s = String(line)
            let comps = s.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard comps.count == 2 else { continue }
            let kb = Double(comps[0]) ?? 0
            let path = String(comps[1])
            let sizeGB = kb / 1_048_576
            guard sizeGB > 0.02 else { continue }
            items.append(CleanableItem(domain: .disk, title: "Old Download: \((path as NSString).lastPathComponent)", path: path, sizeGB: sizeGB, isChecked: true))
        }

        // Dev artifact dirs
        let devOut = shell("find ~ -maxdepth 5 \\( -name node_modules -o -name .next -o -name __pycache__ \\) -type d -print0 2>/dev/null | xargs -0 du -sk 2>/dev/null | sort -rn | head -20")
        for line in devOut.split(separator: "\n") {
            let s = String(line)
            let comps = s.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard comps.count == 2 else { continue }
            let kb = Double(comps[0]) ?? 0
            let path = String(comps[1])
            let sizeGB = kb / 1_048_576
            guard sizeGB > 0.1 else { continue }
            items.append(CleanableItem(domain: .disk, title: "Dev Artifact: \((path as NSString).lastPathComponent)", path: path, sizeGB: sizeGB, isChecked: false))
        }

        // Trash
        let trashKB = Double(shell("du -sk ~/.Trash 2>/dev/null | awk '{print $1}'").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if trashKB > 0 {
            items.append(CleanableItem(domain: .disk, title: "Trash", path: "~/.Trash", sizeGB: trashKB / 1_048_576, isChecked: false))
        }

        return items.sorted { $0.sizeGB > $1.sizeGB }
    }

    func toggleDiskItem(id: UUID) {
        guard let idx = diskJunkItems.firstIndex(where: { $0.id == id }) else { return }
        diskJunkItems[idx].isChecked.toggle()
    }

    func cleanSelectedDiskItems() {
        let selected = diskJunkItems.filter { $0.isChecked }
        guard !selected.isEmpty else {
            cleanupDomainLog = ["Select disk items first."]
            return
        }

        cleanupDomainLog = ["Cleaning \(selected.count) disk item(s)..."]

        DispatchQueue.global(qos: .userInitiated).async {
            var logs: [String] = []

            for item in selected {
                let basename = (item.path as NSString).lastPathComponent
                let target = "~/.Trash/cleanlocal-\(self.slug(basename))-$(date +%s)"

                if item.path == "~/.Trash" {
                    let out = self.shell("find ~/.Trash -mindepth 1 -maxdepth 1 -exec mv {} ~/.Trash/cleanlocal-trash-clean-$(date +%s)-$(basename {}) \\; 2>/dev/null")
                    logs.append(out.isEmpty ? "cleaned Trash items" : out)
                } else {
                    let out = self.shell("mv \(self.sh(item.path)) \(target) 2>&1")
                    if out.isEmpty {
                        logs.append("moved: \(item.title)")
                    } else {
                        logs.append("\(item.title): \(out)")
                    }
                }
            }

            DispatchQueue.main.async {
                self.cleanupDomainLog = logs.isEmpty ? ["Done."] : logs
                self.scanCleanupDomains()
                self.refresh()
            }
        }
    }

    func killHighCPUProcesses() {
        guard !highCPUProcesses.isEmpty else {
            cleanupDomainLog = ["No high CPU processes to kill."]
            return
        }

        let pids = highCPUProcesses.map { String($0.pid) }.joined(separator: " ")
        _ = shell("kill -9 \(pids) 2>/dev/null")
        cleanupDomainLog = ["Killed \(highCPUProcesses.count) high CPU process(es)."]
        scanCleanupDomains()
        refresh()
    }

    func purgeMemory() {
        DispatchQueue.global(qos: .userInitiated).async {
            let out = self.shell("purge 2>&1")
            DispatchQueue.main.async {
                self.cleanupDomainLog = [out.isEmpty ? "Memory purge completed." : out]
                self.refresh()
            }
        }
    }

    func checkForUpdates() {
        guard !isCheckingUpdates else { return }

        guard updateRepo.contains("/") else {
            updateStatusMessage = "Invalid update repo format. Use owner/repo."
            return
        }

        isCheckingUpdates = true
        updateAvailableVersion = nil
        updateStatusMessage = "Checking GitHub releases..."

        let current = currentVersionString()
        guard let url = URL(string: "https://api.github.com/repos/\(updateRepo)/releases/latest") else {
            isCheckingUpdates = false
            updateStatusMessage = "Invalid release URL."
            return
        }

        var request = URLRequest(url: url)
        request.setValue("CleanLocal", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer {
                DispatchQueue.main.async {
                    self.isCheckingUpdates = false
                    self.lastUpdateCheckedAt = Date()
                }
            }

            if let error {
                DispatchQueue.main.async {
                    self.latestReleaseURL = nil
                    self.updateStatusMessage = "Update check failed: \(error.localizedDescription)"
                }
                return
            }

            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self.latestReleaseURL = nil
                    self.updateStatusMessage = "Update check failed: no response"
                }
                return
            }

            guard http.statusCode == 200, let data else {
                DispatchQueue.main.async {
                    self.latestReleaseURL = nil
                    self.updateStatusMessage = "No release found (HTTP \(http.statusCode))."
                }
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latest = self.sanitizeVersion(release.tagName)
                let comparison = self.compareVersion(latest, current)

                DispatchQueue.main.async {
                    self.latestReleaseURL = release.htmlURL
                    if comparison == .orderedDescending {
                        self.updateAvailableVersion = latest
                        self.updateStatusMessage = "Update available: v\(latest)"
                    } else {
                        self.updateStatusMessage = "You’re up to date (v\(current))."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.latestReleaseURL = nil
                    self.updateStatusMessage = "Failed to parse GitHub release."
                }
            }
        }.resume()
    }

    func openLatestRelease() {
        guard let raw = latestReleaseURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func currentVersionString() -> String {
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        if let bundleVersion, !bundleVersion.isEmpty {
            return sanitizeVersion(bundleVersion)
        }
        return "0.1.0"
    }

    private func sanitizeVersion(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(of: "^[vV]\\s*", with: "", options: .regularExpression)
    }

    private func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = versionComponents(from: lhs)
        let r = versionComponents(from: rhs)
        let count = max(l.count, r.count)

        for idx in 0..<count {
            let lv = idx < l.count ? l[idx] : 0
            let rv = idx < r.count ? r[idx] : 0
            if lv > rv { return .orderedDescending }
            if lv < rv { return .orderedAscending }
        }
        return .orderedSame
    }

    private func versionComponents(from version: String) -> [Int] {
        let base = sanitizeVersion(version)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? sanitizeVersion(version)

        let parts = base.split(separator: ".", omittingEmptySubsequences: false).map { part in
            let digits = String(part.prefix { $0.isNumber })
            return Int(digits) ?? 0
        }

        return parts.isEmpty ? [0] : parts
    }

    // MARK: Helpers
    private func shell(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-lc", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseMDLSDate(_ raw: String) -> Date? {
        if raw.isEmpty || raw == "(null)" { return nil }

        let fmts = [
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss +0000",
            "yyyy-MM-dd HH:mm:ss"
        ]

        for f in fmts {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }

    private func slug(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private func sh(_ text: String) -> String {
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func escapeAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Popover View
struct PopoverView: View {
    @ObservedObject var monitor: SystemMonitor
    @AppStorage("cleanlocal.hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @State private var showOnboarding: Bool = false
    @State private var isWalkthroughRunning: Bool = false
    @State private var walkthroughMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("Tab", selection: $monitor.selectedTab) {
                ForEach(CleanLocalTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if let walkthroughMessage {
                VStack(alignment: .leading, spacing: 8) {
                    walkthroughTabChips

                    Text(walkthroughMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    switch monitor.selectedTab {
                    case .monitor:
                        monitorTab
                    case .apps:
                        appsTab
                    case .cleanup:
                        cleanupTab
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()
            footer
        }
        .frame(width: 380, height: 620)
        .onAppear {
            if !hasSeenOnboarding {
                showOnboarding = true
            }
            if monitor.updateStatusMessage.isEmpty {
                monitor.checkForUpdates()
            }
        }
        .sheet(isPresented: $showOnboarding) {
            onboardingSheet
        }
    }

    private var header: some View {
        HStack {
            Text("CleanLocal")
                .font(.system(size: 16, weight: .bold))
            Spacer()
            Button(action: { showOnboarding = true }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("What can CleanLocal do?")
            healthBadge
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var walkthroughTabChips: some View {
        HStack(spacing: 6) {
            walkthroughChip(.monitor, label: "Monitor")
            walkthroughChip(.apps, label: "Apps")
            walkthroughChip(.cleanup, label: "Cleanup")
        }
    }

    private func walkthroughChip(_ tab: CleanLocalTab, label: String) -> some View {
        let isActive = monitor.selectedTab == tab

        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.blue.opacity(0.95) : Color.gray.opacity(0.12))
            .scaleEffect(isActive && isWalkthroughRunning ? 1.06 : 1.0)
            .opacity(isActive && isWalkthroughRunning ? 1.0 : 0.92)
            .animation(.easeInOut(duration: 0.7).repeatCount(isWalkthroughRunning ? 6 : 0, autoreverses: true), value: monitor.selectedTab)
            .cornerRadius(999)
    }

    private var onboardingSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to CleanLocal")
                .font(.system(size: 18, weight: .bold))

            Text("Quick way to keep your Mac fast without hunting settings.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                onboardingRow(
                    icon: "speedometer",
                    title: "Monitor",
                    desc: "Live CPU, Memory, Disk health + one-click Quick Clean."
                )

                onboardingRow(
                    icon: "app.badge",
                    title: "Apps",
                    desc: "Find apps not used in 7/14/30/60 days and uninstall selected ones."
                )

                onboardingRow(
                    icon: "trash",
                    title: "Cleanup",
                    desc: "Scan CPU/Memory/Disk junk, then clean only what you choose."
                )
            }
            .padding(10)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(10)

            Text("Tip: Start with Monitor → Quick Clean, then use Cleanup for selective deep cleanup.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack {
                Button("Skip") {
                    hasSeenOnboarding = true
                    showOnboarding = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Start quick walkthrough") {
                    hasSeenOnboarding = true
                    showOnboarding = false
                    startWalkthrough()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private func onboardingRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func startWalkthrough() {
        guard !isWalkthroughRunning else { return }
        isWalkthroughRunning = true

        monitor.selectedTab = .monitor
        walkthroughMessage = "1/3 Monitor: quick health view + one-click Quick Clean"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            monitor.selectedTab = .apps
            walkthroughMessage = "2/3 Apps: scan unused apps and uninstall selected ones"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            monitor.selectedTab = .cleanup
            walkthroughMessage = "3/3 Cleanup: scan CPU/Memory/Disk and clean selectively"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            walkthroughMessage = nil
            isWalkthroughRunning = false
        }
    }

    private var monitorTab: some View {
        VStack(spacing: 6) {
            StatRow(icon: "cpu", label: "CPU", value: String(format: "%.1f%%", monitor.cpuUsage), color: colorForPercent(monitor.cpuUsage), bar: monitor.cpuUsage)
            StatRow(icon: "memorychip", label: "Memory", value: String(format: "%.1f / %.0f GB", monitor.memoryUsedGB, monitor.memoryTotalGB), color: colorForPercent(monitor.memoryUsage), bar: monitor.memoryUsage)
            StatRow(icon: "internaldrive", label: "Disk", value: String(format: "%.0f / %.0f GB", monitor.diskUsedGB, monitor.diskTotalGB), color: colorForPercent(monitor.diskUsage), bar: monitor.diskUsage)

            keyValueRow(label: "Network", value: monitor.networkUp ? "Connected" : "Offline", color: monitor.networkUp ? .green : .red)

            if monitor.zombieProcessCount > 0 {
                keyValueRow(label: "Zombies", value: "\(monitor.zombieProcessCount) python3.11", color: .orange)
            }

            if monitor.cleanableDiskGB > 0.1 {
                keyValueRow(label: "Cleanable", value: String(format: "%.2f GB", monitor.cleanableDiskGB), color: .cyan)
            }

            if !monitor.cleanupLog.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last quick clean: \(monitor.lastCleaned)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    ForEach(monitor.cleanupLog.prefix(8), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.green)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }

            Button(action: { monitor.cleanNow() }) {
                HStack {
                    if monitor.isCleaning {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(monitor.isCleaning ? "Quick Cleaning..." : "Quick Clean")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(monitor.isCleaning ? .gray : .blue)
            .disabled(monitor.isCleaning)
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }

    private var appsTab: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Not used in")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Picker("Days", selection: $monitor.appUnusedThresholdDays) {
                    Text("7d").tag(7)
                    Text("14d").tag(14)
                    Text("30d").tag(30)
                    Text("60d").tag(60)
                }
                .labelsHidden()
                .frame(width: 100)

                Spacer()

                Button(monitor.isScanningApps ? "Scanning..." : "Scan") {
                    monitor.scanInstalledApps()
                }
                .disabled(monitor.isScanningApps)
            }
            .padding(.horizontal, 12)

            if monitor.filteredInstalledApps.isEmpty {
                Text("No apps found for this threshold. Run Scan.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 5) {
                    ForEach(monitor.filteredInstalledApps.prefix(60)) { app in
                        Button(action: { monitor.toggleAppSelection(id: app.id) }) {
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                    .resizable()
                                    .frame(width: 16, height: 16)

                                Image(systemName: app.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(app.isSelected ? .blue : .secondary)

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack {
                                        Text(app.name)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        if app.needsSudo {
                                            Text("sudo")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.orange)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.15))
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text("\(formatGB(app.sizeGB)) • \(relativeDate(app.lastUsed))")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.gray.opacity(0.07))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }

            Button(action: { monitor.uninstallSelectedApps() }) {
                HStack {
                    if monitor.isUninstallingApps {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        Image(systemName: "trash")
                    }
                    Text(monitor.isUninstallingApps ? "Uninstalling..." : "Uninstall Selected (\(monitor.selectedAppsCount))")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(monitor.isUninstallingApps || monitor.selectedAppsCount == 0)
            .padding(.horizontal, 12)

            Text("Estimated reclaim: \(formatGB(monitor.selectedAppsEstimatedGB))")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)

            if !monitor.uninstallLog.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(monitor.uninstallLog.suffix(8), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }
    }

    private var cleanupTab: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(monitor.isScanningCleanup ? "Scanning..." : "Scan Domains") {
                    monitor.scanCleanupDomains()
                }
                .disabled(monitor.isScanningCleanup)

                Button("Kill High CPU") { monitor.killHighCPUProcesses() }
                    .disabled(monitor.highCPUProcesses.isEmpty)

                Button("Purge RAM") { monitor.purgeMemory() }
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("CPU")
                    .font(.system(size: 11, weight: .bold))
                ForEach(monitor.highCPUProcesses.prefix(5)) { p in
                    Text("PID \(p.pid) • \(String(format: "%.1f", p.cpu))% • \(shortCmd(p.command))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if monitor.highCPUProcesses.isEmpty {
                    Text("No high CPU offenders found.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)

            Divider().padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Memory")
                    .font(.system(size: 11, weight: .bold))
                ForEach(monitor.highMemoryProcesses.prefix(5)) { p in
                    Text("PID \(p.pid) • \(String(format: "%.1f", p.rssMB))MB • \(shortCmd(p.command))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if monitor.highMemoryProcesses.isEmpty {
                    Text("No heavy memory hogs found.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)

            Divider().padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Disk Junk")
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                    Text("Selected: \(formatGB(monitor.selectedDiskEstimatedGB))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                ForEach(monitor.diskJunkItems.prefix(30)) { item in
                    Button(action: { monitor.toggleDiskItem(id: item.id) }) {
                        HStack {
                            Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                                .foregroundColor(item.isChecked ? .blue : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text("\(formatGB(item.sizeGB)) • \(item.path)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }

                if monitor.diskJunkItems.isEmpty {
                    Text("No disk junk scanned yet.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Button("Clean Selected Disk Items") {
                    monitor.cleanSelectedDiskItems()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(monitor.diskJunkItems.filter { $0.isChecked }.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)

            if !monitor.cleanupDomainLog.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(monitor.cleanupDomainLog.suffix(8), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            }
        }
    }

    private func keyValueRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if !monitor.updateStatusMessage.isEmpty {
                Text(monitor.updateStatusMessage)
                    .font(.system(size: 9))
                    .foregroundColor(monitor.updateAvailableVersion == nil ? .secondary : .green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("Last checked: \(formattedLastUpdateCheck)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                Spacer()

                if let version = monitor.updateAvailableVersion {
                    Button("Update v\(version)") {
                        monitor.openLatestRelease()
                    }
                    .font(.system(size: 9, weight: .semibold))
                } else {
                    Button(monitor.isCheckingUpdates ? "Checking…" : "Check Updates") {
                        monitor.checkForUpdates()
                    }
                    .font(.system(size: 9))
                    .disabled(monitor.isCheckingUpdates)
                }

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var healthBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)
            Text("\(monitor.overallHealth)%")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(healthColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(healthColor.opacity(0.15))
        .cornerRadius(8)
    }

    private var healthColor: Color {
        switch monitor.overallHealth {
        case 80...100: return .green
        case 50..<80:  return .yellow
        default:       return .red
        }
    }

    private var formattedLastUpdateCheck: String {
        guard let date = monitor.lastUpdateCheckedAt else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func colorForPercent(_ pct: Double) -> Color {
        switch pct {
        case 0..<60:  return .green
        case 60..<80: return .yellow
        default:      return .red
        }
    }

    private func relativeDate(_ date: Date?) -> String {
        guard let date else { return "never used" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return "last used \(fmt.localizedString(for: date, relativeTo: Date()))"
    }

    private func formatGB(_ gb: Double) -> String {
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        }
        return String(format: "%.0f MB", gb * 1024)
    }

    private func shortCmd(_ cmd: String) -> String {
        if cmd.count <= 42 { return cmd }
        return String(cmd.prefix(42)) + "…"
    }
}

// MARK: - Stat Row
struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    let bar: Double

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.7))
                        .frame(width: geo.size.width * min(bar / 100, 1.0))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
