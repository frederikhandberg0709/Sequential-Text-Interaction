//
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
    
    // Debugging helper
    var currentXDescription: String {
        if let x = desiredXPosition { return String(format: "%.2f", x) }
        return "nil"
    }
    
    // MARK: - State Management
    
    func reset() {
        if desiredXPosition != nil {
            log(" [CaretManager] RESET: Clearing X (was \(currentXDescription)).")
            desiredXPosition = nil
        }
    }
    
    var hasStoredPosition: Bool {
        return desiredXPosition != nil
    }
    
    func storeCurrentXPosition(from textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }
        
        let selectedRange = textView.selectedRange()
        
        // Only store X if we have a pure insertion point (length 0)
        guard selectedRange.length == 0 else {
            desiredXPosition = nil
            return
        }
        storeCurrentXPositionAt(index: selectedRange.location, in: textView)
    }
    
    /// Store X position for a specific character index (used during selection operations)
    func storeCurrentXPositionAt(index: Int, in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }
        
        layoutManager.ensureLayout(for: textContainer)
        
        // 1. Handle Empty String
        if textView.string.isEmpty {
            desiredXPosition = 0
            log("storeCurrentXPositionAt: Empty text, storing X=0")
            return
        }
        
        // 2. Handle End of Text
        if index >= textView.string.count {
            let lastCharIndex = max(0, textView.string.count - 1)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lastCharIndex)
            
            let rect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            
            desiredXPosition = rect.maxX
            log("storeCurrentXPositionAt: At end of text, stored X=\(rect.maxX)")
            return
        }
        
        // 3. Handle Normal Character
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
        let rect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        
        desiredXPosition = rect.origin.x
        log("storeCurrentXPositionAt: Stored X=\(rect.origin.x) at character \(index)")
    }
    
    // MARK: - Navigation Logic
    
    /// Calculates the target index for moving Up/Down within the SAME view
    func calculateInternalVerticalMove(
        in textView: NSTextView,
        direction: SequentialNavigationDirection
    ) -> Int? {
        let selectedRange = textView.selectedRange()
        return calculateInternalVerticalMoveFrom(index: selectedRange.location, in: textView, direction: direction)
    }
    
    /// Calculates the target index for moving Up/Down from a specific index (used during selection)
    func calculateInternalVerticalMoveFrom(
        index: Int,
        in textView: NSTextView,
        direction: SequentialNavigationDirection
    ) -> Int? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let storedX = desiredXPosition else {
            return nil
        }
        
        // Robustly determine current line
        // If at end of string, peek back one char to get the line that "owns" the end.
        let probeIndex = (index == textView.string.count && index > 0) ? index - 1 : index
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: probeIndex)
        
        // Get current line geometry
        var currentLineRange = NSRange(location: 0, length: 0)
        let currentLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &currentLineRange)
        
        // Determine the target glyph index to find the new line
        var targetProbeGlyphIndex: Int
        
        if direction == .up {
            // The character immediately before the current line starts
            targetProbeGlyphIndex = currentLineRange.location - 1
            if targetProbeGlyphIndex < 0 { return nil } // Top boundary
        } else {
            // The character immediately after the current line ends
            targetProbeGlyphIndex = NSMaxRange(currentLineRange)
            if targetProbeGlyphIndex >= layoutManager.numberOfGlyphs { return nil } // Bottom boundary
        }
        
        // Get Target Line Geometry
        var targetLineRange = NSRange(location: 0, length: 0)
        let targetLineRect = layoutManager.lineFragmentRect(
            forGlyphAt: targetProbeGlyphIndex,
            effectiveRange: &targetLineRange
        )
        
        // Safety: If we mapped to the same line (e.g., probe wasn't far enough), abort
        if targetLineRect.origin.y == currentLineRect.origin.y {
            return nil
        }
        
        let charRange = layoutManager.characterRange(forGlyphRange: targetLineRange, actualGlyphRange: nil)
        let lineString = (textView.string as NSString).substring(with: charRange).trimmingCharacters(in: .newlines)
        log(" [Calc] Moving \(direction == .up ? "UP" : "DOWN") from LineY=\(Int(currentLineRect.minY)) to LineY=\(Int(targetLineRect.minY))")
        log(" [Calc] Target Line Text: '\(lineString)'")
        log(" [Calc] Target Rect: \(targetLineRect)")
        
        return indexForPosition(
            x: storedX,
            lineRect: targetLineRect,
            lineGlyphRange: targetLineRange,
            in: textView
        )
    }

    /// Calculates the target index for moving INTO this view from another view
    func calculateCaretPosition(
        in textView: NSTextView,
        preferEnd: Bool = false
    ) -> Int {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let storedX = desiredXPosition else {
            return preferEnd ? textView.string.count : 0
        }
        
        layoutManager.ensureLayout(for: textContainer)
        
        if textView.string.isEmpty { return 0 }
        
        // Determine Target Line (First or Last)
        let targetLineGlyphIndex: Int
        if preferEnd {
            let numberOfGlyphs = layoutManager.numberOfGlyphs
            guard numberOfGlyphs > 0 else { return textView.string.count }
            targetLineGlyphIndex = numberOfGlyphs - 1
        } else {
            targetLineGlyphIndex = 0
        }
        
        // Get Line Geometry
        var lineGlyphRange = NSRange(location: 0, length: 0)
        let lineFragmentRect = layoutManager.lineFragmentRect(
            forGlyphAt: targetLineGlyphIndex,
            effectiveRange: &lineGlyphRange
        )
        
        let charRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
        let lineString = (textView.string as NSString).substring(with: charRange).trimmingCharacters(in: .newlines)
        log(" [Calc] Boundary Enter: Target Line='\(lineString)'")
        
        return indexForPosition(
            x: storedX,
            lineRect: lineFragmentRect,
            lineGlyphRange: lineGlyphRange,
            in: textView
        )
    }
    
    // MARK: - Core Calculation
    
    private func indexForPosition(
        x: CGFloat,
        lineRect: CGRect,
        lineGlyphRange: NSRange,
        in textView: NSTextView
    ) -> Int {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return 0 }
        
        // 1. Find the character index closest to Point(X, CenterY)
        let yPosition = lineRect.minY + (lineRect.height * 0.5)
        let point = CGPoint(x: x, y: yPosition)
        
        var fraction: CGFloat = 0
        var characterIndex = layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        
        // 2. Snap to nearest boundary (The "0 vs 1" Fix)
        if fraction >= 0.5 {
            characterIndex += 1
        }
        
        // 3. Clamp to string bounds
        characterIndex = min(max(0, characterIndex), textView.string.count)
        
        // 4. Validate we are visually on the correct line
        // Sometimes snapping to the "nearest" index jumps us to the start of the *next* line.
        // We check if the resulting glyph is within our target line's glyph range.
        
        // Get glyph index for the calculated char
        // Note: If charIndex == string.count, we use the last valid glyph to check range
        let checkIndex = (characterIndex == textView.string.count) ? max(0, characterIndex - 1) : characterIndex
        let charGlyphIndex = layoutManager.glyphIndexForCharacter(at: checkIndex)
        
        let isInsideLine = charGlyphIndex >= lineGlyphRange.location &&
                           charGlyphIndex < (lineGlyphRange.location + lineGlyphRange.length)
        
        if !isInsideLine {
            // We drifted. Force snap to the end of the target line.
            let endOfLineGlyph = lineGlyphRange.location + lineGlyphRange.length - 1
            characterIndex = layoutManager.characterIndexForGlyph(at: endOfLineGlyph)
            
            // If the line ends with a newline, we usually want to be before it (visually)
            // unless we are specifically targeting the very end.
            if characterIndex < textView.string.count && textView.string[textView.string.index(textView.string.startIndex, offsetBy: characterIndex)] == "\n" {
                // Keep index as is (before newline)
            } else {
                characterIndex += 1
            }
        }
        
        // 5. "Phantom X" Handling (End of Line Snap)
        // If stored X is way past the visual end of the line, ensure we snap to the very end.
        let lineCharRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
        
        if characterIndex >= lineCharRange.location && characterIndex < lineCharRange.location + lineCharRange.length {
            let lastCharInLine = lineCharRange.location + lineCharRange.length - 1
            if lastCharInLine >= 0 && lastCharInLine < textView.string.count {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: lastCharInLine)
                let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
                
                if x > glyphRect.maxX {
                    characterIndex = lastCharInLine
                    let charIndex = textView.string.index(textView.string.startIndex, offsetBy: characterIndex)
                    
                    // If not a newline, step past it
                    if textView.string[charIndex] != "\n" {
                        characterIndex += 1
                    }
                    log("X > Line Width. Snapped to end: \(characterIndex)")
                }
            }
        }
        
        return characterIndex
    }
}
