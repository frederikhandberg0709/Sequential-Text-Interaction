//
//  SequentialTextView+CaretNavigation.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 06/12/2025.
//

import AppKit

// MARK: - Extension: Caret Navigation
// Standard arrow key movements (No Shift)

extension SequentialTextView {
    
    // MARK: Global (Cmd + Arrow)
    
    override func moveToBeginningOfDocument(_ sender: Any?) {
        log("SequentialTextView: moveToBeginningOfDocument (Cmd+Up)")
        
        // 1. Clear external selection if Shift is not pressed (Navigation only)
        clearExternalSelectionIfNecessary()
        
        // 2. Delegate to Manager
        selectionManager?.handleGlobalStart()
    }
    
    override func moveToEndOfDocument(_ sender: Any?) {
        log("SequentialTextView: moveToEndOfDocument (Cmd+Down)")
        
        // 1. Clear external selection
        clearExternalSelectionIfNecessary()
        
        // 2. Delegate to Manager
        selectionManager?.handleGlobalEnd()
    }
    
    // MARK: Arrow Keys
    
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
    
    // MARK: Word Navigation (Option + Arrow)
    
    override func moveWordLeft(_ sender: Any?) {
        log("SequentialTextView: moveWordLeft (Option+Left)")
        
        // 1. Handle selection collapse (Standard behavior: collapse to start)
        if handleMultiViewCollapse(direction: .start, performMove: false) { return }
        
        // 2. Clear external selection if Shift is not pressed
        clearExternalSelectionIfNecessary()
        
        // 3. Boundary Check: If at start, jump to previous view
        if selectedRange().location == 0 && selectedRange().length == 0 {
            log("SequentialTextView: Word Left boundary. Delegating to Manager.")
            selectionManager?.handleWordLeftBoundary(from: self)
            return
        }
        
        // 4. Reset vertical memory (horizontal move invalidates X position)
        selectionManager?.caretManager.reset()
        
        // 5. Native word movement
        super.moveWordLeft(sender)
    }
    
    override func moveWordRight(_ sender: Any?) {
        log("SequentialTextView: moveWordRight (Option+Right)")
        
        // 1. Handle selection collapse (Standard behavior: collapse to end)
        if handleMultiViewCollapse(direction: .end, performMove: false) { return }
        
        // 2. Clear external selection if Shift is not pressed
        clearExternalSelectionIfNecessary()
        
        // 3. Boundary Check: If at end, jump to next view
        // Note: string.count is the index *after* the last character
        if selectedRange().location == string.count && selectedRange().length == 0 {
            log("SequentialTextView: Word Right boundary. Delegating to Manager.")
            selectionManager?.handleWordRightBoundary(from: self)
            return
        }
        
        // 4. Reset vertical memory
        selectionManager?.caretManager.reset()
        
        // 5. Native word movement
        super.moveWordRight(sender)
    }
}
