import Testing
@testable import SkwishMyMac

@Test func quick_clean_phase_order_is_linear() {
    #expect(QuickCleanPolicy.phaseOrder == [.publicSafe, .leftovers, .developer, .riskyReview])
}

@Test func risky_phase_is_never_auto_executed() {
    let risky = QuickCleanItem(
        phase: .riskyReview,
        title: "Kill process",
        pathOrCommand: "kill -9 123",
        estimatedGB: 0,
        risk: .reviewOnly,
        reason: "dangerous",
        executeType: .suggestionOnly
    )

    #expect(QuickCleanPolicy.shouldAutoExecute(risky) == false)
}

@Test func hermes_paths_are_forbidden_in_public_quick_clean() {
    #expect(QuickCleanPolicy.isForbiddenQuickCleanPath("~/.hermes/sessions"))
    #expect(QuickCleanPolicy.isForbiddenQuickCleanPath("/Users/x/.hermes/logs"))
    #expect(QuickCleanPolicy.isForbiddenQuickCleanPath("~/Library/Caches") == false)
}

@Test func developer_phase_requires_signals() {
    #expect(QuickCleanPolicy.isDeveloperPhaseEnabled(devSignals: []) == false)
    #expect(QuickCleanPolicy.isDeveloperPhaseEnabled(devSignals: ["npm"]))
}

@Test func prerelease_version_is_sanitized_for_comparison() {
    #expect(UpdatePolicy.sanitizeVersion("v1.2.3-beta.1") == "1.2.3")
}

@Test func newer_release_creates_optional_update_banner_state() {
    let state = UpdatePolicy.evaluate(current: "0.1.0", latest: "0.2.0", dismissedVersion: nil)

    switch state {
    case .updateAvailable(let current, let latest):
        #expect(current == "0.1.0")
        #expect(latest == "0.2.0")
    default:
        Issue.record("Expected updateAvailable state")
    }

    #expect(UpdatePolicy.shouldShowBanner(for: state, dismissedVersion: nil))
}

@Test func dismissed_version_hides_banner_for_same_release_only() {
    let sameVersionState = UpdatePolicy.evaluate(current: "0.1.0", latest: "0.2.0", dismissedVersion: "0.2.0")
    #expect(UpdatePolicy.shouldShowBanner(for: sameVersionState, dismissedVersion: "0.2.0") == false)

    let newerVersionState = UpdatePolicy.evaluate(current: "0.1.0", latest: "0.2.1", dismissedVersion: "0.2.0")
    #expect(UpdatePolicy.shouldShowBanner(for: newerVersionState, dismissedVersion: "0.2.0"))
}

@Test func menu_bar_only_defaults_to_true_when_bundle_flag_missing() {
    #expect(AppLaunchPolicy.shouldRunMenuBarOnly(infoDictionary: nil, environment: [:]))
}

@Test func menu_bar_only_follows_lsui_element_bundle_flag() {
    #expect(AppLaunchPolicy.shouldRunMenuBarOnly(infoDictionary: ["LSUIElement": true], environment: [:]))
    #expect(AppLaunchPolicy.shouldRunMenuBarOnly(infoDictionary: ["LSUIElement": false], environment: [:]) == false)
}

@Test func dock_override_environment_disables_menu_bar_only_mode() {
    #expect(
        AppLaunchPolicy.shouldRunMenuBarOnly(
            infoDictionary: ["LSUIElement": true],
            environment: ["SKWISH_SHOW_DOCK": "1"]
        ) == false
    )
}
