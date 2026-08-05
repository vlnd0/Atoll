/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Ported from Cyclop <https://github.com/akalikbergenov/cyclop>, MIT licensed:
 *
 *   Copyright (c) 2026 Adil Kalikbergenov
 *
 *   Permission is hereby granted, free of charge, to any person obtaining a copy
 *   of this software and associated documentation files (the "Software"), to deal
 *   in the Software without restriction, including without limitation the rights
 *   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *   copies of the Software, and to permit persons to whom the Software is
 *   furnished to do so, subject to the following conditions:
 *
 *   The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 *   SOFTWARE.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Translation

/// Apple's on-device translator, driven from the notch.
///
/// The session is not ours to create: `translationTask` hands one over and owns
/// its lifetime, so everything here is about deciding *what* to translate and
/// holding the result. `NotchTranslateView` supplies the session.
///
/// Nothing leaves the machine — the framework translates locally from a language
/// pack macOS downloads once.
@available(macOS 15.0, *)
@MainActor
final class Translator: ObservableObject {
    static let shared = Translator()

    static let russian = Locale.Language(identifier: "ru")
    static let english = Locale.Language(identifier: "en")

    /// Both ends are always named. Leaving the source to the framework looks
    /// tempting, but its identifier is a separate asset that is not installed
    /// either — auto-detection fails with `unableToIdentifyLanguage`, and the
    /// translation that follows hangs instead of returning an error.
    struct Route: Equatable {
        var source: Locale.Language
        var target: Locale.Language
    }

    /// Keyed by the view's debounced task. The counter is what makes a retry of
    /// unchanged text a new request rather than a no-op.
    struct Request: Equatable {
        var text: String
        var attempt: Int
    }

    @Published var input = ""
    @Published private(set) var output = ""
    @Published private(set) var failure: String?
    /// The failure is a missing language pack, which is something the user can go
    /// and fix — so the view offers the button that takes them there.
    @Published private(set) var needsDownload = false
    @Published private(set) var isTranslating = false

    private var attempt = 0

    private init() {}

    var request: Request { Request(text: input, attempt: attempt) }
    var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    var route: Route { Self.route(for: trimmed) }

    /// Russian goes out to English, everything else comes in to Russian.
    ///
    /// Decided by script rather than by language detection: a single word is far
    /// too short to identify reliably, and "привет" comes back as Bulgarian often
    /// enough to matter.
    static func route(for text: String) -> Route {
        let cyrillic = text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
        return cyrillic
            ? Route(source: russian, target: english)
            : Route(source: english, target: russian)
    }

    func retry() { attempt += 1 }

    func clear() {
        output = ""
        failure = nil
        needsDownload = false
        isTranslating = false
    }

    func reset() {
        input = ""
        clear()
    }

    func run(_ session: TranslationSession) async {
        let text = trimmed
        guard !text.isEmpty else { clear(); return }
        guard let source = session.sourceLanguage, let target = session.targetLanguage else { return }

        isTranslating = true
        defer { isTranslating = false }

        // No language pack ships installed. `prepareTranslation()` is what asks
        // for one, but it blocks until its system prompt is answered — and that
        // prompt has nowhere to appear over a borderless panel of an app that
        // never activates, so it would hang forever. Check instead, and send the
        // user to the one place that can actually install it.
        let status = await LanguageAvailability().status(from: source, to: target)
        guard status == .installed else {
            output = ""
            needsDownload = status == .supported
            failure = needsDownload
                ? String(format: String(localized: "The %@ → %@ language pack is not installed."),
                         Self.name(source), Self.name(target))
                : String(localized: "macOS does not translate this pair of languages.")
            return
        }

        do {
            let response = try await session.translate(text)
            guard !Task.isCancelled else { return }
            output = response.targetText
            failure = nil
            needsDownload = false
        } catch {
            guard !Task.isCancelled else { return }
            output = ""
            needsDownload = false
            failure = error.localizedDescription
        }
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
    }

    /// Takes whatever is on the pasteboard as the text to translate — the common
    /// case is something just copied from somewhere else.
    func pasteInput() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        input = text
    }

    /// "Русский", "English" — for the column headers.
    static func name(_ language: Locale.Language) -> String {
        guard let code = language.languageCode?.identifier,
              let name = Locale.current.localizedString(forLanguageCode: code) else {
            return language.languageCode?.identifier.uppercased() ?? "?"
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Short code for the header badge — "EN → RU" reads at a glance where a
    /// spelled-out name would not fit in the strip.
    static func code(_ language: Locale.Language) -> String {
        language.languageCode?.identifier.uppercased() ?? "?"
    }

    /// System Settings → General → Language & Region, which is where the
    /// "Translation Languages…" button lives.
    static func openLanguageSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
