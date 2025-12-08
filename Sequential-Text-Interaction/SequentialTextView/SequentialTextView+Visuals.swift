//
//  SequentialTextView+Visuals.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 06/12/2025.
//

import AppKit

// MARK: - Extension: Visuals

extension SequentialTextView {
    
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
