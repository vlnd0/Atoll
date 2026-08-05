/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * The translate feature is ported from Cyclop
 * <https://github.com/akalikbergenov/cyclop>; see Translator.swift for the MIT
 * notice that covers it.
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

import SwiftUI
import Translation

/// Offline translation, English ↔ Russian, in two columns.
///
/// The direction is chosen from the script of what is typed rather than offered
/// as a control: there are only two languages here, and picking between them by
/// hand is a step that the text itself already answers.
@available(macOS 15.0, *)
struct NotchTranslateView: View {
    @ObservedObject private var translator = Translator.shared

    @State private var configuration: TranslationSession.Configuration?
    @FocusState private var inputFocused: Bool

    /// Long enough that typing a word does not fire a translation per keystroke,
    /// short enough that stopping feels like it answered at once.
    private let debounce = Duration.milliseconds(350)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            source
            divider
            result
        }
        .padding(.horizontal, 4)
        .onAppear { inputFocused = true }
        // A new configuration is what starts a session; reusing one would keep
        // translating in the direction the first phrase happened to pick.
        .task(id: translator.request) {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let route = translator.route
            guard !translator.trimmed.isEmpty else {
                translator.clear()
                configuration = nil
                return
            }
            configuration = TranslationSession.Configuration(source: route.source, target: route.target)
        }
        .translationTask(configuration) { session in
            await translator.run(session)
        }
    }

    // MARK: - Left column

    private var source: some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeader(Translator.code(translator.route.source)) {
                iconButton("doc.on.clipboard", help: "Paste") { translator.pasteInput() }
                if !translator.input.isEmpty {
                    iconButton("xmark.circle.fill", help: "Clear") { translator.reset() }
                }
            }

            TextEditor(text: $translator.input)
                .focused($inputFocused)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .secondarySystemFill).opacity(0.18))
                )
                .overlay(alignment: .topLeading) {
                    if translator.input.isEmpty {
                        Text("Type or paste to translate")
                            .font(.system(size: 13))
                            .foregroundStyle(.gray)
                            .padding(.top, 8)
                            .padding(.leading, 6)
                            .allowsHitTesting(false)
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        VStack {
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.gray)
                .padding(.top, 2)
            Spacer()
        }
    }

    // MARK: - Right column

    private var result: some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeader(Translator.code(translator.route.target)) {
                if translator.isTranslating {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                }
                if !translator.output.isEmpty {
                    iconButton("doc.on.doc", help: "Copy") { translator.copyOutput() }
                }
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .secondarySystemFill).opacity(0.18))

                if let failure = translator.failure {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(failure)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if translator.needsDownload {
                                Button("Open Language Settings") { Translator.openLanguageSettings() }
                                    .buttonStyle(.link)
                                    .font(.system(size: 11))
                            }
                            Button("Retry") { translator.retry() }
                                .buttonStyle(.link)
                                .font(.system(size: 11))
                        }
                    }
                    .padding(8)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(translator.output)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bits

    private func columnHeader<Trailing: View>(
        _ code: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 6) {
            Text(code)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.gray)
            Spacer(minLength: 0)
            trailing()
        }
        .frame(height: 14)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
