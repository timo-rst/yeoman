import Foundation
import CoreGraphics
import YeomanCore

func runFinderCutTests() {
    let harness = TestHarness.shared

    harness.runSuite("Finder Cut Tests") {
        harness.test("Event tap mask strictly monitors keyDown only") {
            assertEqual(FinderCutManager.eventMask, CGEventMask(1 << CGEventType.keyDown.rawValue))
            assertTrue(FinderCutManager.shouldTransform(.keyDown))
            assertFalse(FinderCutManager.shouldTransform(.keyUp))
            assertFalse(FinderCutManager.shouldTransform(.flagsChanged))
            assertFalse(FinderCutManager.shouldTransform(.scrollWheel))
            assertFalse(FinderCutManager.shouldTransform(.leftMouseDown))
        }

        harness.test("classifyShortcut identifies Command+X/C/V, Escape, and layout unicode fallback") {
            // Standard ANSI keyCodes + unicode
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 7, unicodeCharacter: "x", flags: .maskCommand), .cut)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 8, unicodeCharacter: "c", flags: .maskCommand), .copy)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 9, unicodeCharacter: "v", flags: .maskCommand), .paste)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 53, unicodeCharacter: nil, flags: []), .escape)

            // Non-ANSI layout (e.g. Dvorak where keyCode differs but unicode matches)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 31, unicodeCharacter: "c", flags: .maskCommand), .copy)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 45, unicodeCharacter: "x", flags: .maskCommand), .cut)

            // ANSI fallback when unicode string is nil
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 7, unicodeCharacter: nil, flags: .maskCommand), .cut)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 8, unicodeCharacter: nil, flags: .maskCommand), .copy)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 9, unicodeCharacter: nil, flags: .maskCommand), .paste)

            // Extra modifiers must not trigger
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 7, unicodeCharacter: "x", flags: [.maskCommand, .maskShift]), .other)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 9, unicodeCharacter: "v", flags: [.maskCommand, .maskAlternate]), .other)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 8, unicodeCharacter: "c", flags: [.maskCommand, .maskControl]), .other)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 53, unicodeCharacter: nil, flags: .maskCommand), .other)

            // Control characters or empty unicode strings still match via layout virtual keyCode
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 7, unicodeCharacter: "\u{18}", flags: .maskCommand), .cut)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 8, unicodeCharacter: "", flags: .maskCommand), .copy)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 9, unicodeCharacter: "\u{16}", flags: .maskCommand), .paste)
            assertEqual(FinderCutDecisionEngine.classifyShortcut(keyCode: 45, unicodeCharacter: "\u{18}", flags: .maskCommand, cutKeyCode: 45, copyKeyCode: 31, pasteKeyCode: 47), .cut)

            // Finder Edit menu item matcher (Copy = C/0, Cut = X/0, Paste = V/0, Move Item Here = V/2)
            assertTrue(FinderCutDecisionEngine.matchesFinderMenuItem(cmdChar: "C", modifiers: 0, targetChar: "C", targetModifiers: 0))
            assertTrue(FinderCutDecisionEngine.matchesFinderMenuItem(cmdChar: "c", modifiers: nil, targetChar: "C", targetModifiers: 0))
            assertTrue(FinderCutDecisionEngine.matchesFinderMenuItem(cmdChar: "V", modifiers: 2, targetChar: "V", targetModifiers: 2))
            assertFalse(FinderCutDecisionEngine.matchesFinderMenuItem(cmdChar: "C", modifiers: 2, targetChar: "C", targetModifiers: 0))
            assertFalse(FinderCutDecisionEngine.matchesFinderMenuItem(cmdChar: "V", modifiers: 3, targetChar: "V", targetModifiers: 2))
            assertFalse(FinderCutDecisionEngine.matchesFinderMenuItem(cmdChar: nil, modifiers: 0, targetChar: "V", targetModifiers: 0))
        }

        harness.test("Non-Finder apps, autorepeat, synthetic, and text fields always pass through") {
            var state = FinderCutState()
            let now = Date()

            // Non-Finder app
            assertEqual(
                FinderCutDecisionEngine.decide(
                    eventType: .keyDown,
                    isFinderFrontmost: false,
                    isAutorepeat: false,
                    isSynthetic: false,
                    shortcut: .cut,
                    isEditingTextInFinder: false,
                    cancelOnEscape: true,
                    state: &state,
                    now: now
                ),
                .passThrough
            )
            assertFalse(state.isCutPending)

            // Autorepeat in Finder
            assertEqual(
                FinderCutDecisionEngine.decide(
                    eventType: .keyDown,
                    isFinderFrontmost: true,
                    isAutorepeat: true,
                    isSynthetic: false,
                    shortcut: .cut,
                    isEditingTextInFinder: false,
                    cancelOnEscape: true,
                    state: &state,
                    now: now
                ),
                .passThrough
            )
            assertFalse(state.isCutPending)

            // Synthetic event in Finder
            assertEqual(
                FinderCutDecisionEngine.decide(
                    eventType: .keyDown,
                    isFinderFrontmost: true,
                    isAutorepeat: false,
                    isSynthetic: true,
                    shortcut: .cut,
                    isEditingTextInFinder: false,
                    cancelOnEscape: true,
                    state: &state,
                    now: now
                ),
                .passThrough
            )
            assertFalse(state.isCutPending)

            // Text input editing (file rename / search field) in Finder
            for role in ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXWebArea"] {
                assertTrue(FinderCutDecisionEngine.isTextInputElement(role: role, subrole: nil))
            }
            assertTrue(FinderCutDecisionEngine.isTextInputElement(role: "AXGroup", subrole: "AXSearchField"))
            assertFalse(FinderCutDecisionEngine.isTextInputElement(role: "AXOutline", subrole: nil))

            assertEqual(
                FinderCutDecisionEngine.decide(
                    eventType: .keyDown,
                    isFinderFrontmost: true,
                    isAutorepeat: false,
                    isSynthetic: false,
                    shortcut: .cut,
                    isEditingTextInFinder: true,
                    cancelOnEscape: true,
                    state: &state,
                    now: now
                ),
                .passThrough
            )
            assertFalse(state.isCutPending)
        }

        harness.test("Cut -> Paste transforms once to Move and clears state afterward") {
            var state = FinderCutState()
            let t0 = Date(timeIntervalSince1970: 1000)

            // 1. Cmd+X in Finder transforms to Cmd+C and marks pending
            let cutAction = FinderCutDecisionEngine.decide(
                eventType: .keyDown,
                isFinderFrontmost: true,
                isAutorepeat: false,
                isSynthetic: false,
                shortcut: .cut,
                isEditingTextInFinder: false,
                cancelOnEscape: true,
                state: &state,
                now: t0
            )
            assertEqual(cutAction, .transformCutToCopy)
            assertTrue(state.isCutPending)
            assertTrue(state.awaitingPasteboardConfirmation)

            // Confirm pasteboard update at changeCount 42
            state.awaitingPasteboardConfirmation = false
            state.confirmedChangeCount = 42
            state.cutItemCount = 2

            // 2. Cmd+V with matching changeCount transforms to Cmd+Opt+V and clears pending state
            let pasteAction = FinderCutDecisionEngine.decide(
                eventType: .keyDown,
                isFinderFrontmost: true,
                isAutorepeat: false,
                isSynthetic: false,
                shortcut: .paste,
                isEditingTextInFinder: false,
                cancelOnEscape: true,
                state: &state,
                now: t0.addingTimeInterval(2.0),
                currentChangeCount: 42
            )
            assertEqual(pasteAction, .transformPasteToMove)
            assertFalse(state.isCutPending)

            // 3. Subsequent Cmd+V passes through normally
            let secondPaste = FinderCutDecisionEngine.decide(
                eventType: .keyDown,
                isFinderFrontmost: true,
                isAutorepeat: false,
                isSynthetic: false,
                shortcut: .paste,
                isEditingTextInFinder: false,
                cancelOnEscape: true,
                state: &state,
                now: t0.addingTimeInterval(3.0),
                currentChangeCount: 42
            )
            assertEqual(secondPaste, .passThrough)
        }

        harness.test("Copy, Escape, pasteboard mismatch, and stale unconfirmed cut cancel pending state") {
            let t0 = Date(timeIntervalSince1970: 2000)

            // Cmd+C cancels pending cut
            var stateCopy = FinderCutState(isCutPending: true, awaitingPasteboardConfirmation: false, confirmedChangeCount: 10, cutStartedAt: t0, cutItemCount: 1)
            let copyAction = FinderCutDecisionEngine.decide(
                eventType: .keyDown,
                isFinderFrontmost: true,
                isAutorepeat: false,
                isSynthetic: false,
                shortcut: .copy,
                isEditingTextInFinder: false,
                cancelOnEscape: true,
                state: &stateCopy,
                now: t0
            )
            assertEqual(copyAction, .clearCutAndPassThrough)
            assertFalse(stateCopy.isCutPending)

            // Escape cancels pending cut when enabled, preserves when disabled
            var stateEsc = FinderCutState(isCutPending: true, awaitingPasteboardConfirmation: false, confirmedChangeCount: 10, cutStartedAt: t0, cutItemCount: 1)
            assertEqual(
                FinderCutDecisionEngine.decide(
                    eventType: .keyDown,
                    isFinderFrontmost: true,
                    isAutorepeat: false,
                    isSynthetic: false,
                    shortcut: .escape,
                    isEditingTextInFinder: false,
                    cancelOnEscape: false,
                    state: &stateEsc,
                    now: t0
                ),
                .passThrough
            )
            assertTrue(stateEsc.isCutPending)

            assertEqual(
                FinderCutDecisionEngine.decide(
                    eventType: .keyDown,
                    isFinderFrontmost: true,
                    isAutorepeat: false,
                    isSynthetic: false,
                    shortcut: .escape,
                    isEditingTextInFinder: false,
                    cancelOnEscape: true,
                    state: &stateEsc,
                    now: t0
                ),
                .clearCutAndPassThrough
            )
            assertFalse(stateEsc.isCutPending)

            // Pasteboard changeCount mismatch aborts move on Cmd+V
            var stateMismatch = FinderCutState(isCutPending: true, awaitingPasteboardConfirmation: false, confirmedChangeCount: 10, cutStartedAt: t0, cutItemCount: 1)
            assertEqual(
                FinderCutDecisionEngine.decide(
                    eventType: .keyDown,
                    isFinderFrontmost: true,
                    isAutorepeat: false,
                    isSynthetic: false,
                    shortcut: .paste,
                    isEditingTextInFinder: false,
                    cancelOnEscape: true,
                    state: &stateMismatch,
                    now: t0.addingTimeInterval(1.0),
                    currentChangeCount: 11
                ),
                .clearCutAndPassThrough
            )
            assertFalse(stateMismatch.isCutPending)

            // Unconfirmed cut past grace interval expires safely; within grace interval succeeds
            var stateFast = FinderCutState(isCutPending: true, awaitingPasteboardConfirmation: true, confirmedChangeCount: nil, cutStartedAt: t0, cutItemCount: 0)
            assertEqual(
                FinderCutDecisionEngine.decide(
                    eventType: .keyDown,
                    isFinderFrontmost: true,
                    isAutorepeat: false,
                    isSynthetic: false,
                    shortcut: .paste,
                    isEditingTextInFinder: false,
                    cancelOnEscape: true,
                    state: &stateFast,
                    now: t0.addingTimeInterval(0.3)
                ),
                .transformPasteToMove
            )
            assertFalse(stateFast.isCutPending)

            var stateExpired = FinderCutState(isCutPending: true, awaitingPasteboardConfirmation: true, confirmedChangeCount: nil, cutStartedAt: t0, cutItemCount: 0)
            assertEqual(
                FinderCutDecisionEngine.decide(
                    eventType: .keyDown,
                    isFinderFrontmost: true,
                    isAutorepeat: false,
                    isSynthetic: false,
                    shortcut: .paste,
                    isEditingTextInFinder: false,
                    cancelOnEscape: true,
                    state: &stateExpired,
                    now: t0.addingTimeInterval(1.5)
                ),
                .clearCutAndPassThrough
            )
            assertFalse(stateExpired.isCutPending)
        }

        harness.test("Fallback permission prompt hotkey registers only in Finder when tap is inactive") {
            let t0 = Date(timeIntervalSince1970: 3000)

            assertTrue(FinderCutDecisionEngine.shouldRegisterFallbackPromptHotKey(
                isModuleRequested: true,
                isTapRunning: false,
                isFinderFrontmost: true,
                isPromptVisible: false,
                isPromptMutedForSession: false,
                lastPromptDismissedAt: nil,
                now: t0
            ))

            assertFalse(FinderCutDecisionEngine.shouldRegisterFallbackPromptHotKey(
                isModuleRequested: true,
                isTapRunning: false,
                isFinderFrontmost: false,
                isPromptVisible: false,
                isPromptMutedForSession: false,
                lastPromptDismissedAt: nil,
                now: t0
            ))

            assertFalse(FinderCutDecisionEngine.shouldRegisterFallbackPromptHotKey(
                isModuleRequested: true,
                isTapRunning: true,
                isFinderFrontmost: true,
                isPromptVisible: false,
                isPromptMutedForSession: false,
                lastPromptDismissedAt: nil,
                now: t0
            ))

            assertFalse(FinderCutDecisionEngine.shouldRegisterFallbackPromptHotKey(
                isModuleRequested: false,
                isTapRunning: false,
                isFinderFrontmost: true,
                isPromptVisible: false,
                isPromptMutedForSession: false,
                lastPromptDismissedAt: nil,
                now: t0
            ))

            assertFalse(FinderCutDecisionEngine.shouldRegisterFallbackPromptHotKey(
                isModuleRequested: true,
                isTapRunning: false,
                isFinderFrontmost: true,
                isPromptVisible: true,
                isPromptMutedForSession: false,
                lastPromptDismissedAt: nil,
                now: t0
            ))

            assertFalse(FinderCutDecisionEngine.shouldRegisterFallbackPromptHotKey(
                isModuleRequested: true,
                isTapRunning: false,
                isFinderFrontmost: true,
                isPromptVisible: false,
                isPromptMutedForSession: true,
                lastPromptDismissedAt: nil,
                now: t0
            ))

            assertFalse(FinderCutDecisionEngine.shouldRegisterFallbackPromptHotKey(
                isModuleRequested: true,
                isTapRunning: false,
                isFinderFrontmost: true,
                isPromptVisible: false,
                isPromptMutedForSession: false,
                lastPromptDismissedAt: t0,
                now: t0.addingTimeInterval(15.0),
                cooldown: 30.0
            ))

            assertTrue(FinderCutDecisionEngine.shouldRegisterFallbackPromptHotKey(
                isModuleRequested: true,
                isTapRunning: false,
                isFinderFrontmost: true,
                isPromptVisible: false,
                isPromptMutedForSession: false,
                lastPromptDismissedAt: t0,
                now: t0.addingTimeInterval(31.0),
                cooldown: 30.0
            ))
        }

        harness.test("FinderCut item overlay converts Quartz rects and standardizes file URL keys") {
            let converted = FinderCutItemOverlayController.quartzToAppKit(
                CGRect(x: 320, y: 200, width: 480, height: 24),
                primaryScreenHeight: 1080
            )
            assertEqual(converted, CGRect(x: 320, y: 856, width: 480, height: 24))

            let multiMonitor = FinderCutItemOverlayController.quartzToAppKit(
                CGRect(x: -600, y: 150, width: 220, height: 20),
                primaryScreenHeight: 900
            )
            assertEqual(multiMonitor, CGRect(x: -600, y: 730, width: 220, height: 20))

            let relative = URL(fileURLWithPath: "/tmp/folder/../example/")
            let canonical = URL(fileURLWithPath: "/tmp/example")
            assertEqual(
                FinderCutItemOverlayController.normalizedFileURLKey(relative),
                FinderCutItemOverlayController.normalizedFileURLKey(canonical)
            )
        }

        harness.test("FinderCut item overlay clippedLocalItemRects filters visibility and enforces maxItems") {
            let clip = CGRect(x: 300, y: 200, width: 600, height: 300)

            let fullInside = CGRect(x: 310, y: 400, width: 580, height: 22)
            let mostlyVisible = CGRect(x: 310, y: 486, width: 580, height: 22) // 14pt visible
            let edgeSliver = CGRect(x: 310, y: 496, width: 580, height: 22) // 4pt visible -> smoothly kept for native panel clipping
            let onePixelEdge = CGRect(x: 310, y: 499, width: 580, height: 22) // 1pt visible -> dropped
            let outside = CGRect(x: 310, y: 600, width: 580, height: 22)

            let local = FinderCutItemOverlayController.clippedLocalItemRects(
                itemAppKitRects: [fullInside, mostlyVisible, edgeSliver, onePixelEdge, outside],
                clipAppKitRect: clip,
                maxItems: 20
            )
            assertEqual(local.count, 3)
            assertEqual(local[0], CGRect(x: 10, y: 200, width: 580, height: 22))
            assertEqual(local[1], CGRect(x: 10, y: 286, width: 580, height: 22))
            assertEqual(local[2], CGRect(x: 10, y: 296, width: 580, height: 22))

            assertTrue(FinderCutItemOverlayController.clippedLocalItemRects(
                itemAppKitRects: [fullInside],
                clipAppKitRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                maxItems: 20
            ).isEmpty)

            let many = Array(repeating: fullInside, count: 30)
            let capped = FinderCutItemOverlayController.clippedLocalItemRects(
                itemAppKitRects: many,
                clipAppKitRect: clip,
                maxItems: 5
            )
            assertEqual(capped.count, 5)
        }

        harness.test("FinderCut item overlay styledOverlayRect matches Finder inset list rows and icon bounds") {
            let wideListRow = CGRect(x: 0, y: 100, width: 689, height: 20)
            let styledWide = FinderCutItemOverlayController.styledOverlayRect(for: wideListRow, isListRow: true)
            assertEqual(styledWide.rect, CGRect(x: 10, y: 100.75, width: 669, height: 18.5))
            assertEqual(styledWide.cornerRadius, 9.25)

            let mergedTwoRows = CGRect(x: 0, y: 100, width: 689, height: 40)
            let styledMerged = FinderCutItemOverlayController.styledOverlayRect(for: mergedTwoRows, isListRow: true)
            assertEqual(styledMerged.rect, CGRect(x: 10, y: 100.75, width: 669, height: 38.5))
            assertEqual(styledMerged.cornerRadius, 10.0)

            let narrowListRow = CGRect(x: 0, y: 100, width: 40, height: 20)
            let styledNarrow = FinderCutItemOverlayController.styledOverlayRect(for: narrowListRow, isListRow: true)
            assertEqual(styledNarrow.rect, CGRect(x: 1.5, y: 100.75, width: 37, height: 18.5))
            assertEqual(styledNarrow.cornerRadius, 9.25)

            let iconCell = CGRect(x: 20, y: 20, width: 80, height: 80)
            let styledIcon = FinderCutItemOverlayController.styledOverlayRect(for: iconCell, isListRow: false)
            assertEqual(styledIcon.rect, CGRect(x: 21.5, y: 21.5, width: 77, height: 77))
            assertEqual(styledIcon.cornerRadius, 10.0)
        }

        harness.test("FinderCut item overlay mergeAdjacentItems combines contiguous rows and keeps gaps separate") {
            let adjacentRows = FinderCutItemOverlayController.mergeAdjacentItems([
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 100, width: 689, height: 20), isListRow: true),
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 120, width: 689, height: 20), isListRow: true)
            ])
            assertEqual(adjacentRows, [
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 100, width: 689, height: 40), isListRow: true)
            ])

            let gappedRows = FinderCutItemOverlayController.mergeAdjacentItems([
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 180, width: 689, height: 20), isListRow: true),
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 140, width: 689, height: 20), isListRow: true),
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 100, width: 689, height: 20), isListRow: true),
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 120, width: 689, height: 20), isListRow: true)
            ])
            assertEqual(gappedRows, [
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 100, width: 689, height: 60), isListRow: true),
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 180, width: 689, height: 20), isListRow: true)
            ])

            let mergedIcons = FinderCutItemOverlayController.mergeAdjacentItems([
                FinderCutOverlayItem(rect: CGRect(x: 10, y: 20, width: 60, height: 60), isListRow: false),
                FinderCutOverlayItem(rect: CGRect(x: 70, y: 20, width: 60, height: 60), isListRow: false),
                FinderCutOverlayItem(rect: CGRect(x: 200, y: 20, width: 60, height: 60), isListRow: false)
            ])
            assertEqual(mergedIcons, [
                FinderCutOverlayItem(rect: CGRect(x: 10, y: 20, width: 120, height: 60), isListRow: false),
                FinderCutOverlayItem(rect: CGRect(x: 200, y: 20, width: 60, height: 60), isListRow: false)
            ])
        }

        harness.test("FinderCut item overlay adaptive refresh uses 120Hz during motion and backs off when idle") {
            assertTrue(FinderCutItemOverlayController.recommendedRefreshInterval(sinceLastMotion: 0.0) <= (1.0 / 100.0))
            assertTrue(FinderCutItemOverlayController.recommendedRefreshInterval(sinceLastMotion: 0.15) <= (1.0 / 100.0))
            assertTrue(FinderCutItemOverlayController.recommendedRefreshInterval(sinceLastMotion: 0.5) >= 0.05)
            assertTrue(FinderCutItemOverlayController.recommendedRefreshInterval(sinceLastMotion: 2.0) >= 0.05)
        }

        harness.test("FinderCut item overlay projectGeometry shrinks list rows flush and keeps top-anchored items aligned") {
            let screenVisible = CGRect(x: 0, y: 25, width: 1440, height: 875)
            let axWindow = CGRect(x: 200, y: 200, width: 900, height: 500)
            let axClip = CGRect(x: 420, y: 200, width: 680, height: 420)
            let topRow = FinderCutOverlayItem(
                rect: CGRect(x: 420, y: 580, width: 680, height: 20),
                isListRow: true
            )
            let lowerRow = FinderCutOverlayItem(
                rect: CGRect(x: 420, y: 240, width: 680, height: 20),
                isListRow: true
            )

            // Shrinking width from the right (900 -> 600) clamps list rows flush with the narrower scroll view.
            let shrunkRightWindow = CGRect(x: 200, y: 200, width: 600, height: 500)
            let shrunkRight = FinderCutItemOverlayController.projectGeometry(
                axWindowAppKit: axWindow,
                axClipAppKit: axClip,
                axItems: [topRow, lowerRow],
                liveWindowAppKit: shrunkRightWindow,
                screenVisibleFrame: screenVisible
            )
            assertEqual(shrunkRight?.clipAppKitRect, CGRect(x: 420, y: 200, width: 380, height: 420))
            assertEqual(shrunkRight?.items, [
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 40, width: 380, height: 20), isListRow: true),
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 380, width: 380, height: 20), isListRow: true)
            ])

            // Shrinking upward from the bottom edge preserves topRow at screen Y=580 while cropping lowerRow below the bottom.
            let shrunkBottomWindow = CGRect(x: 200, y: 450, width: 900, height: 250)
            let shrunkBottom = FinderCutItemOverlayController.projectGeometry(
                axWindowAppKit: axWindow,
                axClipAppKit: axClip,
                axItems: [topRow, lowerRow],
                liveWindowAppKit: shrunkBottomWindow,
                screenVisibleFrame: screenVisible
            )
            assertEqual(shrunkBottom?.clipAppKitRect, CGRect(x: 420, y: 450, width: 680, height: 170))
            assertEqual(shrunkBottom?.items, [
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 130, width: 680, height: 20), isListRow: true)
            ])

            // Translating the window keeps local item coordinates identical.
            let movedWindow = CGRect(x: 250, y: 160, width: 900, height: 500)
            let moved = FinderCutItemOverlayController.projectGeometry(
                axWindowAppKit: axWindow,
                axClipAppKit: axClip,
                axItems: [topRow],
                liveWindowAppKit: movedWindow,
                screenVisibleFrame: screenVisible
            )
            assertEqual(moved?.clipAppKitRect, CGRect(x: 470, y: 160, width: 680, height: 420))
            assertEqual(moved?.items, [
                FinderCutOverlayItem(rect: CGRect(x: 0, y: 380, width: 680, height: 20), isListRow: true)
            ])
        }

        harness.test("FinderCut item overlay clipRectBelowHeader trims below sort buttons even when parent AXHeader height is zero") {
            let primaryHeight: CGFloat = 1000
            let scrollClip = FinderCutItemOverlayController.quartzToAppKit(
                CGRect(x: 526, y: 214, width: 410, height: 389),
                primaryScreenHeight: primaryHeight
            )
            let sortButtonsQuartz = [
                CGRect(x: 536, y: 214, width: 193, height: 28),
                CGRect(x: 729, y: 214, width: 97, height: 28)
            ]

            let trimmed = FinderCutItemOverlayController.clipRectBelowHeader(
                clipAppKitRect: scrollClip,
                headerRectsQuartz: sortButtonsQuartz,
                primaryScreenHeight: primaryHeight
            )
            let expected = FinderCutItemOverlayController.quartzToAppKit(
                CGRect(x: 526, y: 242, width: 410, height: 361),
                primaryScreenHeight: primaryHeight
            )
            assertEqual(trimmed, expected)
        }

        harness.test("FinderCut item overlay projectGeometry preserves horizontal overflow for rows wider than scroll area") {
            let screenVisible = CGRect(x: 0, y: 25, width: 1440, height: 875)
            let axWindow = CGRect(x: 200, y: 200, width: 630, height: 450)
            let axClip = CGRect(x: 420, y: 200, width: 410, height: 360)
            // Scrolled horizontally left by 60pt, full column row is 612pt wide (overflows 410pt viewport).
            let overflowingRow = FinderCutOverlayItem(
                rect: CGRect(x: 360, y: 500, width: 612, height: 20),
                isListRow: true
            )

            let resizedWindow = CGRect(x: 200, y: 200, width: 580, height: 450)
            let projected = FinderCutItemOverlayController.projectGeometry(
                axWindowAppKit: axWindow,
                axClipAppKit: axClip,
                axItems: [overflowingRow],
                liveWindowAppKit: resizedWindow,
                screenVisibleFrame: screenVisible
            )

            assertEqual(projected?.clipAppKitRect, CGRect(x: 420, y: 200, width: 360, height: 360))
            assertEqual(projected?.items, [
                FinderCutOverlayItem(rect: CGRect(x: -60, y: 300, width: 612, height: 20), isListRow: true)
            ])
        }
    }
}
