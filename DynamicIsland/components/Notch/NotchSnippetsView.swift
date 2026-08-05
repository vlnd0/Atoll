/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * The snippets feature is ported from Cyclop
 * <https://github.com/akalikbergenov/cyclop>; see SnippetStore.swift for the
 * MIT notice that covers it.
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
import SwiftUI

/// Pinned pieces of text, kept by hand and copied with one click.
struct NotchSnippetsView: View {
    @ObservedObject private var snippets = SnippetStore.shared

    @State private var isAdding = false
    @State private var draftLabel = ""
    @State private var draftText = ""
    /// Which row was copied last, so the confirmation can be shown on it alone.
    @State private var copiedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            list
        }
        .padding(.horizontal, 4)
        // The file is edited from outside the app as well, so what is in memory
        // is only trustworthy at the moment the tab is opened.
        .onAppear { snippets.reload() }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if isAdding {
            HStack(spacing: 6) {
                TextField("Name (optional)", text: $draftLabel)
                    .textFieldStyle(.plain)
                    .frame(width: 120)
                TextField("Text", text: $draftText)
                    .textFieldStyle(.plain)
                    .onSubmit(commit)
                Spacer(minLength: 0)
                iconButton("checkmark", tint: .green, action: commit)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                iconButton("xmark", action: cancelAdding)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(nsColor: .secondarySystemFill).opacity(0.25)))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                TextField("Search", text: $snippets.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !snippets.query.isEmpty {
                    iconButton("xmark.circle.fill") { snippets.query = "" }
                }
                iconButton("plus") { isAdding = true }
                iconButton("folder") { SnippetStore.reveal() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(nsColor: .secondarySystemFill).opacity(0.25)))
        }
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if snippets.filtered.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 22))
                    .foregroundStyle(.gray)
                Text(snippets.items.isEmpty ? "No snippets yet" : "Nothing matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                if snippets.items.isEmpty {
                    Text("Add one with +, or edit snippets.json")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(snippets.filtered) { item in
                        row(item)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row(_ item: Snippet) -> some View {
        HStack(spacing: 8) {
            Image(systemName: copiedID == item.id ? "checkmark" : item.symbol)
                .font(.system(size: 11))
                .foregroundStyle(copiedID == item.id ? .green : .gray)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                if !item.label.isEmpty {
                    Text(item.label)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                Text(item.text)
                    .font(.system(size: item.label.isEmpty ? 12 : 10))
                    .foregroundStyle(item.label.isEmpty ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            iconButton("trash") { snippets.remove(item) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .secondarySystemFill).opacity(0.18))
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture { copy(item) }
        .help(item.text)
    }

    // MARK: - Bits

    private func iconButton(_ symbol: String, tint: Color = .gray, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copy(_ item: Snippet) {
        snippets.copy(item)
        withAnimation(.smooth(duration: 0.15)) { copiedID = item.id }
        // Long enough to register, short enough not to linger over the next click.
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                withAnimation(.smooth(duration: 0.15)) {
                    if copiedID == item.id { copiedID = nil }
                }
            }
        }
    }

    private func commit() {
        snippets.add(label: draftLabel, text: draftText)
        cancelAdding()
    }

    private func cancelAdding() {
        isAdding = false
        draftLabel = ""
        draftText = ""
    }
}
