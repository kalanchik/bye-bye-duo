import SwiftUI

struct TranslationCardView: View {
    let exercise: Exercise
    @Binding var answer: String
    let feedback: Feedback?
    let check: (() -> Void)?

    var body: some View {
        let tint = feedback.map { $0.correct ? PlanStyle.success : Color(.setupErrorText) }
        let shape = RoundedRectangle(cornerRadius: 20)
        VStack(spacing: 14) {
            if let front = exercise.translationCardFront {
                ZStack(alignment: .top) {
                    ForEach([0, 17], id: \.self) { offset in
                        shape.fill(PlanStyle.card)
                            .overlay { shape.strokeBorder(PlanStyle.border) }
                            .frame(height: 300)
                            .offset(y: CGFloat(offset))
                            .accessibilityHidden(true)
                    }
                    Text(feedback == nil ? front : exercise.acceptedAnswers?.first ?? answer)
                        .font(PlanStyle.prompt)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(tint ?? PlanStyle.text)
                        .padding(20)
                        .frame(maxWidth: .infinity, minHeight: 300)
                        .background(feedback.map { $0.correct ? PlanStyle.successBackground : Color(.setupErrorBackground) } ?? PlanStyle.card, in: shape)
                        .overlay { shape.strokeBorder(tint ?? PlanStyle.border) }
                        .padding(.top, 34)
                }
                .frame(maxWidth: 300)
                .padding(.top, 16)
            } else {
                // A legacy writing task may have no unambiguous short translation target.
                MarkdownText(exercise.prompt).font(PlanStyle.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                TextField("Напиши перевод", text: $answer)
                    .textFieldStyle(.plain).font(PlanStyle.answer)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 300, minHeight: 54)
                    .modifier(TranslationInputBorder())
                    .onSubmit { if !answer.trimmed.isEmpty { check?() } }
                if let check, feedback == nil {
                    Button(action: check) {
                        Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.system(size: 26)).foregroundStyle(PlanStyle.secondary)
                            .frame(width: 54, height: 54)
                            .modifier(TranslationInputBorder())
                    }
                    .buttonStyle(.plain)
                    .disabled(answer.trimmed.isEmpty)
                    .accessibilityLabel("Проверить перевод")
                    .help("Проверить перевод")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TranslationInputBorder: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        content.background(PlanStyle.card, in: shape)
            .overlay { shape.strokeBorder(PlanStyle.action, lineWidth: 2).allowsHitTesting(false) }
    }
}

struct TranslationPairsView: View {
    let pairs: [Exercise.TranslationPair]
    let selection: TranslationPairSelection
    let checked: Bool
    let select: (TranslationPairSelection.Pick) -> Void

    // Keep the order stable when reopening a draft, including for an already alphabetized word list.
    private var englishOrder: [Int] {
        let order = pairs.indices.sorted { pairs[$0].english.localizedCaseInsensitiveCompare(pairs[$1].english) == .orderedAscending }
        return order.elementsEqual(pairs.indices) ? Array(order.dropFirst()) + order.prefix(1) : order
    }

    var body: some View {
        let order = englishOrder
        Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(pairs.indices, id: \.self) { index in
                GridRow {
                    tile(.init(index: index, side: .russian), text: pairs[index].russian)
                    tile(.init(index: order[index], side: .english), text: pairs[order[index]].english)
                }
            }
        }
    }

    private func tile(_ pick: TranslationPairSelection.Pick, text: String) -> some View {
        let partner = selection.partner(of: pick)
        let selected = selection.pending == pick
        let result = checked ? partner.map { $0 == pick.index } : nil
        let tint = result.map { $0 ? PlanStyle.success : Color(.setupErrorText) }
        let fill = result.map { $0 ? PlanStyle.successBackground : Color(.setupErrorBackground) }
        let shape = RoundedRectangle(cornerRadius: 16)
        let counterpart = partner.flatMap { index in
            pairs.indices.contains(index) ? (pick.side == .russian ? pairs[index].english : pairs[index].russian) : nil
        }
        return Button { select(pick) } label: {
            HStack {
                Text(text).font(PlanStyle.answer).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let result { Image(systemName: result ? "checkmark" : "xmark") }
            }
            .foregroundStyle(tint ?? (partner == nil ? PlanStyle.text : PlanStyle.secondary))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(fill ?? (selected ? PlanStyle.soft : partner == nil ? PlanStyle.card : PlanStyle.subtle), in: shape)
            .overlay { shape.strokeBorder(tint ?? (selected ? PlanStyle.action : PlanStyle.connector),
                                          lineWidth: selected || partner != nil ? 2 : 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(counterpart.map { "В паре с «\($0)»" } ?? "")
        .help(counterpart.map { checked ? "В паре с «\($0)»" : "В паре с «\($0)». Нажми, чтобы изменить пару." } ?? "Выбери слово")
    }
}

struct TranslationTilesView: View {
    let words: [String]
    let selected: [Int]
    let feedback: Feedback?
    let update: ([Int]) -> Void

    private enum Slot: Hashable { case answer, bank, word(Int) }
    private struct Drag {
        let index: Int
        let value: DragGesture.Value
    }
    @Namespace private var space
    @State private var frames: [Slot: CGRect] = [:]
    @GestureState private var drag: Drag?

    var body: some View {
        VStack(spacing: 14) {
            WordRows(centered: false, rowSpacing: 12) {
                ForEach(selected, id: \.self) { index in
                    tile(index, inAnswer: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .background { rules }
            .background { measure(.answer) }
            WordRows(centered: true, rowSpacing: 2) {
                ForEach(words.indices, id: \.self) { index in
                    if selected.contains(index) {
                        chip(index, placeholder: true).frame(minHeight: 44, alignment: .top)
                            .accessibilityHidden(true)
                    } else {
                        tile(index, inAnswer: false)
                    }
                }
            }
            .background { measure(.bank) }
        }
        .coordinateSpace(name: space)
        .overlay(alignment: .topLeading) {
            if let drag, let frame = frames[.word(drag.index)] {
                chip(drag.index)
                    .frame(width: frame.width)
                    .position(x: frame.midX + drag.value.translation.width, y: frame.midY + drag.value.translation.height)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    private var rules: some View {
        Canvas { context, size in
            let origin = frames[.answer]?.minY ?? 0
            let bottoms = Set(selected.compactMap { frames[.word($0)]?.maxY }.map { ($0 - origin).rounded() })
            var lines = bottoms.isEmpty ? Set([CGFloat(44)]) : bottoms
            if lines.count == 1 { lines.insert(max(100, (lines.max() ?? 44) + 56)) }
            var path = Path()
            for y in lines {
                path.move(to: CGPoint(x: 0, y: min(y, size.height) - 0.5))
                path.addLine(to: CGPoint(x: size.width, y: min(y, size.height) - 0.5))
            }
            context.stroke(path, with: .color(PlanStyle.connector), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func measure(_ slot: Slot) -> some View {
        let coordinateSpace = space
        return Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(coordinateSpace)) } action: {
            frames[slot] = $0
        }
    }

    private func chip(_ index: Int, placeholder: Bool = false, inAnswer: Bool = false) -> some View {
        let result = inAnswer ? feedback : nil
        let color = result.map { $0.correct ? PlanStyle.success : Color(.setupErrorText) }
        let shape = RoundedRectangle(cornerRadius: 12)
        return Text(words[index]).font(PlanStyle.label)
            .foregroundStyle(placeholder ? .clear : color ?? PlanStyle.text)
            .padding(.horizontal, 13).padding(.vertical, 7).frame(minHeight: 38)
            .background(placeholder ? PlanStyle.subtle : PlanStyle.card, in: shape)
            .overlay { if !placeholder { shape.strokeBorder(color ?? PlanStyle.border) } }
    }

    private func tile(_ index: Int, inAnswer: Bool) -> some View {
        Button {
            update(inAnswer ? selected.filter { $0 != index } : selected + [index])
        } label: {
            chip(index, placeholder: drag?.index == index, inAnswer: inAnswer)
                .frame(minHeight: 44, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background { measure(.word(index)) }
        .highPriorityGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
            .updating($drag) { value, state, _ in state = Drag(index: index, value: value) }
            .onEnded { value in drop(index, at: value.location) })
        .accessibilityLabel(words[index])
        .accessibilityHint(inAnswer ? "Убрать из ответа" : "Добавить в ответ")
    }

    private func drop(_ index: Int, at point: CGPoint) {
        guard feedback == nil else { return }
        var order = selected.filter { $0 != index }
        if frames[.answer]?.contains(point) == true {
            let position = order.firstIndex { other in
                guard let frame = frames[.word(other)] else { return false }
                return point.y < frame.minY || (point.y <= frame.maxY && point.x < frame.midX)
            }
            order.insert(index, at: position ?? order.endIndex)
        } else if frames[.bank]?.contains(point) != true {
            return
        }
        if order != selected { update(order) }
    }
}

struct WordRows: Layout {
    let centered: Bool
    let rowSpacing: CGFloat

    private func rows(width: CGFloat, subviews: Subviews) -> [[CGRect]] {
        var rows: [[CGRect]] = []
        var row: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: min(width, view.sizeThatFits(.unspecified).width), height: nil))
            if !row.isEmpty, x + size.width > width {
                rows.append(row)
                y = (row.map(\.maxY).max() ?? y) + rowSpacing
                row = []
                x = 0
            }
            row.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + 8
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width + 8 }
        return CGSize(width: width, height: rows(width: width, subviews: subviews).last?.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var index = 0
        for row in rows(width: bounds.width, subviews: subviews) {
            let offset = centered ? (bounds.width - (row.last?.maxX ?? 0)) / 2 : 0
            for frame in row {
                subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX + offset, y: bounds.minY + frame.minY),
                                      anchor: .topLeading, proposal: ProposedViewSize(frame.size))
                index += 1
            }
        }
    }
}
