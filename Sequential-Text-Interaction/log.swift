//
//  log.swift
//  Notes-app
//
//  Created by Frederik Handberg on 20/11/2025.
//

import Foundation

let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

func log(_ message: String,
         file: String = #file,
         line: Int = #line) {
    let timestamp = timestampFormatter.string(from: Date())
    let fileName = (file as NSString).lastPathComponent
    Swift.print("[\(timestamp)] \(fileName):\(line) — \(message)")
}
