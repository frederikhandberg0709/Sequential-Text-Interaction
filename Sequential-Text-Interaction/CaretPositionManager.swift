//
//  CaretPositionManager.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 21/11/2025.
//

import AppKit
import Foundation
import Observation

@Observable
class CaretPositionManager {
    private var desiredXPosition: CGFloat?
    private(set) var isNavigatingUp: Bool = false
    private(set) var isNavigatingDown: Bool = false
    private(set) var isNavigatingLeft: Bool = false
    private(set) var isNavigatingRight: Bool = false
    
    func setNavigationDirection(up: Bool = false, down: Bool = false, left: Bool = false, right: Bool = false) {
        log("CaretPositionManager.setNavigationDirection: up=\(up), down=\(down), left=\(left), right=\(right)")
        isNavigatingUp = up
        isNavigatingDown = down
        isNavigatingLeft = left
        isNavigatingRight = right
    }
    
    func clearNavigationDirection() {
        log("CaretPositionManager.clearNavigationDirection")
        isNavigatingUp = false
        isNavigatingDown = false
        isNavigatingLeft = false
        isNavigatingRight = false
    }
    
    var shouldPositionAtEnd: Bool {
        return isNavigatingUp || isNavigatingLeft
    }
    
    var shouldPositionAtBeginning: Bool {
        return isNavigatingDown || isNavigatingRight
    }
    
    func storeCurrentXPosition(from textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            log("storeCurrentXPosition: No layout manager or text container")
            desiredXPosition = nil
            return
        }
        
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0 else {
            log("storeCurrentXPosition: Selection length > 0, not storing")
            desiredXPosition = nil
            return
        }
        
        layoutManager.ensureLayout(for: textContainer)
        
        if textView.string.isEmpty {
            log("storeCurrentXPosition: Empty text, storing X=0")
            desiredXPosition = 0
            return
        }
        
        // Handle caret at end of text
        if selectedRange.location >= textView.string.count {
            // Get the last character's position
            let lastCharIndex = max(0, textView.string.count - 1)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lastCharIndex)
            
            guard glyphIndex < layoutManager.numberOfGlyphs else {
                log("storeCurrentXPosition: At end, storing X=0")
                desiredXPosition = 0
                return
            }
            
            let rect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            
            // Store the position at the END of the last character
            desiredXPosition = rect.maxX
            log("storeCurrentXPosition: At end of text, stored X=\(rect.maxX)")
            return
        }
        
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: selectedRange.location)
        
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            log("storeCurrentXPosition: Glyph index out of bounds, storing X=0")
            desiredXPosition = 0
            return
        }
        
        let rect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        
        desiredXPosition = rect.origin.x
        log("storeCurrentXPosition: Stored X=\(rect.origin.x) at character \(selectedRange.location)")
    }
    
    func calculateCaretPosition(
        in textView: NSTextView,
        preferEnd: Bool = false
    ) -> Int {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let storedX = desiredXPosition else {
            log("calculateCaretPosition: No stored X, returning \(preferEnd ? "end" : "start")")
            return preferEnd ? textView.string.count : 0
        }
        
        layoutManager.ensureLayout(for: textContainer)
        
        if textView.string.isEmpty {
            log("calculateCaretPosition: Empty text, returning 0")
            return 0
        }
        
        // Determine which line to target
        let targetLineGlyphIndex: Int
        if preferEnd {
            // Navigating UP - target the LAST line
            let numberOfGlyphs = layoutManager.numberOfGlyphs
            guard numberOfGlyphs > 0 else {
                log("calculateCaretPosition: No glyphs, returning \(textView.string.count)")
                return textView.string.count
            }
            targetLineGlyphIndex = numberOfGlyphs - 1
            log("calculateCaretPosition: preferEnd=true, targeting last line")
        } else {
            // Navigating DOWN - target the FIRST line
            targetLineGlyphIndex = 0
            log("calculateCaretPosition: preferEnd=false, targeting first line")
        }
        
        // Get the line fragment rect for the target line
        var lineGlyphRange = NSRange(location: 0, length: 0)
        let lineFragmentRect = layoutManager.lineFragmentRect(
            forGlyphAt: targetLineGlyphIndex,
            effectiveRange: &lineGlyphRange
        )
        
        // Use the middle of the line for Y coordinate
        let yPosition = lineFragmentRect.minY + (lineFragmentRect.height * 0.5)
        let point = CGPoint(x: storedX, y: yPosition)
        
        // Get character index at this point
        var fraction: CGFloat = 0
        var characterIndex = layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        
        // Verify we're actually on the target line and handle edge cases
        let charGlyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        
        // Check if the character is within the target line's glyph range
        if charGlyphIndex < lineGlyphRange.location || charGlyphIndex >= lineGlyphRange.location + lineGlyphRange.length {
            // Character index is outside target line, adjust it
            if preferEnd {
                // For last line, convert last glyph to character index
                characterIndex = layoutManager.characterIndexForGlyph(at: lineGlyphRange.location + lineGlyphRange.length - 1)
            } else {
                // For first line, use first character
                characterIndex = layoutManager.characterIndexForGlyph(at: lineGlyphRange.location)
            }
            log("Adjusted character index to stay within target line: \(characterIndex)")
        }
        
        // Get the actual character range for this line
        let lineCharRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
        
        // Handle case where stored X is beyond the line's content
        // This happens when the caret was at the end of a longer line
        if characterIndex >= lineCharRange.location && characterIndex < lineCharRange.location + lineCharRange.length {
            // Check if we should snap to end of line
            let lastCharInLine = lineCharRange.location + lineCharRange.length - 1
            
            if lastCharInLine >= 0 && lastCharInLine < textView.string.count {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: lastCharInLine)
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: glyphIndex, length: 1),
                    in: textContainer
                )
                
                // If stored X is beyond the last character, snap to end of line
                if storedX > glyphRect.maxX {
                    characterIndex = lastCharInLine
                    // Exclude trailing newline
                    let charIndex = textView.string.index(textView.string.startIndex, offsetBy: characterIndex)
                    if textView.string[charIndex] == "\n" && characterIndex > lineCharRange.location {
                        characterIndex -= 1
                    }
                    log("X beyond line content, snapping to end: \(characterIndex)")
                }
            }
        }
        
        let clampedIndex = min(max(0, characterIndex), textView.string.count)
        
        log("calculateCaretPosition: X=\(storedX), Y=\(yPosition) -> character \(clampedIndex)")
        
        return clampedIndex
    }
    
    func reset() {
        log("RESET: Clearing stored X position - called from: \(Thread.callStackSymbols[1])")
        log(" [CaretManager] RESET: Clearing X (was \(currentXDescription)). Source: \(Thread.callStackSymbols[1].split(separator: "$").last ?? "Unknown")")
        desiredXPosition = nil
    }
    
    var  hasStoredPosition: Bool {
        return desiredXPosition != nil
    }
}
