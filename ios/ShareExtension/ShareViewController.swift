//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Simon Nikel on 27.08.25.
//

import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

    private func openHostApp() {
        guard let url = URL(string: "receivesharingintent://wake") else { return }
        // Host-App aus der Extension heraus öffnen. open(_:) schließt die Extension-UI selbstständig.
        self.extensionContext?.open(url, completionHandler: nil)
    }

    private func saveAttachmentsToAppGroup(completion: @escaping () -> Void) {
        let groupId = "group.com.simonnikel.phone"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            print("[ShareExt] missing app group container")
            completion(); return
        }
        guard let items = self.extensionContext?.inputItems as? [NSExtensionItem] else {
            print("[ShareExt] no input items")
            completion(); return
        }

        let wants: [String] = [
            UTType.audio.identifier,
            "public.mpeg-4-audio",
            "com.apple.m4a-audio",
            "public.mp3",
            "public.aiff-audio",
            "public.waveform-audio",
        ]

        let group = DispatchGroup()
        var savedPaths: [String] = []

        for item in items {
            for provider in item.attachments ?? [] {
                guard wants.contains(where: { provider.hasItemConformingToTypeIdentifier($0) }) else { continue }
                group.enter()

                // 1) Generisch als Audio versuchen; wenn das nicht geht, nehmen wir die erste passende UTI aus wants
                func load(using typeId: String, fallbackIndex: Int = 0) {
                    provider.loadItem(forTypeIdentifier: typeId, options: nil) { (nsItem, error) in
                        if let error = error { print("[ShareExt] loadItem error: \(error)") }

                        if let url = nsItem as? URL {
                            let started = url.startAccessingSecurityScopedResource()
                            defer { if started { url.stopAccessingSecurityScopedResource() } }

                            let originalExt = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
                            let dest = containerURL.appendingPathComponent("Shared-\(UUID().uuidString).\(originalExt)")

                            do {
                                // Direkte Kopie versuchen
                                try? FileManager.default.removeItem(at: dest)
                                do {
                                    try FileManager.default.copyItem(at: url, to: dest)
                                } catch {
                                    // Fallback: via Data
                                    let data = try Data(contentsOf: url)
                                    try data.write(to: dest, options: .atomic)
                                }
                                savedPaths.append(dest.path)
                                print("[ShareExt] saved: \(dest.path)")
                            } catch {
                                print("[ShareExt] copy failed: \(error)")
                            }

                            group.leave()
                            return
                        }

                        // Nächsten passenden Typ probieren
                        var nextIdx = fallbackIndex
                        while nextIdx < wants.count && wants[nextIdx] == typeId { nextIdx += 1 }
                        if nextIdx < wants.count {
                            load(using: wants[nextIdx], fallbackIndex: nextIdx)
                        } else {
                            print("[ShareExt] no usable URL from provider")
                            group.leave()
                        }
                    }
                }

                // Start mit dem generischen Audio-UTType
                load(using: UTType.audio.identifier)
            }
        }

        group.notify(queue: .main) {
            // 2) Liste in App Group UserDefaults ablegen
            if let defaults = UserDefaults(suiteName: groupId) {
                var list = defaults.stringArray(forKey: "shared_file_paths") ?? []
                list.append(contentsOf: savedPaths)
                defaults.set(list, forKey: "shared_file_paths")
                print("[ShareExt] recorded paths: \(list.count)")
            } else {
                print("[ShareExt] could not open UserDefaults suite")
            }
            completion()
        }
    }

    private func logIncomingUTIs() {
        guard let items = self.extensionContext?.inputItems as? [NSExtensionItem] else { return }
        for (i, item) in items.enumerated() {
            if let providers = item.attachments {
                for (j, p) in providers.enumerated() {
                    print("[ShareExt] item #\(i) provider #\(j) UTIs: \(p.registeredTypeIdentifiers)")
                }
            }
        }
    }

    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        logIncomingUTIs()
        return true
    }

    override func didSelectPost() {
        logIncomingUTIs()
        saveAttachmentsToAppGroup { [weak self] in
            self?.openHostApp()
        }
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }

}
