import SwiftUI

struct VocabularyView: View {
    private enum Mode: String, CaseIterable {
        case pairs = "Соединить пары"
        case written = "Ввести перевод"
    }

    let section: StudySection
    let model: StudyModel
    let backToLesson: () -> Void

    @State private var mode: Mode = .pairs

    var body: some View {
        StudyPage {
            VStack(alignment: .leading, spacing: 10) {
                Text(section.entries.first?.section.title ?? "Словарь")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Карточки")
                    .font(.system(size: 34, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Picker("Режим тренировки", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            switch mode {
            case .pairs:
                VocabularyPairsView(section: section, model: model, backToLesson: backToLesson)
            case .written:
                VocabularyRecallView(section: section, model: model, backToLesson: backToLesson)
            }
        }
    }
}

private struct VocabularyPairsView: View {
    private enum Side { case english, russian }

    private struct Pick: Equatable {
        let id: String
        let side: Side
    }

    private struct Round {
        let cards: [VocabularyCard]
        let translations: [VocabularyCard]
        var selected: Pick?
        var wrong: [Pick] = []
        var matched: Set<String> = []
        var missed: Set<String> = []
        var example: VocabularyCard?

        var finished: Bool { matched.count == cards.count }

        init(cards: [VocabularyCard]) {
            self.cards = cards
            let shuffled = cards.shuffled()
            if cards.count > 1, shuffled.map(\.id) == cards.map(\.id) {
                translations = Array(shuffled.dropFirst()) + [shuffled[0]]
            } else {
                translations = shuffled
            }
        }
    }

    let section: StudySection
    let model: StudyModel
    let backToLesson: () -> Void

    @State private var round: Round?
    @State private var speech = PracticeSpeech()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var items: [VocabularyItem] { model.snapshot.vocabulary[section.id] ?? [] }
    private var activityID: String { "words/\(section.id)/pairs" }
    private var studying: Bool { model.activeStudy?.key == activityID }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Выбери английскую фразу и её русский перевод.")
                .foregroundStyle(.secondary)
            if let round {
                board(round)
                if round.finished {
                    let correct = round.cards.count - round.missed.count
                    Label("Раунд завершён · \(correct) из \(round.cards.count) с первого раза",
                          systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    if !round.missed.isEmpty {
                        Text("Слова, в которых были ошибки, появятся раньше в следующем повторении.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                let due = items.count { $0.isDue(at: .now) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(due > 0 ? "К повторению: \(due)" : "На сегодня всё повторено")
                        .font(.title2.weight(.semibold))
                    Text("В раунде до пяти пар. После совпадения появится пример, который можно прослушать.")
                        .foregroundStyle(.secondary)
                }
                .studyCard()
            }

            controls
        }
        .onChange(of: studying) { _, active in
            if !active { speech.stop() }
        }
        .onDisappear {
            speech.stop()
            model.pauseStudy(activityID: activityID)
        }
    }

    private func board(_ round: Round) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Пары").font(.headline)
                Spacer()
                Text("\(round.matched.count) из \(round.cards.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(round.matched.count), total: Double(round.cards.count))
                .accessibilityLabel("Собрано пар")
            HStack(alignment: .top, spacing: 14) {
                column(round.cards, side: .english, title: "Английский", round: round)
                column(round.translations, side: .russian, title: "Русский", round: round)
            }
            .padding(.top, 2)
            if !round.wrong.isEmpty {
                Label("Эти карточки не совпадают. Попробуй ещё раз.", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            } else if let example = round.example {
                HStack(alignment: .top, spacing: 10) {
                    Button("Прослушать пример", systemImage: "speaker.wave.2") {
                        speech.play(example.example) { model.error = $0 }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(example.example).font(.body.weight(.medium))
                            .environment(\.locale, Locale(identifier: "en_US"))
                        Text(example.exampleTranslation).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ cards: [VocabularyCard], side: Side, title: String, round: Round) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(cards) { card in
                let pick = Pick(id: card.id, side: side)
                let label = side == .english ? card.english : card.russian
                let matched = round.matched.contains(card.id)
                let wrong = round.wrong.contains(pick)
                let selected = round.selected == pick
                let color: Color = matched ? .green : (wrong ? .red : .accentColor)
                let emphasized = matched || wrong || selected
                Button {
                    select(pick)
                } label: {
                    HStack(spacing: 8) {
                        Text(label)
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        if matched {
                            Image(systemName: "checkmark").foregroundStyle(.green)
                        } else if wrong {
                            Image(systemName: "xmark").foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.background.secondary)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(emphasized ? color.opacity(matched ? 0.07 : 0.13) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(emphasized ? color.opacity(0.76) : Color.secondary.opacity(0.26),
                                          lineWidth: emphasized ? 1.5 : 1)
                    }
                    .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(matched)
                .foregroundStyle(matched ? .secondary : .primary)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityValue(matched ? "Пара найдена" : (wrong ? "Не совпадает" : ""))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack {
            VocabularyButton("К уроку", icon: "chevron.left", action: backToLesson)
            Spacer()
            if let round, !round.finished {
                if studying {
                    VocabularyButton("Пауза", icon: "pause") {
                        model.pauseStudy(activityID: activityID)
                    }
                } else {
                    VocabularyButton("Продолжить", icon: "play", primary: true) {
                        model.startVocabulary(in: section, activityID: activityID)
                    }
                }
            } else {
                let title = round == nil ? "Начать раунд" : "Следующий раунд"
                VocabularyButton(title, icon: "arrow.right", primary: true) { startRound() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }

    private func startRound() {
        let cards = vocabularyRoundCards(items, previous: round?.cards ?? [], retry: round?.missed ?? [])
        guard !cards.isEmpty else { return }
        round = Round(cards: cards)
        model.startVocabulary(in: section, activityID: activityID)
    }

    private func select(_ pick: Pick) {
        guard var round, !round.matched.contains(pick.id) else { return }
        model.startVocabulary(in: section, activityID: activityID)
        round.wrong = []
        guard let previous = round.selected, previous.side != pick.side else {
            round.selected = round.selected == pick ? nil : pick
            self.round = round
            return
        }
        round.selected = nil
        if previous.id == pick.id {
            guard model.reviewVocabulary(pick.id, correct: true, in: section,
                                         updateSchedule: !round.missed.contains(pick.id)) else { return }
            round.matched.insert(pick.id)
            round.example = round.cards.first { $0.id == pick.id }
        } else {
            let englishID = pick.side == .english ? pick.id : previous.id
            guard model.reviewVocabulary(englishID, correct: false, in: section,
                                         updateSchedule: !round.missed.contains(englishID)) else { return }
            round.missed.insert(englishID)
            round.wrong = [previous, pick]
            round.example = nil
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.17)) { self.round = round }
        model.playSound(previous.id == pick.id ? .pairCorrect : .pairIncorrect)
        if round.finished { model.pauseStudy(activityID: activityID) }
    }

}

private struct VocabularyRecallView: View {
    private struct Round {
        let initial: [VocabularyCard]
        var queue: [VocabularyCard]
        var index = 0
        var feedback: Bool?
        var missed: Set<String> = []

        init(_ cards: [VocabularyCard]) {
            initial = cards
            queue = cards
        }

        var current: VocabularyCard? { queue.indices.contains(index) ? queue[index] : nil }
        var finished: Bool { current == nil }
    }

    let section: StudySection
    let model: StudyModel
    let backToLesson: () -> Void

    @State private var round: Round?
    @State private var answer = ""
    @State private var speech = PracticeSpeech()
    @FocusState private var answerFocused: Bool

    private var items: [VocabularyItem] { model.snapshot.vocabulary[section.id] ?? [] }
    private var activityID: String { "words/\(section.id)/written" }
    private var studying: Bool { model.activeStudy?.key == activityID }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Вспомни английскую фразу и напечатай её.")
                .foregroundStyle(.secondary)
            if let round, let card = round.current {
                VStack(alignment: .leading, spacing: 12) {
                    let total = round.queue.count
                    Text("Карточка \(round.index + 1) из \(total)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(round.index), total: Double(total))
                        .accessibilityLabel("Прогресс раунда")
                    Text(card.russian)
                        .font(.title.weight(.semibold))
                        .padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)
                    TextField("Перевод на английский", text: $answer)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($answerFocused)
                        .disabled(round.feedback != nil)
                        .onChange(of: answer) { _, value in
                            if !value.trimmed.isEmpty && round.feedback == nil { startTime() }
                        }
                    if let correct = round.feedback {
                        Label(correct ? "Верно" : "Попробуешь ещё раз", systemImage: correct ? "checkmark.circle" : "arrow.counterclockwise")
                            .font(.headline)
                            .foregroundStyle(correct ? .green : .orange)
                        Text(card.english)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        HStack(alignment: .top, spacing: 10) {
                            Button("Прослушать пример", systemImage: "speaker.wave.2") {
                                speech.play(card.example) { model.error = $0 }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.example)
                                Text(card.exampleTranslation).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .studyCard()
            } else if let round {
                Label("Раунд завершён · \(round.initial.count - round.missed.count) из \(round.initial.count) с первого раза",
                      systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                let due = items.count { $0.isDue(at: .now) }
                Text(due > 0 ? "К повторению: \(due)" : "На сегодня всё повторено")
                    .font(.title2.weight(.semibold))
            }
            controls
        }
        .onChange(of: studying) { _, active in
            if !active { speech.stop() }
        }
        .onDisappear {
            speech.stop()
            model.pauseStudy(activityID: activityID)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            VocabularyButton("К уроку", icon: "chevron.left", action: backToLesson)
            Spacer()
            if let round, !round.finished {
                if studying {
                    VocabularyButton("Пауза", icon: "pause") { model.pauseStudy(activityID: activityID) }
                }
                if round.feedback != nil {
                    let title = round.index + 1 == round.queue.count ? "Завершить раунд" : "Дальше"
                    VocabularyButton(title, icon: "arrow.right", primary: true, action: advance)
                        .keyboardShortcut(.defaultAction)
                } else {
                    VocabularyButton("Показать ответ", icon: "eye") { evaluate(reveal: true) }
                    VocabularyButton("Проверить", icon: "checkmark", primary: true) { evaluate(reveal: false) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(answer.trimmed.isEmpty)
                }
            } else {
                let title = round == nil ? "Начать раунд" : "Следующий раунд"
                VocabularyButton(title, icon: "arrow.right", primary: true, action: startRound)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }

    private func startRound() {
        let cards = vocabularyRoundCards(items, previous: round?.initial ?? [], retry: round?.missed ?? [])
        guard !cards.isEmpty else { return }
        round = Round(cards)
        answer = ""
        answerFocused = true
        startTime()
    }

    private func evaluate(reveal: Bool) {
        guard var round, round.feedback == nil, let card = round.current,
              reveal || !answer.trimmed.isEmpty else { return }
        startTime()
        let correct = !reveal && card.accepts(answer)
        let firstPass = round.index < round.initial.count
        guard model.reviewVocabulary(card.id, correct: correct, in: section,
                                     updateSchedule: firstPass, countCheck: !reveal) else { return }
        if firstPass {
            if !correct {
                round.missed.insert(card.id)
                round.queue.append(card)
            }
        }
        round.feedback = correct
        self.round = round
        if !reveal { model.playSound(.answer(correct: correct, translationCard: true)) }
        answerFocused = false
    }

    private func advance() {
        guard var round, round.feedback != nil else { return }
        speech.stop()
        round.index += 1
        round.feedback = nil
        self.round = round
        answer = ""
        answerFocused = !round.finished
        if round.finished {
            model.pauseStudy(activityID: activityID)
        } else {
            startTime()
        }
    }

    private func startTime() {
        model.startVocabulary(in: section, activityID: activityID)
    }
}

private struct VocabularyButton: View {
    let title: String
    let icon: String
    let primary: Bool
    let action: () -> Void

    init(_ title: String, icon: String, primary: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.primary = primary
        self.action = action
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            if primary {
                Button(title, systemImage: icon, action: action).buttonStyle(.glassProminent)
            } else {
                Button(title, systemImage: icon, action: action).buttonStyle(.glass)
            }
        } else if primary {
            Button(title, systemImage: icon, action: action).buttonStyle(.borderedProminent)
        } else {
            Button(title, systemImage: icon, action: action).buttonStyle(.bordered)
        }
    }
}
