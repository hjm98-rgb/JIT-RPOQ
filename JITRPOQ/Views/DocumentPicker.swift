//
//  DocumentPicker.swift
//  JIT RPOQ
//
//  用 UIDocumentPickerViewController(asCopy: true) 选文件：
//  文件先复制进沙盒，避免 iCloud / 文件 App 的安全作用域读取把界面卡死。
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    var allowsMultiple: Bool = false
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.item, .data, .xml, .propertyList]
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        controller.allowsMultipleSelection = allowsMultiple
        controller.shouldShowFileExtensions = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
