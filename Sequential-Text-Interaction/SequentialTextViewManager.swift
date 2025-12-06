//
//  SequentialTextViewManager.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 02/12/2025.
//

import AppKit
import SwiftUI
import Combine

enum SequentialNavigationDirection {
    case up
    case down
    case left
    case right
}

@Observable
class SequentialTextViewManager {
    // MARK: - Properties
    
    // We keep weak references to avoiding retain cycles, but we need a robust way to sort them.
    // For this implementation, we assume the ViewRepresentable lifecycle manages registration/deregistration.
    var textViews: [SequentialTextView] = []
    
    // The logic helper for maintaining X-position during vertical movement
    let caretManager = CaretPositionManager()
    
    // Selection State
    private var isDragging = false
    private var anchorInfo: (view: SequentialTextView, charIndex: Int)?
    private var needsSorting = false
    
    // Timestamp to prevent SwiftUI gestures from clearing selection immediately after creation
    private var lastInteractionTime: TimeInterval = 0
    
    var isCurrentlyDragging: Bool { isDragging }
    
    // MARK: - Registration
    
    func register(_ textView: SequentialTextView) {
        if !textViews.contains(textView) {
            textViews.append(textView)
            textView.selectionManager = self
            needsSorting = true
            log("Manager: Registered TextView. Total: \(textViews.count)")
        }
    }
    
    func unregister(_ textView: SequentialTextView) {
        textViews.removeAll { $0 == textView }
    }
    
    /// Sorts views based on their window Y-coordinates to determine "Next" and "Previous"
    private func sortViewsIfNeeded() {
        guard needsSorting else { return }
        
        // Top-most views have higher Y values in standard window coordinates.
        // If the view is flipped (like our scrollview content often is), we might need to check geometry.
        // Assuming standard sorting logic from previous file:
        textViews.sort { v1, v2 in
            let y1 = v1.convert(v1.bounds.origin, to: nil).y
            let y2 = v2.convert(v2.bounds.origin, to: nil).y
            return y1 > y2 // Higher Y = Higher on screen
        }
        
        needsSorting = false
        log("Manager: Sorted views")
    }
    
    // MARK: - Global Navigation
    
    /// Moves caret to the start of the very first text view (Cmd + Up)
    func handleGlobalStart() {
        sortViewsIfNeeded()
        
        guard let firstView = textViews.first else { return }
        
        log("Manager: Handling Global Start")
        
        // 1. Clear existing selections
        clearAllSelections(except: nil)
        
        // 2. Focus the first view
        firstView.window?.makeFirstResponder(firstView)
        
        // 3. Move caret to index 0
        firstView.setSelectedRange(NSRange(location: 0, length: 0))
        firstView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        
        // 4. Reset vertical memory
        caretManager.reset()
    }
    
    /// Moves caret to the end of the very last text view (Cmd + Down)
    func handleGlobalEnd() {
        sortViewsIfNeeded()
        
        guard let lastView = textViews.last else { return }
        
        log("Manager: Handling Global End")
        
        // 1. Clear existing selections
        clearAllSelections(except: nil)
        
        // 2. Focus the last view
        lastView.window?.makeFirstResponder(lastView)
        
        // 3. Move caret to end
        let end = lastView.string.count
        lastView.setSelectedRange(NSRange(location: end, length: 0))
        lastView.scrollRangeToVisible(NSRange(location: end, length: 0))
        
        // 4. Reset vertical memory
        caretManager.reset()
    }
    
    // MARK: - Character Navigation (Arrow Keys)
    
    /// Called by a view when the caret hits a boundary (Top of view + Up Arrow, or Bottom + Down Arrow)
    func handleBoundaryNavigation(from view: SequentialTextView, direction: SequentialNavigationDirection) {
        sortViewsIfNeeded()
        
        guard let currentIndex = textViews.firstIndex(of: view) else {
            log("handleBoundaryNavigation: Current view not found in registry")
            return
        }
        
        log(" [Manager] Boundary Navigation: Direction \(direction) from View \(currentIndex)")
        
        // 1. Identify the Target View
        var targetView: SequentialTextView?
        
        switch direction {
        case .up:
            if currentIndex > 0 {
                targetView = textViews[currentIndex - 1]
            } else {
                log(" [Manager] Global Top Hit. Resetting Manager.")
                // BOUNDARY HIT: Top of the first view
                // Move caret to absolute start (Index 0)
                view.setSelectedRange(NSRange(location: 0, length: 0))
                view.scrollRangeToVisible(NSRange(location: 0, length: 0))
                caretManager.reset() // Clear vertical X memory
                return
            }
            
        case .down:
            if currentIndex < textViews.count - 1 {
                targetView = textViews[currentIndex + 1]
            } else {
                log(" [Manager] Global Bottom Hit. Resetting Manager.")
                // BOUNDARY HIT: Bottom of the last view
                // Move caret to absolute end
                let end = view.string.count
                view.setSelectedRange(NSRange(location: end, length: 0))
                view.scrollRangeToVisible(NSRange(location: end, length: 0))
                caretManager.reset() // Clear vertical X memory
                return
            }
            
        case .left:
            if currentIndex > 0 { targetView = textViews[currentIndex - 1] }
            
        case .right:
            if currentIndex < textViews.count - 1 { targetView = textViews[currentIndex + 1] }
        }
        
        guard let target = targetView else {
            log("handleBoundaryNavigation: No target view found in direction \(direction)")
            return
        }
        
        log("handleBoundaryNavigation: Moving from view \(currentIndex) to view \(textViews.firstIndex(of: target) ?? -1)")
        
        // Store X position if needed (only for Up/Down)
        if (direction == .up || direction == .down) {
            if !caretManager.hasStoredPosition {
                log(" [Manager] No X stored. Asking view to store current X now.")
                caretManager.storeCurrentXPosition(from: view)
            } else {
                log(" [Manager] X already stored (\(caretManager.currentXDescription)). Reusing it.")
            }
        } else {
            // Horizontal moves kill vertical memory
            caretManager.reset()
        }
        
        // 2. Focus the Target
        target.window?.makeFirstResponder(target)
        
        // Determine New Insertion Index
        let newIndex: Int
        switch direction {
        case .up:
            log("Moving up")
            newIndex = caretManager.calculateCaretPosition(in: target, preferEnd: true)
        case .down:
            log("Moving down")
            newIndex = caretManager.calculateCaretPosition(in: target, preferEnd: false)
        case .left:
            log("Moving left")
            newIndex = target.string.count
        case .right:
            log("Moving right")
            // Right Arrow: Jump to the very START of the next block
            newIndex = 0
        }
        
        // 3. Place Caret
        target.setSelectedRange(NSRange(location: newIndex, length: 0))
        target.scrollRangeToVisible(NSRange(location: newIndex, length: 0))
    }
    
    // MARK: - Word Navigation
    
    /// Handles Option + Left Arrow crossing into the previous view.
    /// Standard behavior dictates this should select the *start* of the last word in the previous view.
    func handleWordLeftBoundary(from view: SequentialTextView) {
        sortViewsIfNeeded()
        
        // 1. Check if there is a previous view (Index > 0)
        guard let currentIndex = textViews.firstIndex(of: view),
              currentIndex > 0 else {
                  log("No previous view to navigate to.")
            return
        }
        
        // 2. Identify Next View
        let target = textViews[currentIndex - 1]
        
        // 3. Focus the Target
        target.window?.makeFirstResponder(target)
        
        // 4. Perform the Word Move
        // Placing the caret at the end of the text.
        // Then trigger `moveWordLeft`.
        // This calculates the jump to the start of the last word
        let end = target.string.count
        target.setSelectedRange(NSRange(location: end, length: 0))
        target.moveWordLeft(nil)
        
        // 5. Reset vertical memory
        caretManager.reset()
    }
    
    /// Handles Option + Right Arrow crossing into the next view.
    /// Standard behavior dictates this should select the *end* of the first word in the next view.
    func handleWordRightBoundary(from view: SequentialTextView) {
        sortViewsIfNeeded()
        
        // 1. Check if there is a next view
        guard let currentIndex = textViews.firstIndex(of: view),
              currentIndex < textViews.count - 1 else {
            log("No next view to navigate to.")
            return
        }
        
        // 2. Identify Next View
        let target = textViews[currentIndex + 1]
        
        // 3. Focus the Target
        target.window?.makeFirstResponder(target)
        
        // 4. Perform the Word Move
        // Placing the caret at the start (0) and then programmatically trigger a word-right move.
        // This leverages Cocoa's native logic to skip whitespace and find the word ending.
        target.setSelectedRange(NSRange(location: 0, length: 0))
        target.moveWordRight(nil)
        
        // 5. Reset vertical memory
        caretManager.reset()
    }
    
    // MARK: - Mouse Selection (Dragging)
    
    func handleMouseDown(_ event: NSEvent, in view: SequentialTextView) {
        log("handleMouseDown: Processing mouse down in view")
        updateInteractionTime()
        sortViewsIfNeeded()
        
        // 1. Clear existing selection in all other views
        clearAllSelections(except: view)
        
        
        // 2. Record the anchor point
        let point = view.convert(event.locationInWindow, from: nil)
        let index = view.characterIndexForInsertion(at: point)
        anchorInfo = (view, index)
        isDragging = true
        log("handleMouseDown: Anchor set at index \(index)")
        
        // 3. Reset Caret Manager (Mouse click breaks the "vertical memory")
        caretManager.reset()
        log("handleMouseDown: Caret manager reset")
    }
    
    func handleMouseDragged(_ event: NSEvent) {
        guard isDragging, let anchor = anchorInfo else { return }
        
        let locationInWindow = event.locationInWindow
        // log("handleMouseDragged: Location: \(locationInWindow)")
        
        // 1. Find which view is currently under the mouse (or closest to it)
        guard let (targetView, isInGap) = findTargetView(at: locationInWindow) else {
            // log("handleMouseDragged: No target view found")
            return
        }
        
        // 2. Determine index within that view
        let currentIndex: Int
        if isInGap {
            // If in the gap, snap to top (0) or bottom (count) depending on relative Y
            let pointInTarget = targetView.convert(locationInWindow, from: nil)
            currentIndex = pointInTarget.y < 0 ? 0 : targetView.string.count
            // log("handleMouseDragged: In gap, snapped to index \(currentIndex)")
        } else {
            let pointInTarget = targetView.convert(locationInWindow, from: nil)
            currentIndex = targetView.characterIndexForInsertion(at: pointInTarget)
        }
        
        // 3. Update selection across the chain of views
        updateSelectionChain(from: anchor.view, anchorIndex: anchor.charIndex,
                             to: targetView, currentIndex: currentIndex) //
    }
    
    func handleMouseUp(_ event: NSEvent) {
        log("handleMouseUp: Dragging ended")
        updateInteractionTime()
        isDragging = false
    }
    
    func handleShiftClick(_ event: NSEvent, in clickedView: SequentialTextView) {
        log("handleShiftClick")
        updateInteractionTime()
        sortViewsIfNeeded()
        
        // Use existing anchor if available, otherwise reconstruct or default to click
        // (Simplified logic from Source B for brevity, but retains core functionality)
        guard let anchor = anchorInfo else {
            // Fallback: Start a new selection if no anchor exists
            handleMouseDown(event, in: clickedView)
            return
        }
        
        let point = clickedView.convert(event.locationInWindow, from: nil)
        let clickIndex = clickedView.characterIndexForInsertion(at: point)
        
        log("handleShiftClick: Extending selection to index \(clickIndex)")
        
        updateSelectionChain(from: anchor.view, anchorIndex: anchor.charIndex,
                             to: clickedView, currentIndex: clickIndex)
    }
    
    // MARK: - Deletion
    
    func handleMultiViewDelete() {
        sortViewsIfNeeded()
        
        // 1. Identify participating views
        // We filter for views that actually have text selected.
        let participatingViews = textViews.filter { $0.selectedRange().length > 0 }
        
        guard let firstView = participatingViews.first,
              let lastView = participatingViews.last else {
            return
        }
        
        log("Manager: Handling Delete across \(participatingViews.count) views")
        
        // 2. Capture Content to Preserve
        //   - Prefix: Everything in the first view BEFORE the selection
        //   - Suffix: Everything in the last view AFTER the selection
        let startRange = firstView.selectedRange()
        let endRange = lastView.selectedRange()
        
        let prefixRange = NSRange(location: 0, length: startRange.location)
        let prefix = (firstView.string as NSString).substring(with: prefixRange)
        
        let suffixLocation = endRange.location + endRange.length
        let suffixLength = lastView.string.count - suffixLocation
        let suffix = (lastView.string as NSString).substring(with: NSRange(location: suffixLocation, length: suffixLength))
        
        // 3. Execute Merge
        //   The first view absorbs the suffix of the last view.
        //   All other participating views (including the last one) are cleared.
        
        // A. Update First View (The Survivor)
        let mergedContent = prefix + suffix
        if let storage = firstView.textStorage {
            // Using replaceCharacters to maintain some semblance of text system integrity
            storage.replaceCharacters(in: NSRange(location: 0, length: firstView.string.count),
                                      with: mergedContent)
        } else {
            firstView.string = mergedContent
        }
        
        // B. Clear Other Views
        for view in participatingViews where view != firstView {
            if let storage = view.textStorage {
                storage.replaceCharacters(in: NSRange(location: 0, length: view.string.count),
                                          with: "")
            } else {
                view.string = ""
            }
            // Reset selection for the cleared views
            view.setSelectedRange(NSRange(location: 0, length: 0))
        }
        
        // 4. Restore Selection/Focus
        // Focus the first view
        firstView.window?.makeFirstResponder(firstView)
        
        // Place caret exactly where the deletion happened (at the end of the prefix)
        let newCaretIndex = prefix.count
        firstView.setSelectedRange(NSRange(location: newCaretIndex, length: 0))
        firstView.scrollRangeToVisible(NSRange(location: newCaretIndex, length: 0))
        
        // 5. Cleanup
        // Ensure other views know they are no longer selected
        clearAllSelections(except: firstView)
        
        // Trigger generic change handlers (important for resizing intrinsic content size)
        firstView.didChangeText()
        participatingViews.forEach { if $0 != firstView { $0.didChangeText() } }
    }
    
    // MARK: - Helper: Chain Selection Logic
    
    private func updateSelectionChain(from startView: SequentialTextView, anchorIndex: Int,
                                      to endView: SequentialTextView, currentIndex: Int) {
        guard let startIndex = textViews.firstIndex(of: startView),
              let endIndex = textViews.firstIndex(of: endView) else {
            log("updateSelectionChain: Could not find indices for start or end view")
            return
        }
        
        let isForward = startIndex < endIndex || (startIndex == endIndex && anchorIndex <= currentIndex)
         log("updateSelectionChain: From View \(startIndex) to \(endIndex) (Forward: \(isForward))")
        
        for (i, view) in textViews.enumerated() {
            // Enable forced display so views look selected even when not focused
            view.forceInactiveSelectionDisplay = true //
            
            // 1. The Anchor View
            if i == startIndex {
                if startView == endView {
                    // Single view selection
                    let range = NSRange(location: min(anchorIndex, currentIndex), length: abs(currentIndex - anchorIndex))
                    view.setSelectedRange(range)
                } else {
                    // Selection leaves this view
                    let len = view.string.count
                    if isForward {
                        // Anchor -> End
                        view.setSelectedRange(NSRange(location: anchorIndex, length: len - anchorIndex))
                    } else {
                        // Start -> Anchor
                        view.setSelectedRange(NSRange(location: 0, length: anchorIndex))
                    }
                }
                continue
            }
            
            // 2. The Target View
            if i == endIndex {
                if isForward {
                    // Start -> Mouse
                    view.setSelectedRange(NSRange(location: 0, length: currentIndex))
                } else {
                    // Mouse -> End
                    let len = view.string.count
                    view.setSelectedRange(NSRange(location: currentIndex, length: len - currentIndex))
                }
                continue
            }
            
            // 3. Middle Views (Select All)
            if isForward {
                if i > startIndex && i < endIndex {
                    view.setSelectedRange(NSRange(location: 0, length: view.string.count))
                } else {
                    view.setSelectedRange(NSRange(location: 0, length: 0))
                }
            } else {
                if i > endIndex && i < startIndex {
                    view.setSelectedRange(NSRange(location: 0, length: view.string.count))
                } else {
                    view.setSelectedRange(NSRange(location: 0, length: 0))
                }
            }
            
            view.needsDisplay = true
        }
    }
    
    // MARK: - Multi-View Selection Helpers
    
    /// Checks if more than one view has a selection, or if a single view has a selection
    /// but we need to treat it globally.
    var hasMultiViewSelection: Bool {
        return textViews.filter { $0.selectedRange().length > 0 }.count > 1
    }
    
    enum SelectionBoundary {
        case start // Top/Left (Up/Left arrow)
        case end   // Bottom/Right (Down/Right arrow)
    }
    
    /// Finds the view and character index corresponding to the start or end of the entire selection chain.
    func collapseSelection(to boundary: SelectionBoundary) -> (SequentialTextView, Int)? {
        sortViewsIfNeeded()
        
        // Find all views that actually have a selection
        let participatingViews = textViews.filter { $0.selectedRange().length > 0 }
        guard !participatingViews.isEmpty else { return nil }
        
        switch boundary {
        case .start:
            // The "Start" is the location in the very first view
            guard let firstView = participatingViews.first else { return nil }
            return (firstView, firstView.selectedRange().location)
            
        case .end:
            // The "End" is the max range in the very last view
            guard let lastView = participatingViews.last else { return nil }
            return (lastView, lastView.selectedRange().upperBound)
        }
    }
    
    // MARK: - Helper: Hit Testing
    
    /// Finds which view the mouse is over, or the closest one if in a gap
    private func findTargetView(at windowPoint: NSPoint) -> (view: SequentialTextView, isInGap: Bool)? {
        // Direct Hit
        for view in textViews {
            let localPoint = view.convert(windowPoint, from: nil)
            if view.bounds.contains(localPoint) {
                return (view, false)
            }
        }
        
        // Gap Hit: Find closest view vertically
        let closest = textViews.min(by: { v1, v2 in
            let p1 = v1.convert(NSPoint.zero, to: nil)
            let p2 = v2.convert(NSPoint.zero, to: nil)
            return abs(p1.y - windowPoint.y) < abs(p2.y - windowPoint.y)
        })
        
        if let found = closest {
            // log("findTargetView: Closest view found via gap check")
            return (found, true)
        }
        
        log("findTargetView: No view found")
        return nil
    }
    
    // MARK: - Utilities
    
    private func updateInteractionTime() {
        lastInteractionTime = Date().timeIntervalSinceReferenceDate
    }
    
    func clearAllSelections(except keptView: SequentialTextView?) {
        // PROTECTION: If this is an external clear request (keptView == nil)
        // AND we are either actively dragging OR the user interacted very recently,
        // ignore the request. This filters out the conflicting SwiftUI Tap Gesture.
        if keptView == nil {
            let timeSinceInteraction = Date().timeIntervalSinceReferenceDate - lastInteractionTime
            if isDragging || timeSinceInteraction < 0.3 {
                log("clearAllSelections: Ignored conflict with SwiftUI gesture (Time delta: \(String(format: "%.3f", timeSinceInteraction))s)")
                return
            }
        }
        
        log("clearAllSelections: Clearing selection (except keptView)")
        for view in textViews where view != keptView {
            view.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }
    
    /// Returns combined string for Copy operations
    func getSelectedText() -> String? {
        log("getSelectedText: Compiling selected text")
        var result = ""
        var hasSelection = false
        var isFirst = true
        
        // Iterate in visual order
        sortViewsIfNeeded()
        
        for view in textViews {
            let range = view.selectedRange()
            if range.length > 0 {
                hasSelection = true
                if !isFirst { result += "\n\n" }
                isFirst = false
                let substring = (view.string as NSString).substring(with: range)
                result += substring
            }
        }
        log("getSelectedText: Found selection? \(hasSelection)")
        return hasSelection ? result : nil
    }
    
    /// Select All (Cmd+A) support
    func selectAllViews() {
        log("selectAll: Selecting all text across views")
        for view in textViews {
            view.forceInactiveSelectionDisplay = true
            view.setSelectedRange(NSRange(location: 0, length: view.string.count))
            view.needsDisplay = true
        }
    }
}
