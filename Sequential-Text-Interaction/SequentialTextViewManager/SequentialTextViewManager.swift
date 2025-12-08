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
    var isDragging = false
    var anchorInfo: (view: SequentialTextView, charIndex: Int)?
    private var needsSorting = false
    
    // Timestamp to prevent SwiftUI gestures from clearing selection immediately after creation
    var lastInteractionTime: TimeInterval = 0
    
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
    func sortViewsIfNeeded() {
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
    
    // MARK: - Utilities
    
    func updateInteractionTime() {
        lastInteractionTime = Date().timeIntervalSinceReferenceDate
    }
    
    func resetSelectionAnchor() {
        if anchorInfo != nil {
            anchorInfo = nil
            log("Manager: Anchor reset")
        }
    }
}
