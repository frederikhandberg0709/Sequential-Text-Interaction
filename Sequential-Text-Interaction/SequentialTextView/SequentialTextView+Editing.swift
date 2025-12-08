//
//  SequentialTextView+Editing.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 06/12/2025.
//

import AppKit

// MARK: - Extension: Editing Actions

extension SequentialTextView {
    
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
}
