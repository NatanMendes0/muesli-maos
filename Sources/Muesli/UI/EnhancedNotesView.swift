import SwiftUI

struct EnhancedNotesView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var settings: AppSettings
    let meetingID: UUID
    let enhancing: Bool
    let onEnhance: () -> Void
    var onSwitchToCopilot: (() -> Void)?

    private var meeting: Meeting? { store.meeting(meetingID) }

    var body: some View {
        if enhancing {
            VStack(spacing: 12) {
                ProgressView()
                Text("Combinando suas anotações com a transcrição…")
                    .foregroundStyle(CoastalTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CoastalTheme.surface)
        } else if let md = meeting?.enhancedMD {
            ScrollView {
                MarkdownView(markdown: md
                    .replacingOccurrences(of: "TL;DR:", with: "## Resumo\n")
                    .replacingOccurrences(of: "TL;DR", with: "Resumo")
                    .replacingOccurrences(of: "TLDR", with: "Resumo"))
                    .padding(22)
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .background(CoastalTheme.surface)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(CoastalTheme.accent)
                Text("Transforme suas anotações em uma ata estruturada")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CoastalTheme.text)
                Text("O Muesli combina o que você anotou com a transcrição —\ndecisões, contexto técnico e plano de ação.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CoastalTheme.secondaryText)
                    .font(.system(size: 13))

                HStack(spacing: 10) {
                    Button(action: onEnhance) {
                        Label(settings.hasAIConfigured ? "Aprimorar com IA" : "Configurar IA", systemImage: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CoastalTheme.btnInkFg)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(CoastalTheme.btnInkBg, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(settings.hasAIConfigured && !(meeting?.hasTranscript ?? false) && (meeting?.notesMD.isEmpty ?? true))

                    if let onSwitchToCopilot {
                        Button("Usar Copilot (sem chave)", action: onSwitchToCopilot)
                            .buttonStyle(.plain)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(CoastalTheme.infoFg)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(CoastalTheme.infoBg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CoastalTheme.infoBorder, lineWidth: 1))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(CoastalTheme.surface)
        }
    }
}

/// Dependency-free Markdown renderer with headings, lists, checkboxes, quotes, and tables.
struct MarkdownView: View {
    let markdown: String

    private enum Block: Identifiable {
        case heading(Int, String)
        case bullet(String, checked: Bool?)
        case numbered(Int, String)
        case quote(String)
        case table([[String]])
        case rule
        case paragraph(String)

        var id: UUID { UUID() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parse()) { block in
                render(block)
            }
        }
        .foregroundStyle(CoastalTheme.bodyText)
        .textSelection(.enabled)
    }

    private func parse() -> [Block] {
        var blocks: [Block] = []
        let rawLines = markdown.components(separatedBy: "\n")
        var idx = 0
        while idx < rawLines.count {
            let line = rawLines[idx].trimmingCharacters(in: .whitespaces)
            idx += 1
            if line.isEmpty { continue }

            // Markdown table detection
            if line.hasPrefix("|") && line.hasSuffix("|") {
                var tableRows: [[String]] = []
                let firstCells = parseTableRow(line)
                if !firstCells.isEmpty { tableRows.append(firstCells) }
                while idx < rawLines.count {
                    let next = rawLines[idx].trimmingCharacters(in: .whitespaces)
                    if next.hasPrefix("|") && next.hasSuffix("|") {
                        idx += 1
                        if isSeparatorRow(next) { continue }
                        let cells = parseTableRow(next)
                        if !cells.isEmpty { tableRows.append(cells) }
                    } else {
                        break
                    }
                }
                if !tableRows.isEmpty {
                    blocks.append(.table(tableRows))
                    continue
                }
            }

            if line == "---" || line == "***" {
                blocks.append(.rule)
            } else if line.hasPrefix("### ") {
                blocks.append(.heading(3, localizedHeading(String(line.dropFirst(4)))))
            } else if line.hasPrefix("## ") {
                blocks.append(.heading(2, localizedHeading(String(line.dropFirst(3)))))
            } else if line.hasPrefix("# ") {
                blocks.append(.heading(1, localizedHeading(String(line.dropFirst(2)))))
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("* [ ] ") {
                blocks.append(.bullet(String(line.dropFirst(6)), checked: false))
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") || line.hasPrefix("* [x] ") {
                blocks.append(.bullet(String(line.dropFirst(6)), checked: true))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(String(line.dropFirst(2)), checked: nil))
            } else if line.hasPrefix("> ") {
                blocks.append(.quote(String(line.dropFirst(2))))
            } else if let (n, rest) = MarkdownView.numberedPrefix(line) {
                blocks.append(.numbered(n, rest))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        return blocks
    }

    private func parseTableRow(_ line: String) -> [String] {
        let inner = line.dropFirst().dropLast()
        return inner.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func isSeparatorRow(_ line: String) -> Bool {
        let cleaned = line.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty
    }

    private func localizedHeading(_ text: String) -> String {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "TL;DR", "TLDR": return "Resumo"
        default: return text
        }
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            styled(text)
                .font(level == 1 ? .title2.weight(.bold) : level == 2 ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(CoastalTheme.text)
                .padding(.top, level == 1 ? 2 : 8)
        case .bullet(let text, let checked):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let checked {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? CoastalTheme.ok : CoastalTheme.accent)
                } else {
                    Text("•").foregroundStyle(CoastalTheme.accent)
                }
                styled(text)
            }
            .padding(.leading, 4)
        case .numbered(let n, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).")
                    .foregroundStyle(CoastalTheme.secondaryText)
                    .monospacedDigit()
                styled(text)
            }
            .padding(.leading, 4)
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(CoastalTheme.accent.opacity(0.6))
                    .frame(width: 3)
                styled(text)
                    .foregroundStyle(CoastalTheme.secondaryText)
                    .italic()
            }
        case .table(let rows):
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { cIdx, cell in
                            styled(cell)
                                .font(.system(size: 12.5, weight: rIdx == 0 ? .semibold : .regular))
                                .foregroundStyle(rIdx == 0 ? CoastalTheme.text : CoastalTheme.bodyText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                            if cIdx < row.count - 1 {
                                Rectangle().fill(CoastalTheme.separator).frame(width: 1)
                            }
                        }
                    }
                    .background(rIdx == 0 ? CoastalTheme.surfaceSoft : CoastalTheme.surface)
                    if rIdx < rows.count - 1 {
                        Rectangle().fill(CoastalTheme.separator).frame(height: 1)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CoastalTheme.separator, lineWidth: 1))
        case .rule:
            Divider()
        case .paragraph(let text):
            styled(text)
        }
    }

    static func numberedPrefix(_ line: String) -> (Int, String)? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let head = line[line.startIndex..<dot]
        guard !head.isEmpty, head.count <= 3, head.allSatisfy(\.isNumber), let n = Int(head) else { return nil }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        let rest = line[line.index(after: afterDot)...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (n, rest)
    }

    private func styled(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}
