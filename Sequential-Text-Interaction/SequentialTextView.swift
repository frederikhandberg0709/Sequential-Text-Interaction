//
//  SequentialTextView.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 02/12/2025.
//

import AppKit
import Observation

class SequentialTextView: NSTextView {
    
    // MARK: - Dependencies
    weak var selectionManager: SequentialTextViewManager?
    
    // From SelectableTextView: Allows us to show "blue" selection even when this specific view isn't focused
    var forceInactiveSelectionDisplay: Bool = false
    
    // MARK: - Lifecycle
    
    override var acceptsFirstResponder: Bool { true }
    
    // Ensure the view takes up only as much vertical space as its text requires
    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height))
    }
    
    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
        // Reset X position memory when user types
        log("SequentialTextView: Text changed. Resetting caret manager X position.")
        selectionManager?.caretManager.reset()
    }
    
    // MARK: - Helper: Selection Clearing
    
    /// Checks if the Shift key is pressed. If NOT, it tells the manager to clear selection in other blocks.
    private func clearExternalSelectionIfNecessary() {
        // We look at the current event modifiers.
        // If Shift is NOT held down, it means we are moving the caret without extending selection.
        // Therefore, we should clear any selection existing in neighbor blocks.
        let flags = NSApp.currentEvent?.modifierFlags ?? .init()
        if !flags.contains(.shift) {
            log("SequentialTextView: Arrow key without shift. Clearing external selections.")
            selectionManager?.clearAllSelections(except: self)
        }
    }
    
    // MARK: - Helper: Handle Multi-View Collapse
    
    /// Returns TRUE if we handled a multi-view collapse, meaning the caller should return immediately.
    private func handleMultiViewCollapse(direction: SequentialTextViewManager.SelectionBoundary, performMove: Bool) -> Bool {
        guard let manager = selectionManager,
              let currentEvent = NSApp.currentEvent,
              !currentEvent.modifierFlags.contains(.shift) else {
            return false
        }
        
        // Only intervene if selection actually spans multiple views
        if manager.hasMultiViewSelection {
            log("SequentialTextView: Collapsing multi-view selection to \(direction)")
            
            if let (targetView, targetIndex) = manager.collapseSelection(to: direction) {
                // 1. Clear everything
                manager.clearAllSelections(except: nil)
                
                // 2. Focus target
                targetView.window?.makeFirstResponder(targetView)
                
                // 3. Place caret at the specific boundary
                targetView.setSelectedRange(NSRange(location: targetIndex, length: 0))
                targetView.scrollRangeToVisible(NSRange(location: targetIndex, length: 0))
                
                // 4. If this is Up/Down, we usually want to move *from* that collapsed point.
                //    Example: Selected lines 1-5. Press Down. Caret goes to line 6 (Move Down from line 5).
                if performMove {
                    if direction == .start {
                        targetView.moveUp(nil)
                    } else {
                        targetView.moveDown(nil)
                    }
                }
                return true
            }
        }
        
        // Also handle the case where we just want to clear external selections
        // (e.g. we are in View A, but View B has selection, and we act on View A)
        if !currentEvent.modifierFlags.contains(.shift) {
            manager.clearAllSelections(except: self)
        }
        
        return false
    }
    
    // MARK: - Navigation Overrides (Caret Movement)
    
    override func moveUp(_ sender: Any?) {
        log("SequentialTextView: moveUp triggered")
        
        // 1. Handle collapse & clearing
        // Check for collapse first
        if handleMultiViewCollapse(direction: .start, performMove: true) { return }
        
        // Clear other views if not multi-selecting
        clearExternalSelectionIfNecessary()
        
        guard let layoutManager = layoutManager else {
            super.moveUp(sender)
            return
        }
        
        let range = selectedRange()
        let indexToProbe = (range.location == string.count && range.location > 0) ? range.location - 1 : range.location
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: indexToProbe)
        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
        
        log(" > View State: Range=\(range), LineStart=\(lineRange.location)")
        log(" > Manager State Before: X=\(selectionManager?.caretManager.currentXDescription ?? "nil")")
        
        // 3. Check if we are on the first line
        if lineRange.location == 0 {
            log("SequentialTextView: Top boundary detected. Delegating to Manager.")
            // We are at the top boundary -> Handover to Manager
            selectionManager?.handleBoundaryNavigation(from: self, direction: .up)
        } else {
            log("SequentialTextView: Internal Move Up.")
            
            // 1. Ensure we have a stored X (capture it now if this is the start of a sequence)
            if let manager = selectionManager, !manager.caretManager.hasStoredPosition {
                manager.caretManager.storeCurrentXPosition(from: self)
            }
            
            // 2. Attempt manual move
            if let manager = selectionManager,
               let targetIndex = manager.caretManager.calculateInternalVerticalMove(in: self, direction: .up) {
                log(" > Manual Move to index: \(targetIndex)")
                setSelectedRange(NSRange(location: targetIndex, length: 0))
                scrollRangeToVisible(NSRange(location: targetIndex, length: 0))
            } else {
                // Fallback if manual calculation fails (shouldn't happen)
                super.moveUp(sender)
            }
        }
    }
    
    override func moveDown(_ sender: Any?) {
        log("SequentialTextView: moveDown triggered")
        
        // 1. Handle collapse & clearing
        // Check for collapse first
        if handleMultiViewCollapse(direction: .end, performMove: true) { return }
        
        // Clear other views if not multi-selecting
        clearExternalSelectionIfNecessary()
        
        guard let layoutManager = layoutManager else {
            super.moveDown(sender)
            return
        }
        
        let range = selectedRange()
        let indexToProbe = (range.location == string.count && range.location > 0) ? range.location - 1 : range.location
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: indexToProbe)
        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
        
        log(" > View State: Range=\(range), LineStart=\(lineRange.location)")
        log(" > Manager State Before: X=\(selectionManager?.caretManager.currentXDescription ?? "nil")")
        
        // 1. Check if we are on the last line
        let isLastLine = NSMaxRange(lineRange) >= layoutManager.numberOfGlyphs
        
        if isLastLine {
            log("SequentialTextView: Bottom boundary detected. Delegating to Manager.")
            // We are at the bottom boundary -> Handover to Manager
            selectionManager?.handleBoundaryNavigation(from: self, direction: .down)
        } else {
            log("SequentialTextView: Internal Move Down.")
            
            // 1. Ensure we have a stored X
            if let manager = selectionManager, !manager.caretManager.hasStoredPosition {
                manager.caretManager.storeCurrentXPosition(from: self)
            }
            
            // 2. Attempt manual move
            if let manager = selectionManager,
               let targetIndex = manager.caretManager.calculateInternalVerticalMove(in: self, direction: .down) {
                log(" > Manual Move to index: \(targetIndex)")
                setSelectedRange(NSRange(location: targetIndex, length: 0))
                scrollRangeToVisible(NSRange(location: targetIndex, length: 0))
            } else {
                super.moveDown(sender)
            }
        }
    }
    
    override func moveLeft(_ sender: Any?) {
        // 1. Handle selection collapse
        // Left arrow collapses to Start, but DOES NOT perform an extra move
        // (Standard behavior: Left Arrow on selection puts caret at start of selection)
        if handleMultiViewCollapse(direction: .start, performMove: false) { return }
        
        // Clear other views if not multi-selecting
        clearExternalSelectionIfNecessary()
        
        // 2. Check for Start Boundary
        // We only jump views if the selection length is 0.
        // If we have a selection at index 0, standard behavior is to collapse it, not jump.
        if selectedRange().location == 0 && selectedRange().length == 0 {
            log("SequentialTextView: Left boundary detected. Delegating to Manager.")
            selectionManager?.handleBoundaryNavigation(from: self, direction: .left)
            return
        }
        
        // 3. Reset vertical memory (if moving left/right, the "X" memory is invalid)
        selectionManager?.caretManager.reset()
        
        super.moveLeft(sender)
    }
    
    override func moveRight(_ sender: Any?) {
        // 1. Handle selection collapse
        // Right arrow collapses to End, but DOES NOT perform an extra move
        // (Standard behavior: Right Arrow on selection puts caret at end of selection)
        if handleMultiViewCollapse(direction: .end, performMove: false) { return }
        
        // Clear other views if not multi-selecting
        clearExternalSelectionIfNecessary()
        
        // 2. Check for End Boundary
        // Note: string.count is the index *after* the last character
        if selectedRange().location == string.count && selectedRange().length == 0 {
            log("SequentialTextView: Right boundary detected. Delegating to Manager.")
            selectionManager?.handleBoundaryNavigation(from: self, direction: .right)
            return
        }
        
        // 3. Reset vertical memory (if moving left/right, the "X" memory is invalid)
        selectionManager?.caretManager.reset()
        
        super.moveRight(sender)
    }
    
    // MARK: - Mouse Overrides (Selection)
    
    override func mouseDown(with event: NSEvent) {
        log("SequentialTextView: mouseDown received")
        
        // Shift+Click support
        if event.modifierFlags.contains(.shift) {
            log("SequentialTextView: Shift+Click detected. Delegating to Manager.")
            selectionManager?.handleShiftClick(event, in: self)
        } else {
            // 1. Tell manager to start a fresh selection
            log("SequentialTextView: New selection start. Delegating to Manager.")
            selectionManager?.handleMouseDown(event, in: self)
            
            // 2. Set the cursor locally
            let point = convert(event.locationInWindow, from: nil)
            let index = characterIndexForInsertion(at: point)
            log("SequentialTextView: Setting local caret to index \(index)")
            setSelectedRange(NSRange(location: index, length: 0))
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Hijack the drag loop to support cross-view selection
        // log("SequentialTextView: mouseDragged")
        selectionManager?.handleMouseDragged(event)
        
        // Autoscroll is necessary so the scrollview moves when dragging to edges
        autoscroll(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        log("SequentialTextView: mouseUp")
        selectionManager?.handleMouseUp(event)
        super.mouseUp(with: event)
    }
    
    // MARK: - Select All Text
    
    override func selectAll(_ sender: Any?) {
        log("TextView: selectAll called")
        
        guard let manager = selectionManager else {
            super.selectAll(sender)
            return
        }
        
        if manager.isCurrentlyDragging {
            log("TextView: selectAll blocked - currently dragging")
            return
        }
        
        manager.selectAllViews()
    }
    
    // MARK: - Copy
    
    override func copy(_ sender: Any?) {
        guard let manager = selectionManager,
              let selectedText = manager.getSelectedText() else {
            // Fallback to default behavior if no manager or no selection
            super.copy(sender)
            return
        }
        
        // Put the combined text on the pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
        
        log("TextView: Copied \(selectedText.count) characters across views")
    }
    
    // MARK: - Deletion
    
    override func deleteBackward(_ sender: Any?) {
        // Check for selection across multiple text views
        if let manager = selectionManager, manager.hasMultiViewSelection {
            log("SequentialTextView: Multi-view delete detected. Delegating to Manager.")
            manager.handleMultiViewDelete()
            return
        }
        
        // Otherwise use standard behavior
        super.deleteBackward(sender)
    }
    
    // MARK: - Custom Drawing
    
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        
        // If this view is NOT the key focus, but is part of a multi-block selection,
        // we manually draw the selection highlight.
        if forceInactiveSelectionDisplay && window?.firstResponder != self {
            // log("SequentialTextView: Drawing custom background for inactive selection")
            drawCustomSelection()
        }
    }
    
    private func drawCustomSelection() {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        
        NSColor.selectedTextBackgroundColor.setFill()
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: glyphRange, in: textContainer) { rect, _ in
            var drawRect = rect
            drawRect.origin.x += self.textContainerOrigin.x
            drawRect.origin.y += self.textContainerOrigin.y
            drawRect.fill()
        }
    }
    
    // Disable native inactive selection drawing to avoid conflicts
    override var selectedTextAttributes: [NSAttributedString.Key : Any] {
        get {
            if forceInactiveSelectionDisplay && window?.firstResponder != self {
                return [:]
            }
            return super.selectedTextAttributes
        }
        set { super.selectedTextAttributes = newValue }
    }
}
