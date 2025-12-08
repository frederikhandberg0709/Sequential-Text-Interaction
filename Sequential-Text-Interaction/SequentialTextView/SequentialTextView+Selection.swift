//
//  SequentialTextView+Selection.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 06/12/2025.
//

import AppKit

// MARK: - Extension: Selection

extension SequentialTextView {
    
    // MARK: - Shift + Arrow Keys (Selection Extension)
    
    override func moveUpAndModifySelection(_ sender: Any?) {
        log("SequentialTextView: moveUpAndModifySelection (Shift+Up)")
        
        guard let layoutManager = layoutManager,
              let manager = selectionManager else {
            super.moveUpAndModifySelection(sender)
            return
        }
        
        // 1. Establish anchor if needed
        manager.ensureSelectionAnchor(in: self)
        
        let range = selectedRange()
        
        // Find the "head" of the selection (the end that moves during selection)
        // For Shift+Up, selection is extending from the current head upward
        let selectionHead = manager.getSelectionHead(in: self)
        
        let indexToProbe = (/*range.location*/ selectionHead == string.count && /*range.location*/ selectionHead > 0) ? /*range.location*/ selectionHead - 1 : /*range.location*/ selectionHead
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: indexToProbe)
        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
        
        log(" > Selection range: \(range), head: \(selectionHead), lineStart: \(lineRange.location)")
        
        // 2. Check if selection is on the first line -> cross-view selection
        if lineRange.location == 0 {
            log("SequentialTextView: Shift+Up at boundary, delegating to manager")
            manager.handleShiftBoundaryNavigation(from: self, direction: .up)
        } else {
            log("SequentialTextView: Shift+Up internal move")
            
            // Store X if needed
            if !manager.caretManager.hasStoredPosition {
                manager.caretManager.storeCurrentXPositionAt(index: selectionHead, in: self)
            }
            
            // Calculate target index
            if let targetIndex = manager.caretManager.calculateInternalVerticalMoveFrom(index: selectionHead, in: self, direction: .up) {
                manager.extendSelection(in: self, to: targetIndex)
            } else {
                super.moveUpAndModifySelection(sender)
            }
        }
    }
    
    override func moveDownAndModifySelection(_ sender: Any?) {
        log("SequentialTextView: moveDownAndModifySelection (Shift+Down)")
        
        guard let layoutManager = layoutManager,
              let manager = selectionManager else {
            super.moveDownAndModifySelection(sender)
            return
        }
        
        // 1. Establish anchor if needed
        manager.ensureSelectionAnchor(in: self)
        
        let range = selectedRange()
        
        // Find the "head" of the selection (the end that moves during selection)
        let selectionHead = manager.getSelectionHead(in: self)
        
        let indexToProbe = (selectionHead == string.count && selectionHead > 0) ? selectionHead - 1 : selectionHead
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: indexToProbe)
        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
        
        let isLastLine = NSMaxRange(lineRange) >= layoutManager.numberOfGlyphs
        
        log(" > Selection range: \(range), head: \(selectionHead), isLastLine: \(isLastLine)")
        
        // 2. Check if we're on the last line -> cross-view selection
        if isLastLine {
            log("SequentialTextView: Shift+Down at boundary, delegating to manager")
            manager.handleShiftBoundaryNavigation(from: self, direction: .down)
        } else {
            log("SequentialTextView: Shift+Down internal move")
            
            // Store X if needed
            if !manager.caretManager.hasStoredPosition {
                manager.caretManager.storeCurrentXPositionAt(index: selectionHead, in: self)
            }
            
            // Calculate target index from the selection head
            if let targetIndex = manager.caretManager.calculateInternalVerticalMoveFrom(index: selectionHead, in: self, direction: .down) {
                manager.extendSelection(in: self, to: targetIndex)
            } else {
                super.moveDownAndModifySelection(sender)
            }
        }
    }
    
    override func moveLeftAndModifySelection(_ sender: Any?) {
        log("SequentialTextView: moveLeftAndModifySelection (Shift+Left)")
        
        guard let manager = selectionManager else {
            super.moveLeftAndModifySelection(sender)
            return
        }
        
        // 1. Establish anchor if needed
        manager.ensureSelectionAnchor(in: self)
        
        // 2. Check for boundary
        let selectionHead = manager.getSelectionHead(in: self)
        if selectionHead == 0 {
            log("SequentialTextView: Shift+Left at boundary, delegating to manager")
            manager.handleShiftBoundaryNavigation(from: self, direction: .left)
            return
        }
        
        // 3. Reset vertical memory
        manager.caretManager.reset()
        
        // 4. Internal selection extension
        let newLocation = max(0, selectionHead - 1)
        manager.extendSelection(in: self, to: newLocation)
    }
    
    override func moveRightAndModifySelection(_ sender: Any?) {
        log("SequentialTextView: moveRightAndModifySelection (Shift+Right)")
        
        guard let manager = selectionManager else {
            super.moveRightAndModifySelection(sender)
            return
        }
        
        // 1. Establish anchor if needed
        manager.ensureSelectionAnchor(in: self)
        
        // 2. Check for boundary
        let selectionHead = manager.getSelectionHead(in: self)
        if selectionHead == string.count {
            log("SequentialTextView: Shift+Right at boundary, delegating to manager")
            manager.handleShiftBoundaryNavigation(from: self, direction: .right)
            return
        }
        
        // 3. Reset vertical memory
        manager.caretManager.reset()
        
        // 4. Internal selection extension
        let newLocation = min(string.count, selectionHead + 1)
        manager.extendSelection(in: self, to: newLocation)
    }
    
    // MARK: - Cmd+Shift+Arrow (Global Selection Extension)
    
    override func moveToBeginningOfDocumentAndModifySelection(_ sender: Any?) {
        log("SequentialTextView: moveToBeginningOfDocumentAndModifySelection (Cmd+Shift+Up)")
        selectionManager?.handleGlobalShiftStart(from: self)
    }
    
    override func moveToEndOfDocumentAndModifySelection(_ sender: Any?) {
        log("SequentialTextView: moveToEndOfDocumentAndModifySelection (Cmd+Shift+Down)")
        selectionManager?.handleGlobalShiftEnd(from: self)
    }
}
