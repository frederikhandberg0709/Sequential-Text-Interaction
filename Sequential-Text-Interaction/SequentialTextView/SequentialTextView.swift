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
    func clearExternalSelectionIfNecessary() {
        // We look at the current event modifiers.
        // If Shift is NOT held down, it means we are moving the caret without extending selection.
        // Therefore, we should clear any selection existing in neighbor blocks.
        let flags = NSApp.currentEvent?.modifierFlags ?? .init()
        if !flags.contains(.shift) {
            log("SequentialTextView: Arrow key without shift. Clearing external selections.")
            selectionManager?.clearAllSelections(except: self)
            
            selectionManager?.resetSelectionAnchor()
        }
    }
    
    // MARK: - Helper: Handle Multi-View Collapse
    
    /// Returns TRUE if we handled a multi-view collapse, meaning the caller should return immediately.
    func handleMultiViewCollapse(direction: SequentialTextViewManager.SelectionBoundary, performMove: Bool) -> Bool {
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
                
                manager.resetSelectionAnchor()
                
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
}
