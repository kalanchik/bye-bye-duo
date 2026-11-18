import SwiftUI

struct MarkdownText: View {
    let source: String
    private let bodyFont: Font

    init(_ source: String, bodyFont: Font = .body) {
        self.source = source
        self.bodyFont = bodyFont
    }

    var body: some View {
        if let document = try? AttributedString(markdown: source), !document.characters.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(groups(in: document)) { group in
                    if !group.columns.isEmpty {
                        table(group)
                    } else {
                        ForEach(group.blocks) { block in
                            render(block)
                        }
                    }
                }
            }
            .textSelection(.enabled)
        } else {
            Text(source)
                .textSelection(.enabled)
        }
    }

    private func table(_ group: BlockGroup) -> some View {
        let rows = group.blocks.reduce(into: [TableRow]()) { rows, block in
            guard let row = block.tableRow, case let .tableCell(column) = block.kind else { return }
            if rows.last?.id != row.identity {
                rows.append(TableRow(id: row.identity, header: row.kind == .tableHeaderRow))
            }
            rows[rows.count - 1].cells[column] = block.text
        }
        return ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(rows) { row in
                    GridRow {
                        ForEach(group.columns.indices, id: \.self) { column in
                            Text(row.cells[column] ?? AttributedString())
                                .fontWeight(row.header ? .semibold : .regular)
                                .gridColumnAlignment(group.columns[column].horizontalAlignment)
                        }
                    }
                    if row.header {
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
            .padding(10)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        if block.kind == .thematicBreak {
            Divider()
        } else if case .codeBlock = block.kind {
            ScrollView(.horizontal) {
                Text(String(block.text.characters).trimmingCharacters(in: .newlines))
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let marker = block.marker {
                    Text(marker)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(block.text)
                    .font(block.font(body: bodyFont))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(max(0, block.listDepth - 1)) * 18)
            .padding(.leading, block.isQuote ? 12 : 0)
            .overlay(alignment: .leading) {
                if block.isQuote {
                    RoundedRectangle(cornerRadius: 1).fill(.secondary.opacity(0.4)).frame(width: 2)
                }
            }
        }
    }

    private func groups(in document: AttributedString) -> [BlockGroup] {
        var blocks: [Block] = []
        for run in document.runs {
            let components = run.presentationIntent?.components ?? []
            let id = components.first?.identity ?? 0
            var text = AttributedString(document[run.range])
            if run.inlinePresentationIntent?.contains(.code) == true {
                text.font = .system(.body, design: .monospaced)
            }
            if blocks.last?.id == id {
                blocks[blocks.count - 1].text.append(text)
            } else {
                blocks.append(Block(id: id, components: components, text: text))
            }
        }
        var seenItems = Set<Int>()
        return blocks.reduce(into: [BlockGroup]()) { groups, block in
            var block = block
            if let item = block.listItem {
                block.firstInItem = seenItems.insert(item.identity).inserted
            }
            if let table = block.tableID, groups.last?.id == table {
                groups[groups.count - 1].blocks.append(block)
            } else {
                groups.append(BlockGroup(id: block.tableID ?? block.id, columns: block.tableColumns, blocks: [block]))
            }
        }
    }

    private struct BlockGroup: Identifiable {
        let id: Int
        let columns: [PresentationIntent.TableColumn]
        var blocks: [Block]
    }

    private struct TableRow: Identifiable {
        let id: Int
        let header: Bool
        var cells: [Int: AttributedString] = [:]
    }

    private struct Block: Identifiable {
        let id: Int
        let components: [PresentationIntent.IntentType]
        var text: AttributedString
        var firstInItem = false

        var kind: PresentationIntent.Kind? { components.first?.kind }
        var isQuote: Bool { components.contains { $0.kind == .blockQuote } }
        var listDepth: Int { components.filter { $0.kind == .orderedList || $0.kind == .unorderedList }.count }

        var tableID: Int? { table?.identity }

        var tableColumns: [PresentationIntent.TableColumn] {
            if case let .table(columns) = table?.kind { columns } else { [] }
        }

        private var table: PresentationIntent.IntentType? {
            components.first {
                if case .table = $0.kind { true } else { false }
            }
        }

        var tableRow: PresentationIntent.IntentType? {
            components.first {
                switch $0.kind {
                case .tableHeaderRow, .tableRow: true
                default: false
                }
            }
        }

        var listItem: PresentationIntent.IntentType? {
            components.first {
                if case .listItem = $0.kind { true } else { false }
            }
        }

        var marker: String? {
            guard firstInItem, case let .listItem(ordinal) = listItem?.kind else { return nil }
            let list = components.first { $0.kind == .orderedList || $0.kind == .unorderedList }
            return list?.kind == .orderedList ? "\(ordinal)." : "•"
        }

        func font(body: Font) -> Font {
            switch kind {
            case .header(level: 1): .title2.bold()
            case .header(level: 2): .title3.bold()
            case .header: .headline
            default: body
            }
        }
    }
}

private extension PresentationIntent.TableColumn {
    var horizontalAlignment: HorizontalAlignment {
        switch alignment {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        @unknown default: .leading
        }
    }
}
