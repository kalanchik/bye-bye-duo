import Foundation

nonisolated enum DemoCourse {
    static var entries: [CourseEntry] {
        let module = CourseModule(
            id: "present-tenses",
            title: "Настоящее время",
            theory: """
            | Время | Когда используем | Пример |
            | --- | --- | --- |
            | **Present Simple** | Привычки и факты | *I work from home on Fridays.* |
            | **Present Continuous** | Действие сейчас или временная ситуация | *I’m working from home today.* |
            """
        )
        let simple = CourseSection(
            id: "present-simple",
            title: "Present Simple",
            theory: """
            С **he, she, it** в утверждении добавляем к глаголу **-s** или **-es**. В вопросах и отрицаниях эту роль берёт на себя **does**, поэтому основной глагол возвращается к начальной форме.

            *She works from home. Does she work from home? She doesn’t work from home.*
            """
        )
        let continuous = CourseSection(
            id: "present-continuous",
            title: "Present Continuous",
            theory: """
            Для действия в процессе используем **am / is / are + глагол с -ing**. Для вопроса ставим **am / is / are** перед подлежащим.

            *She is working now. Is she working now?*
            """
        )
        let contrast = CourseSection(
            id: "present-contrast",
            title: "Simple или Continuous?",
            theory: """
            Сначала реши, о чём речь: о привычке или о текущей ситуации.

            *I usually take the bus, but today I’m walking.*
            """
        )
        return [
            CourseEntry(module: module, section: simple, lesson: Lesson(
                id: "simple-practice", title: "Привычки и факты", kind: .lesson,
                theory: "Потренируй две формы: **she works** и **does she work**.", estimatedMinutes: 5,
                timeLimitMinutes: nil, exercises: [
                    Exercise(id: "fridays", kind: .gap, prompt: "She ___ (work) from home on Fridays.",
                             options: nil, acceptedAnswers: ["works"],
                             explanation: "В утверждении после she к work добавляем -s.", rubric: nil, topic: "Третье лицо"),
                    Exercise(id: "does", kind: .correction, prompt: "Does she works from home on Fridays?",
                             options: nil, acceptedAnswers: ["Does she work from home on Fridays?"],
                             explanation: "После does ставим начальную форму work.", rubric: nil, topic: "Вопросы с does")
                ]
            )),
            CourseEntry(module: module, section: continuous, lesson: Lesson(
                id: "continuous-practice", title: "Что происходит сейчас", kind: .lesson,
                theory: "Обрати внимание на вспомогательный глагол в каждом предложении.", estimatedMinutes: 5,
                timeLimitMinutes: nil, exercises: [
                    Exercise(id: "call", kind: .choice, prompt: "I can’t talk right now. I ___ dinner.",
                             options: ["cook", "am cooking"], acceptedAnswers: ["am cooking"],
                             explanation: "Готовка идёт прямо сейчас, поэтому I am cooking.", rubric: nil, topic: "Действие сейчас"),
                    Exercise(id: "listen", kind: .gap, prompt: "They ___ (listen) to the teacher now.",
                             options: nil, acceptedAnswers: ["are listening"],
                             explanation: "После they используем are, затем listening.", rubric: nil, topic: "Форма am / is / are")
                ]
            )),
            CourseEntry(module: module, section: contrast, lesson: Lesson(
                id: "present-homework", title: "Обычный день и сегодня", kind: .homework,
                theory: "В этой работе ты сравнишь привычки с временными изменениями в своём расписании.", estimatedMinutes: 10,
                timeLimitMinutes: 10, exercises: [
                    Exercise(id: "today", kind: .choice, prompt: "I usually take the bus, but today I ___ to work.",
                             options: ["walk", "am walking"], acceptedAnswers: ["am walking"],
                             explanation: "Today здесь описывает временное отклонение от привычки.", rubric: nil, topic: "Выбор времени"),
                    Exercise(id: "routine", kind: .written, prompt: "Напиши 3–4 предложения по-английски. Чем ты обычно занимаешься утром и что делаешь иначе сегодня?",
                             options: nil, acceptedAnswers: nil, explanation: nil,
                             rubric: "Use Present Simple for a routine and Present Continuous for a temporary change.", topic: "Распорядок дня"),
                    Exercise(id: "chat", kind: .dialogue, prompt: "Ответь на два сообщения коллеги по-английски.\n\n1. What do you usually do on Fridays?\n2. What are you working on right now?",
                             options: nil, acceptedAnswers: nil, explanation: nil,
                             rubric: "Give two relevant replies, with Present Simple in the first and Present Continuous in the second.", topic: "Диалог с коллегой")
                ]
            ))
        ]
    }
}

extension DemoCourse {
    nonisolated static var followUpEntries: [CourseEntry] {
        let basics = entries
        return [
            CourseEntry(module: basics[0].module, section: basics[0].section, lesson: Lesson(
                id: "simple-listening-beginner", title: "Present Simple на слух", kind: .lesson,
                theory: """
                Нажми **«Прослушать»**. Сначала попробуй уловить знакомое слово, затем послушай ещё раз и выбери ответ.

                **Слова:** *tea* — чай, *coffee* — кофе, *read* — читать, *work* — работать, *home* — дом.

                После проверки посмотри текст фразы. Прослушай её ещё раз и повтори вслух.
                """,
                estimatedMinutes: 8, timeLimitMinutes: nil, exercises: [
                    listening("tea", "Что человек пьёт утром?", "I drink tea in the morning.",
                              ["Чай", "Кофе"], "Чай", "**Tea** — чай."),
                    listening("home", "Где она работает?", "She works from home.",
                              ["В офисе", "Дома"], "Дома", "**From home** здесь значит «из дома»."),
                    listening("read", "Что человек делает вечером?", "I read in the evening.",
                              ["Читает", "Работает"], "Читает", "**Read** — читать."),
                    listening("question", "О чём спрашивает собеседник?", "Do you like coffee?",
                              ["Любишь ли ты кофе?", "Работаешь ли ты дома?"], "Любишь ли ты кофе?",
                              "**Do you like…?** — «Тебе нравится…?»")
                ]
            )),
            checkpoint(for: basics[0], id: "present-simple-checkpoint", title: "Контрольная · Present Simple", exercises: [
                choice("we", "Мы читаем каждый день. **We ___ every day.**",
                       ["reads", "read"], "read", "С **we** говорим **read**.", "Третье лицо"),
                choice("he", "Он работает дома. **He ___ from home.**",
                       ["work", "works"], "works", "С **he** в утверждении добавляем **-s**.", "Третье лицо"),
                choice("negative", "Она не пьёт кофе. **She ___ drink coffee.**",
                       ["doesn’t", "don’t"], "doesn’t", "В отрицании с **she** используем **doesn’t**.", "Отрицания с does"),
                listening("hear", "Что она делает по пятницам?", "She reads on Fridays.",
                          ["Работает", "Читает"], "Читает", "Слово **reads** значит «читает»."),
                Exercise(id: "reply", kind: .dialogue, prompt: "Ответь по-английски на вопрос **Do you read every day?** Подойдёт короткий ответ.",
                         options: nil, acceptedAnswers: nil, explanation: nil,
                         rubric: "Accept Yes, I do; No, I don't; or a grammatical relevant first-person answer. Ignore minor punctuation and capitalization.",
                         topic: "Короткие ответы")
            ]),
            checkpoint(for: basics[1], id: "present-continuous-checkpoint", title: "Контрольная · Present Continuous", exercises: [
                choice("am", "Я сейчас читаю. **I ___ reading now.**", ["am", "is"], "am",
                       "С **I** употребляем **am**.", "Форма am / is / are"),
                choice("are", "Они сейчас работают. **They ___ working now.**", ["is", "are"], "are",
                       "С **they** употребляем **are**.", "Форма am / is / are"),
                choice("ing", "Она сейчас слушает. **She is ___ now.**", ["listen", "listening"], "listening",
                       "После **is** в этой форме нужен глагол с **-ing**.", "Форма с -ing"),
                choice("question", "Выбери вопрос «Ты сейчас работаешь?»", ["Are you working now?", "You are working now."],
                       "Are you working now?", "В вопросе **are** ставим перед **you**.", "Вопросы в Continuous"),
                listening("hear", "Что он делает прямо сейчас?", "He is cooking dinner right now.",
                          ["Готовит ужин", "Читает книгу"], "Готовит ужин", "**Cooking dinner** — «готовит ужин».")
            ] + continuousCheckpointPractice),
            checkpoint(for: basics[2], id: "present-contrast-checkpoint", title: "Контрольная · Два настоящих времени", exercises: [
                choice("habit", "Она читает каждый день. **She ___ every day.**", ["reads", "is reading"], "reads",
                       "**Every day** описывает привычку. Здесь подходит Present Simple.", "Выбор времени"),
                choice("now", "Он готовит прямо сейчас. **He ___ right now.**", ["cooks", "is cooking"], "is cooking",
                       "**Right now** описывает действие в процессе. Здесь подходит Present Continuous.", "Выбор времени"),
                choice("usually", "Мы обычно ездим на автобусе. **We usually ___ the bus.**", ["take", "are taking"], "take",
                       "Привычку выражаем Present Simple: **we take**.", "Выбор времени"),
                listening("hear", "Фраза говорит о привычке или о том, что происходит прямо сейчас?",
                          "They are watching TV right now.", ["О привычке", "О том, что происходит сейчас"],
                          "О том, что происходит сейчас", "**Are watching** и **right now** указывают на действие сейчас."),
                Exercise(id: "contrast", kind: .written, prompt: "Напиши два коротких предложения. Что ты обычно делаешь утром? Что ты делаешь сейчас?",
                         options: nil, acceptedAnswers: nil, explanation: nil,
                         rubric: "Accept two brief relevant statements using Present Simple for a habit and Present Continuous for a current action. Ignore minor punctuation and capitalization.",
                         topic: "Выбор времени")
            ])
        ]
    }

    private nonisolated static func checkpoint(
        for entry: CourseEntry, id: String, title: String, exercises: [Exercise]
    ) -> CourseEntry {
        CourseEntry(module: entry.module, section: entry.section, lesson: Lesson(
            id: id, title: title, kind: .lesson,
            theory: "Выполни задания самостоятельно. После проверки ты увидишь разбор и сможешь пересдать работу.",
            estimatedMinutes: exercises.count >= 20 ? 25 : 10, timeLimitMinutes: nil, exercises: exercises, passingPercent: 80
        ))
    }

    private nonisolated static func choice(
        _ id: String, _ prompt: String, _ options: [String], _ answer: String, _ explanation: String, _ topic: String
    ) -> Exercise {
        Exercise(id: id, kind: .choice, prompt: prompt, options: options, acceptedAnswers: [answer],
                 explanation: explanation, rubric: nil, topic: topic)
    }

    private nonisolated static func listening(
        _ id: String, _ prompt: String, _ speechText: String, _ options: [String], _ answer: String, _ explanation: String
    ) -> Exercise {
        Exercise(id: id, kind: .choice, prompt: prompt, options: options, acceptedAnswers: [answer],
                 explanation: explanation, rubric: nil, topic: "Понимание на слух", speechText: speechText)
    }
}

extension DemoCourse {
    nonisolated static var vocabulary: [String: [VocabularyCard]] {
        [
            "present-simple": cards([
                ("every-day", "every day", "каждый день", "I read every day.", "Я читаю каждый день."),
                ("in-the-morning", "in the morning", "утром", "I drink tea in the morning.", "Я пью чай утром."),
                ("from-home", "from home", "из дома (о работе)", "I work from home on Fridays.", "Я работаю из дома по пятницам."),
                ("on-fridays", "on Fridays", "по пятницам", "She reads on Fridays.", "Она читает по пятницам."),
                ("read-a-book", "read a book", "читать книгу", "We read a book together.", "Мы читаем книгу вместе."),
                ("drink-tea", "drink tea", "пить чай", "Do you drink tea?", "Ты пьёшь чай?"),
                ("like-coffee", "like coffee", "любить кофе", "Does he like coffee?", "Он любит кофе?"),
                ("in-the-evening", "in the evening", "вечером", "They read in the evening.", "Они читают вечером.")
            ]),
            "present-continuous": cards([
                ("right-now", "right now", "прямо сейчас", "What are you doing right now?", "Что ты делаешь прямо сейчас?"),
                ("at-the-moment", "at the moment", "в данный момент", "I’m busy at the moment.", "Я занят в данный момент."),
                ("this-week", "this week", "на этой неделе", "I’m working from home this week.", "На этой неделе я работаю из дома."),
                ("wait-for", "wait for", "ждать кого-то или чего-то", "I’m waiting for the bus.", "Я жду автобус."),
                ("look-for", "look for", "искать кого-то или что-то", "She’s looking for her keys.", "Она ищет свои ключи."),
                ("work-on", "work on", "работать над чем-то", "I’m working on a report.", "Я работаю над отчётом."),
                ("write-a-message", "write a message", "писать сообщение", "He’s writing a message.", "Он пишет сообщение."),
                ("make-dinner", "make dinner", "готовить ужин", "My brother is making dinner.", "Мой брат готовит ужин."),
                ("talk-to", "talk to", "разговаривать с кем-то", "Are you talking to Alex?", "Ты разговариваешь с Алексом?"),
                ("listen-to", "listen to", "слушать кого-то или что-то", "They’re listening to music.", "Они слушают музыку."),
                ("have-lunch", "have lunch", "обедать", "Are you having lunch?", "Ты обедаешь?"),
                ("get-ready", "get ready", "собираться, готовиться", "We’re getting ready for work.", "Мы собираемся на работу.")
            ]),
            "present-contrast": cards([
                ("usually", "usually", "обычно", "I usually take the bus.", "Я обычно езжу на автобусе."),
                ("today", "today", "сегодня", "Today I’m walking to work.", "Сегодня я иду на работу пешком."),
                ("take-the-bus", "take the bus", "ехать на автобусе", "She usually takes the bus.", "Она обычно ездит на автобусе."),
                ("walk-to-work", "walk to work", "ходить на работу пешком", "I’m walking to work today.", "Сегодня я иду на работу пешком."),
                ("watch-tv", "watch TV", "смотреть телевизор", "They’re watching TV now.", "Они сейчас смотрят телевизор."),
                ("on-weekdays", "on weekdays", "по будням", "We get up early on weekdays.", "По будням мы встаём рано."),
                ("get-up", "get up", "вставать с постели", "I get up at seven.", "Я встаю в семь."),
                ("take-a-break", "take a break", "сделать перерыв", "I’m taking a break now.", "Сейчас у меня перерыв.")
            ])
        ]
    }

    private nonisolated static func cards(
        _ rows: [(id: String, en: String, ru: String, example: String, translation: String)]
    ) -> [VocabularyCard] {
        rows.map { row in
            let alternatives: [String]? = switch row.id {
            case "make-dinner": ["cook dinner"]
            case "talk-to": ["talk with", "speak to", "speak with"]
            case "have-lunch": ["eat lunch"]
            case "at-the-moment": ["at this moment"]
            case "right-now": ["right at this moment"]
            default: nil
            }
            return VocabularyCard(id: row.id, english: row.en, russian: row.ru, example: row.example,
                                  exampleTranslation: row.translation, acceptedAnswers: alternatives)
        }
    }

    private nonisolated static var continuousCheckpointPractice: [Exercise] {
        [
            choice("snow", "На улице идёт снег. **It ___ outside.**", ["am snowing", "is snowing", "are snowing"],
                   "is snowing", "С **it** используем **is**.", "Форма am / is / are"),
            choice("temporary", "У Лео временно сломана машина. Выбери фразу про эту неделю.",
                   ["Leo is taking the bus this week.", "Leo is take the bus this week.", "Leo are taking the bus this week."],
                   "Leo is taking the bus this week.", "Временную ситуацию выражаем **is taking**.", "Временная ситуация"),
            choice("short", "Выбери краткий ответ. **Are your friends studying now?**",
                   ["Yes, they do.", "Yes, they are.", "Yes, they’re."], "Yes, they are.",
                   "Короткий ответ строится на **are** и использует полную форму.", "Короткие ответы"),
            choice("where", "Выбери вопрос «Куда они идут?»",
                   ["Where they are going?", "Where are they going?", "What are they going?"],
                   "Where are they going?", "Порядок слов: **Where + are + they + going**.", "Вопросы в Continuous"),
            gap("swim", "Впиши форму глагола. **The children are ___ (swim).**",
                ["swimming"], "Перед **-ing** удваиваем конечную **m**."),
            gap("take", "Впиши форму глагола. **He’s ___ (take) a photo.**",
                ["taking"], "У **take** убираем конечную **e**."),
            gap("she-not", "Впиши **два слова**. **She ___ ___ (not) watching TV.**",
                ["is not"], "В отрицании **not** ставим после **is**."),
            gap("what", "Впиши вопросительное слово. **___ are you looking for?** «Что ты ищешь?»",
                ["What"], "**What** означает «что»."),
            gap("full-are", "Исправь одно слово и перепиши фразу. **We is waiting for a friend.**",
                ["We are waiting for a friend.", "We're waiting for a friend."],
                "С **we** ставим **are**.", kind: .correction),
            gap("fix-order", "Исправь порядок слов. **You are working on the report?**",
                ["Are you working on the report?"], "В вопросе **are** идёт перед **you**.", kind: .correction),
            listening("hear-bus", "Чего ждёт говорящий?", "I’m waiting for the bus near the park.",
                      ["Автобуса", "Такси", "Друга"], "Автобуса", "**Waiting for the bus** — «жду автобус»."),
            listening("hear-jacket", "Что ищет говорящий?", "I’m looking for my jacket.",
                      ["Телефон", "Куртку", "Ключи"], "Куртку", "**Jacket** означает «куртка»."),
            listening("hear-report", "Что человек делает вместо обеда?", "I’m not having lunch. I’m working on a report.",
                      ["Пишет отчёт", "Готовит ужин", "Ждёт автобус"], "Пишет отчёт",
                      "**Work on a report** — «работать над отчётом»."),
            Exercise(id: "ask-now", kind: .written, prompt: "Напиши по-английски «Чем она сейчас занимается?»",
                     options: nil, acceptedAnswers: nil, explanation: nil,
                     rubric: "Accept What is she doing now? or What’s she doing at the moment? Accept equivalent present continuous questions.",
                     topic: "Вопросы в Continuous"),
            Exercise(id: "message", kind: .dialogue, prompt: "Друг спрашивает **Can you talk?** Ответь двумя фразами. Скажи, что ты сейчас делаешь, и спроси, свободен ли он позже.",
                     options: nil, acceptedAnswers: nil, explanation: nil,
                     rubric: "Require a short response with a Present Continuous description and a natural question about being free later. Accept any sensible activity.",
                     topic: "Короткие сообщения")
        ]
    }

    private nonisolated static func gap(
        _ id: String, _ prompt: String, _ answers: [String], _ explanation: String, kind: Exercise.Kind = .gap
    ) -> Exercise {
        Exercise(id: id, kind: kind, prompt: prompt, options: nil, acceptedAnswers: answers,
                 explanation: explanation, rubric: nil, topic: "Формы Present Continuous")
    }
}
