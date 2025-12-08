//
//  SequentialTextViewManager+CaretNavigation.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 06/12/2025.
//

import AppKit

// MARK: - Extension: Caret Navigation
// Handles moving the cursor *without* selecting text (Arrow keys, Cmd+Arrow, Option+Arrow)

extension SequentialTextViewManager {
    
    // MARK: - Global Navigation
    
    /// Moves caret to the start of the very first text view (Cmd + Up)
    func handleGlobalStart() {
        resetSelectionAnchor()
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
        resetSelectionAnchor()
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
    
    // MARK: Boundary Crossings (Arrow Keys)
    
    func handleBoundaryNavigation(from view: SequentialTextView, direction: SequentialNavigationDirection) {
        sortViewsIfNeeded()
        
        resetSelectionAnchor()
        
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
    
    // MARK: - Word Navigation (Option + Arrow)
    
    /// Handles Option + Left Arrow crossing into the previous view.
    /// Standard behavior dictates this should select the *start* of the last word in the previous view.
    func handleWordLeftBoundary(from view: SequentialTextView) {
        resetSelectionAnchor()
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
        resetSelectionAnchor()
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
}
