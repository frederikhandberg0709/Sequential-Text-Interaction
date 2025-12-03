//
//  Block.swift
//  Sequential-Text-Interaction
//
//  Created by Frederik Handberg on 20/11/2025.
//

import Foundation
import AppKit

struct Block: Identifiable {
    let id: UUID
    var text: NSAttributedString
    
    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14)
        ]
        self.text = NSAttributedString(string: text, attributes: attrs)
    }
}
