import Testing
@testable import CleanLocal

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
