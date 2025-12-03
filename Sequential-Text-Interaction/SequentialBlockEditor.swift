//
//  SequentialBlockEditor.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 02/12/2025.
//

import SwiftUI
import Observation

struct SequentialBlockEditor: View {
    // The single source of truth for the list of blocks
    @State private var blocks: [Block] = [
        Block(text: "Header\nThis is the first block."),
        Block(text: "Body\nThis is the second block. You can select across this gap."),
        Block(text: "Footer\nThis is the third block.")
    ]
    
    @State private var selectionManager = SequentialTextViewManager()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach($blocks) { $block in
                    SequentialBlockView(
                        text: $block.text,
                        manager: selectionManager
                    )
                }
            }
            .padding()
        }
        .background(Color.clear)
        // Global click handler to clear selection if clicking empty space
        .onTapGesture {
            selectionManager.clearAllSelections(except: nil)
        }
    }
}

// MARK: - The Bridge

struct SequentialBlockView: NSViewRepresentable {
    @Binding var text: NSAttributedString
    var manager: SequentialTextViewManager
    
    func makeNSView(context: Context) -> SequentialTextView {
        let textView = SequentialTextView()
        
        // Standard Visual Setup
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .white
        
        // Layout Setup
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        
        // Set initial text
        textView.textStorage?.setAttributedString(text)
        
        // IMPORTANT: Register with the manager
        manager.register(textView)
        
        textView.delegate = context.coordinator
        
        return textView
    }
    
    func updateNSView(_ textView: SequentialTextView, context: Context) {
        // Update text only if it changed externally to avoid loops
        if textView.textStorage?.string != text.string {
            textView.textStorage?.setAttributedString(text)
        }
        
        // Ensure manager reference is fresh (though typically stable)
        textView.selectionManager = manager
    }
    
    static func dismantleNSView(_ textView: SequentialTextView, coordinator: Coordinator) {
        // Cleanup: Removing the view from the manager prevents memory leaks
        // and keeps the arrow navigation logic clean.
        textView.selectionManager?.unregister(textView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SequentialBlockView
        
        init(_ parent: SequentialBlockView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Sync changes back to SwiftUI model
            if let storage = textView.textStorage {
                parent.text = storage
            }
        }
    }
}
