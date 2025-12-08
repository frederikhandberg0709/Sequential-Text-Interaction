//
//  SequentialTextView+Mouse.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 06/12/2025.
//

import AppKit

// MARK: - Extenstion: Mouse

extension SequentialTextView {
    
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
}
