//
//  SequentialTextViewManager+Selection.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 06/12/2025.
//

import AppKit

// MARK: - Extension: Selection

extension SequentialTextViewManager {
    
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
    
    // MARK: - Shift + Arrow Navigation (Selection Extension)
    
    /// Ensures an anchor exists for selection operations
    func ensureSelectionAnchor(in view: SequentialTextView) {
        if anchorInfo == nil {
            let range = view.selectedRange()
            // If there's an existing selection, anchor at the opposite end from where user is extending
            // Otherwise, anchor at current cursor position
            let anchorIndex = range.length > 0 ? range.location : range.location
            anchorInfo = (view, anchorIndex)
            log("Manager: Anchor established at index \(anchorIndex)")
        }
    }
    
    /// Returns the "head" of the selection - the end that moves during shift+arrow operations
    /// This is the end opposite from the anchor
    func getSelectionHead(in view: SequentialTextView) -> Int {
        guard let anchor = anchorInfo else {
            // If no anchor use current position
            return view.selectedRange().location
        }
        
        if anchor.view != view {
            // Different view
            // Need to figure out which boundary based on view order
            sortViewsIfNeeded()
            
            guard let anchorViewIndex = textViews.firstIndex(of: anchor.view),
                  let currentViewIndex = textViews.firstIndex(of: view) else {
                // Fallback if we can't determine order
                return view.selectedRange().location
            }
            
            let range = view.selectedRange()
            
            if currentViewIndex > anchorViewIndex {
                // Current view is AFTER anchor view (forward selection)
                // Head is at the end of the selection in this view
                let head = range.location + range.length
                log(" > getSelectionHead: Cross-view forward (anchor in view \(anchorViewIndex), current view \(currentViewIndex)), head at end (\(head))")
                return head
            } else {
                // Current view is BEFORE anchor view (backward selection)
                // Head is at the start of the selection in this view
                log(" > getSelectionHead: Cross-view backward (anchor in view \(anchorViewIndex), current view \(currentViewIndex)), head at start (\(range.location))")
                return range.location
            }
        }
        
        let range = view.selectedRange()
        
        // If we have a selection, the head is whichever end isn't the anchor
        if range.length > 0 {
            let rangeStart = range.location
            let rangeEnd = range.location + range.length
            
            // Is anchor at the start or end of current selection?
            if anchor.charIndex == rangeStart {
                // Anchor is at start, head is at end
                log(" > getSelectionHead: Anchor at start (\(rangeStart)), head at end (\(rangeEnd))")
                return rangeEnd
            } else if anchor.charIndex == rangeEnd {
                // Anchor is at end, head is at start
                log(" > getSelectionHead: Anchor at end (\(rangeEnd)), head at start (\(rangeStart))")
                return rangeStart
            } else {
                // Anchor is somewhere in the middle or outside current range
                // This shouldn't normally happen, but handle it gracefully
                // Assume the head is the end farther from the anchor
                let distToStart = abs(anchor.charIndex - rangeStart)
                let distToEnd = abs(anchor.charIndex - rangeEnd)
                let head = distToEnd > distToStart ? rangeEnd : rangeStart
                log(" > getSelectionHead: Anchor at \(anchor.charIndex) (middle), head at \(head)")
                return head
            }
        } else {
            // Zero-length selection - head equals anchor
            return range.location
        }
    }
    
    /// Extends selection within a single view from anchor to target index
    func extendSelection(in view: SequentialTextView, to targetIndex: Int) {
        guard let anchor = anchorInfo else {
            log("Manager: No anchor for selection extension")
            return
        }
        
        // If anchor is in a different view, use cross-view logic
        if anchor.view != view {
            updateSelectionChain(from: anchor.view, anchorIndex: anchor.charIndex,
                                 to: view, currentIndex: targetIndex)
        } else {
            // Same view: simple range calculation
            let start = min(anchor.charIndex, targetIndex)
            let length = abs(targetIndex - anchor.charIndex)
            view.setSelectedRange(NSRange(location: start, length: length))
            log("Manager: Extended selection in view to [\(start), \(length)]")
        }
    }
    
    /// Handles Shift+Arrow boundary crossing (extends selection to adjacent view)
    func handleShiftBoundaryNavigation(from view: SequentialTextView, direction: SequentialNavigationDirection) {
        sortViewsIfNeeded()
        
        guard let currentIndex = textViews.firstIndex(of: view) else { return }
        
        log("Manager: Shift+Boundary Navigation from view \(currentIndex), direction \(direction)")
        
        // Make sure anchor exists
        ensureSelectionAnchor(in: view)
        
        guard let anchor = anchorInfo else { return }
        
        // Get the selection head (the moving end)
        let selectionHead = getSelectionHead(in: view)
        log(" > Selection head at index \(selectionHead)")
        
        // Find target view
        var targetView: SequentialTextView?
        var targetIndex: Int = 0
        
        switch direction {
        case .up:
            if currentIndex > 0 {
                targetView = textViews[currentIndex - 1]
                // Store X if needed
                if !caretManager.hasStoredPosition {
                    caretManager.storeCurrentXPositionAt(index: selectionHead, in: view)
                }
                targetIndex = caretManager.calculateCaretPosition(in: targetView!, preferEnd: true)
            } else {
                // At global top: extend to start of current view
                targetIndex = 0
                targetView = view
            }
            
        case .down:
            if currentIndex < textViews.count - 1 {
                targetView = textViews[currentIndex + 1]
                // Store X if needed
                if !caretManager.hasStoredPosition {
                    caretManager.storeCurrentXPositionAt(index: selectionHead, in: view)
                }
                targetIndex = caretManager.calculateCaretPosition(in: targetView!, preferEnd: false)
            } else {
                // At global bottom: extend to end of current view
                targetIndex = view.string.count
                targetView = view
            }
            
        case .left:
            if currentIndex > 0 {
                targetView = textViews[currentIndex - 1]
                targetIndex = targetView!.string.count
            } else {
                // At global left: extend to start
                targetIndex = 0
                targetView = view
            }
            caretManager.reset()
            
        case .right:
            if currentIndex < textViews.count - 1 {
                targetView = textViews[currentIndex + 1]
                targetIndex = 0
            } else {
                // At global right: extend to end
                targetIndex = view.string.count
                targetView = view
            }
            caretManager.reset()
        }
        
        guard let target = targetView else { return }
        
        // Focus the target view
        target.window?.makeFirstResponder(target)
        
        // Update selection chain
        updateSelectionChain(from: anchor.view, anchorIndex: anchor.charIndex,
                             to: target, currentIndex: targetIndex)
    }
    
    // MARK: - Shift + Option + Arrow (Word Selection Extension)

    func handleShiftWordLeftBoundary(from view: SequentialTextView) {
        sortViewsIfNeeded()
        
        guard let currentIndex = textViews.firstIndex(of: view) else { return }
        
        log("Manager: Shift+Option+Left boundary from view \(currentIndex)")
        
        ensureSelectionAnchor(in: view)
        guard let anchor = anchorInfo else { return }
        
        // Move to previous view's end
        if currentIndex > 0 {
            let targetView = textViews[currentIndex - 1]
            targetView.window?.makeFirstResponder(targetView)
            
            let targetIndex = targetView.string.count
            updateSelectionChain(from: anchor.view, anchorIndex: anchor.charIndex,
                                 to: targetView, currentIndex: targetIndex)
        } else {
            // At global start: extend to start of current view
            updateSelectionChain(from: anchor.view, anchorIndex: anchor.charIndex,
                                 to: view, currentIndex: 0)
        }
        
        caretManager.reset()
    }

    func handleShiftWordRightBoundary(from view: SequentialTextView) {
        sortViewsIfNeeded()
        
        guard let currentIndex = textViews.firstIndex(of: view) else { return }
        
        log("Manager: Shift+Option+Right boundary from view \(currentIndex)")
        
        ensureSelectionAnchor(in: view)
        guard let anchor = anchorInfo else { return }
        
        // Move to next view's start
        if currentIndex < textViews.count - 1 {
            let targetView = textViews[currentIndex + 1]
            targetView.window?.makeFirstResponder(targetView)
            
            updateSelectionChain(from: anchor.view, anchorIndex: anchor.charIndex,
                                 to: targetView, currentIndex: 0)
        } else {
            // At global end: extend to end of current view
            updateSelectionChain(from: anchor.view, anchorIndex: anchor.charIndex,
                                 to: view, currentIndex: view.string.count)
        }
        
        caretManager.reset()
    }
    
    // MARK: - Cmd+Shift+Arrow (Global Selection Extension)
    
    /// Handles Cmd+Shift+Up (select from current position to start of document)
    func handleGlobalShiftStart(from view: SequentialTextView) {
        sortViewsIfNeeded()
        
        log("Manager: Global Shift Start")
        
        // Establish anchor at current position
        ensureSelectionAnchor(in: view)
        
        guard let anchor = anchorInfo,
              let firstView = textViews.first else { return }
        
        // Focus first view
        firstView.window?.makeFirstResponder(firstView)
        
        // Select from anchor to start of first view
        updateSelectionChain(from: anchor.view, anchorIndex: anchor.charIndex,
                             to: firstView, currentIndex: 0)
        
        caretManager.reset()
    }
    
    /// Handles Cmd+Shift+Down (select from current position to end of document)
    func handleGlobalShiftEnd(from view: SequentialTextView) {
        sortViewsIfNeeded()
        
        log("Manager: Global Shift End")
        
        // Establish anchor at current position
        ensureSelectionAnchor(in: view)
        
        guard let anchor = anchorInfo,
              let lastView = textViews.last else { return }
        
        // Focus last view
        lastView.window?.makeFirstResponder(lastView)
        
        // Select from anchor to end of last view
        updateSelectionChain(from: anchor.view, anchorIndex: anchor.charIndex,
                             to: lastView, currentIndex: lastView.string.count)
        
        caretManager.reset()
    }
    
    // MARK: - Deletion & Editing
    
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
    
    // MARK: - Helper: (Chain, Collapse, HitTest)
    
    func updateSelectionChain(from startView: SequentialTextView, anchorIndex: Int,
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
            view.forceInactiveSelectionDisplay = true
            
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
    
    enum SelectionBoundary {
        case start // Top/Left (Up/Left arrow)
        case end   // Bottom/Right (Down/Right arrow)
    }
    
    // MARK: - Multi-View Selection Helpers
    
    /// Checks if more than one view has a selection, or if a single view has a selection
    /// but we need to treat it globally.
    var hasMultiViewSelection: Bool {
        return textViews.filter { $0.selectedRange().length > 0 }.count > 1
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
    
    /// Select All (Cmd+A) support
    func selectAllViews() {
        log("selectAll: Selecting all text across views")
        for view in textViews {
            view.forceInactiveSelectionDisplay = true
            view.setSelectedRange(NSRange(location: 0, length: view.string.count))
            view.needsDisplay = true
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
}
