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
        Block(text: "Short line.\nThis is a significantly longer line that extends far to the right.\nTiny.\nBack to a long line to see if the caret remembered the X position from line 2.\nEnd."),
        Block(text: "Start here at the very end of this long sentence."),
        Block(text: "Tiny."),
        Block(text: "End here. Ideally the caret is far to the right."),
        Block(text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla sit amet massa et lectus auctor finibus.\n\nVivamus a congue elit, ut viverra orci. Phasellus vel urna id nisi elementum placerat. Pellentesque dapibus urna vitae pulvinar facilisis. Fusce orci elit, consectetur at vulputate et, vehicula sit amet elit.\nNunc egestas ultrices diam ac dapibus. Ut gravida, leo vel ullamcorper varius, erat risus faucibus ligula, bibendum viverra eros urna quis ex. Sed sit amet orci leo. Sed elit felis, fringilla in nisi imperdiet, euismod placerat ligula. Quisque aliquet nibh nisi, ac elementum arcu mollis a.\nNullam dapibus lectus at aliquet condimentum. Fusce varius mauris eros, in tempor metus blandit id. Aliquam vestibulum lacus ac nulla tristique, a ultrices nibh mollis. Vivamus viverra felis sed velit pretium, non tempor ex tristique."),
        Block(text: "WWWWWWWWWW"),
        Block(text: "iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii"),
        Block(text: "WWWWWWWWWW"),
        Block(text: "Body\nThis is the second block. You can select across this gap - that's pretty cool.\nasdas\nMore text here.asd\nasd"),
        Block(text: "Footerad\nThis is the third block.")
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
        
        // Register with the manager
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
