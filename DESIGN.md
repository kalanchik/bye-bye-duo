---
name: "English Practice"
description: "Игровой тренажёр английского для начинающих с нативной навигацией Apple."
colors:
  surface-canvas-light: "#F7F6FF"
  surface-canvas-dark: "#131221"
  surface-card-light: "#FFFFFF"
  surface-card-dark: "#1E1C30"
  surface-subtle-light: "#EFEDF8"
  surface-subtle-dark: "#27253B"
  text-primary-light: "#211B3D"
  text-primary-dark: "#F5F2FF"
  text-secondary-light: "#5E5675"
  text-secondary-dark: "#BDB5D4"
  border-decorative-light: "#E0DCEF"
  border-decorative-dark: "#38334F"
  border-control-light: "#817899"
  border-control-dark: "#837A9D"
  brand-action-light: "#5146C6"
  brand-action-dark: "#B8AAFF"
  brand-action-edge-light: "#352B95"
  brand-action-edge-dark: "#7863D7"
  brand-on-action-light: "#FFFFFF"
  brand-on-action-dark: "#211744"
  brand-soft-light: "#ECE8FF"
  brand-soft-dark: "#332855"
  brand-on-soft-light: "#44369E"
  brand-on-soft-dark: "#D7CEFF"
  state-success-background-light: "#DDF7ED"
  state-success-background-dark: "#18362F"
  state-success-foreground-light: "#145D47"
  state-success-foreground-dark: "#98E6C8"
  state-error-background-light: "#FCE8ED"
  state-error-background-dark: "#412431"
  state-error-foreground-light: "#982944"
  state-error-foreground-dark: "#FFBACB"
  state-reward-background-light: "#FFECCD"
  state-reward-background-dark: "#403021"
  state-reward-foreground-light: "#794806"
  state-reward-foreground-dark: "#FFD498"
  state-disabled-background-light: "#E8E5F0"
  state-disabled-background-dark: "#2E2A43"
  state-disabled-foreground-light: "#655E78"
  state-disabled-foreground-dark: "#A9A1BF"
  progress-track-light: "#E4DFF5"
  progress-track-dark: "#3D355A"
  progress-fill-light: "#6554D8"
  progress-fill-dark: "#B8AAFF"
  focus-ring-light: "#5146C6"
  focus-ring-dark: "#C2B5FF"
typography:
  display:
    fontFamily: "Nunito"
    fontSize: "36px"
    fontWeight: 800
    lineHeight: "44px"
    letterSpacing: "-0.6px"
  screen-title:
    fontFamily: "Nunito"
    fontSize: "28px"
    fontWeight: 800
    lineHeight: "36px"
    letterSpacing: "-0.35px"
  section-title:
    fontFamily: "Nunito"
    fontSize: "22px"
    fontWeight: 800
    lineHeight: "28px"
    letterSpacing: "0px"
  exercise-prompt:
    fontFamily: "Inter"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: "34px"
    letterSpacing: "0px"
  body:
    fontFamily: "Inter"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: "24px"
    letterSpacing: "0px"
  answer:
    fontFamily: "Inter"
    fontSize: "17px"
    fontWeight: 500
    lineHeight: "26px"
    letterSpacing: "0px"
  button:
    fontFamily: "Inter"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: "22px"
    letterSpacing: "0px"
  label:
    fontFamily: "Inter"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: "20px"
    letterSpacing: "0px"
  caption:
    fontFamily: "Inter"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: "18px"
    letterSpacing: "0px"
rounded:
  field: "12px"
  control: "16px"
  card: "20px"
  panel: "24px"
  pill: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
components:
  button-primary-light:
    backgroundColor: "{colors.brand-action-light}"
    textColor: "{colors.brand-on-action-light}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    height: "52px"
  button-primary-dark:
    backgroundColor: "{colors.brand-action-dark}"
    textColor: "{colors.brand-on-action-dark}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    height: "52px"
---

# English Practice

## Overview

English Practice — тренажёр для тех, кто начинает учить английский. Урок состоит из коротких заданий с русскими инструкциями и примерами из повседневной речи. На экране сразу видны текущий шаг, само задание и следующее действие.

В Duolingo прогресс расположен над заданием, варианты ответа выглядят как крупные карточки, а результат проверки появляется рядом с кнопкой перехода. Переносим эту структуру в English Practice. Свой визуальный характер строим на индиго, прохладных поверхностях и округлых заголовках. На экране результата появляется абрикосовый цвет и крупное число. [Экраны Duolingo для iPhone](https://apps.apple.com/ru/app/id570060128)

## Colors

Две темы следуют системному оформлению. В таблице указаны значения sRGB и имена ролей. В Figma они сгруппированы под `English Practice/Color/Light` и `English Practice/Color/Dark`.

| Роль | Светлая | Тёмная | Применение |
| --- | --- | --- | --- |
| `Surface/Canvas` | `#F7F6FF` | `#131221` | Фон экрана урока и плана. |
| `Surface/Card` | `#FFFFFF` | `#1E1C30` | Карточки заданий и поверхность поля ввода. |
| `Surface/Subtle` | `#EFEDF8` | `#27253B` | Нейтральные плашки и фон примеров. |
| `Text/Primary` | `#211B3D` | `#F5F2FF` | Основной текст. |
| `Text/Secondary` | `#5E5675` | `#BDB5D4` | Пояснения, перевод, подсказка в поле. |
| `Border/Decorative` | `#E0DCEF` | `#38334F` | Декоративные разделители и края карточек. |
| `Border/Control` | `#817899` | `#837A9D` | Контур активного поля и варианта ответа. |
| `Brand/Action` | `#5146C6` | `#B8AAFF` | Основное действие. |
| `Brand/Action edge` | `#352B95` | `#7863D7` | Нижняя грань основной кнопки. |
| `Brand/On action` | `#FFFFFF` | `#211744` | Текст и иконка основной кнопки. |
| `Brand/Soft` | `#ECE8FF` | `#332855` | Выбранный ответ и тематическая плашка. |
| `Brand/On soft` | `#44369E` | `#D7CEFF` | Текст и иконка на Brand/Soft. |
| `State/Success/Background` | `#DDF7ED` | `#18362F` | Подложка верного ответа. |
| `State/Success/Foreground` | `#145D47` | `#98E6C8` | Текст и иконка верного ответа. |
| `State/Error/Background` | `#FCE8ED` | `#412431` | Подложка ошибки. |
| `State/Error/Foreground` | `#982944` | `#FFBACB` | Текст и иконка ошибки. |
| `State/Reward/Background` | `#FFECCD` | `#403021` | Подложка достижения. |
| `State/Reward/Foreground` | `#794806` | `#FFD498` | Текст и иконка достижения. |
| `State/Disabled/Background` | `#E8E5F0` | `#2E2A43` | Подложка недоступного действия. |
| `State/Disabled/Foreground` | `#655E78` | `#A9A1BF` | Текст недоступного действия. |
| `Progress/Track` | `#E4DFF5` | `#3D355A` | Дорожка индикатора. |
| `Progress/Fill` | `#6554D8` | `#B8AAFF` | Заполненная часть индикатора. |
| `Focus/Ring` | `#5146C6` | `#C2B5FF` | Контур клавиатурного фокуса. |

Индиго обозначает действие или выбор. Мятный и ягодный появляются после проверки ответа. Абрикосовый отмечает завершение урока и достижения. Состояние всегда сопровождается текстом или иконкой с доступной подписью.

Контраст текста на поверхностях и надписей на цветных подложках проверен для обеих тем. У текста основной кнопки соотношение 6,90:1 в светлой теме и 8,05:1 в тёмной. Для текста используем минимум 4,5:1, для значимых контуров и индикаторов — 3:1. Контраст системного стекла проверяем на реальном фоне.

## Typography

**Nunito ExtraBold** задаёт характер заголовкам и результатам. **Inter** используется для заданий, ответов и пояснений. Оба семейства поддерживают латиницу и кириллицу. Для стандартных панелей, меню и диалогов используем системный шрифт Apple.

В таблице приведены базовые значения макета в px. При переносе в нативный интерфейс используем их как исходные размеры в pt и масштабируем вместе с пользовательскими настройками текста. Стили в Figma находятся в группе `English Practice/Type`.

| Стиль | Шрифт и вес | Кегль / строка | Трекинг | Применение |
| --- | --- | --- | --- | --- |
| `Display` | Nunito 800 | 36 / 44 | -0,6 | Итог урока, крупное число результата. |
| `Screen title` | Nunito 800 | 28 / 36 | -0,35 | Заголовок экрана. |
| `Section title` | Nunito 800 | 22 / 28 | 0 | Название раздела или учебной карточки. |
| `Exercise prompt` | Inter 600 | 24 / 34 | 0 | Английская фраза или главный вопрос. |
| `Body` | Inter 400 | 16 / 24 | 0 | Русская инструкция, перевод и объяснение. |
| `Answer` | Inter 500 | 17 / 26 | 0 | Вариант ответа и введённый текст. |
| `Button` | Inter 600 | 16 / 22 | 0 | Надпись на кнопке. |
| `Label` | Inter 600 | 14 / 20 | 0 | Метка задания, статус и счётчик. |
| `Caption` | Inter 400 | 13 / 18 | 0 | Второстепенные метаданные. |

Фраза для перевода получает `Exercise prompt`, а русская инструкция — `Body`. Например, «Переведи на русский» и «I usually get up at seven». Английские слова в пояснениях выделяем полужирным начертанием в строке. Переводы и объяснения допускают переносы, в том числе при увеличенном размере текста.

## Layout

- Базовый шаг 4 pt. Для вертикального ритма используем 8, 12, 16, 24 и 32 pt. Поля контента начинаются с 16 pt в компактном окне и 24 pt в широком.
- В уроке сверху располагается строка прогресса с подписью «Задание 6 из 24». Под ней идут инструкция, фраза и поле или варианты ответа. Внизу находится основное действие. На широких экранах учебная колонка центрируется и ограничивается 600 pt.
- Когда открывается клавиатура или увеличивается текст, контент прокручивается. Нижнее действие учитывает безопасную область и остаётся достижимым. Русские инструкции и длинные ответы переносятся целиком.
- На широком экране в плане обучения уместен системный сайдбар. На узком используем системную навигацию с предсказуемым возвратом. В самом уроке доступны выход и сохранение черновика.

## Elevation & Depth

- Учебный слой непрозрачный. Карточка задания, варианты ответа, поле ввода и объяснение отделяются поверхностью и контуром. Текст остаётся читаемым независимо от соседних элементов.
- Liquid Glass используется в системном слое навигации. Предпочитаем стандартные панели, тулбар и сайдбар. Для отдельного плавающего навигационного элемента подходит системный вариант `regular`.
- При уменьшенной прозрачности, повышенном контрасте или на платформе без Liquid Glass пользователь получает читаемую системную поверхность. Для кастомного элемента запасной вариант — непрозрачная `Surface/Card`. В Figma навигационное стекло можно обозначить отдельно как приближение системного материала.
- Игровая глубина сосредоточена в основной кнопке. В покое у неё видна нижняя грань 3 pt. При нажатии грань сжимается, а область нажатия сохраняет размер. При Reduce Motion используем статическую смену состояния.

## Shapes

| Элемент | Скругление |
| --- | --- |
| Поле ввода | 12 pt |
| Основная кнопка и вариант ответа | 16 pt |
| Карточка задания | 20 pt |
| Кастомная панель результата | 24 pt |
| Короткая метка и индикатор прогресса | Капсула |

У самостоятельного интерактивного элемента целевая область не меньше 44 × 44 pt. Кастомный клавиатурный фокус — видимое кольцо 2 pt с зазором 2 pt от элемента. У системных элементов сохраняем системные форму и фокус.

## Components

Для нативных виджетов macOS в макетах Figma используй экземпляры компонентов из библиотеки **macOS 27 UI Kit** от Apple.

| Компонент | Внешний вид и поведение |
| --- | --- |
| **Основное действие** | Высота от 52 pt. Индиго, контрастная надпись и нижняя грань. Типичный переход — «Проверить» → «Продолжить». |
| **Вариант ответа** | В покое `Surface/Card` и `Border/Control`. При выборе — `Brand/Soft`, индиговый контур и отметка. После проверки — цвет и подпись результата. |
| **Поле ввода** | Полноразмерная непрозрачная поверхность с видимым контуром. Инструкция или пример остаются видны при вводе. Для диалога и сообщения поле растёт по высоте. |
| **Аудирование** | Кнопка воспроизведения со значком и доступной подписью «Прослушать». Повторное воспроизведение доступно с того же места интерфейса. |
| **Проверка ответа** | Сообщение появляется перед кнопкой «Продолжить», сразу после учебного блока. «Верно» или «Почти!» сопровождается коротким пояснением. При ошибке показываем правильный вариант рядом с ответом ученика. |
| **План обучения** | Разделы идут последовательно. Текущий шаг выделяется плашкой «Продолжить», завершённые видны по галочке, следующие — по нейтральному состоянию. |
| **Карточка словаря** | Русский смысл или английская фраза в фокусе. После раскрытия видны ответ и короткий пример с переводом. |
| **Итог урока** | Крупный результат в `Display`, абрикосовый акцент и одно основное действие. |

## Do's and Don'ts

- На одном экране даём приоритет одному действию. После проверки оставляем ответ и пояснение на виду до перехода дальше.
- Для верного ответа, ошибки и недоступного действия используем понятную подпись. Проверяем урок в обеих темах, с увеличенным текстом, клавиатурной навигацией и настройками движения и прозрачности.
- Игровые детали располагаем вокруг задания. Формулировка, поле ввода и объяснение остаются визуально спокойными.
- В заданиях на лексику иллюстрация может быть частью вопроса. В заданиях на грамматику главным ориентиром остаётся фраза.

### Импорт в Figma

1. Распакуй [English-Practice-Figma-Styles.zip](design/English-Practice-Figma-Styles.zip) и открой целевой файл **Figma Design** в настольном приложении.
2. Выбери **Plugins → Development → Import plugin from manifest…** и укажи `manifest.json` из архива.
3. Запусти **English Practice Styles** из меню **Plugins → Development**. В локальных стилях появятся 46 стилей цвета и 9 текстовых стилей. Светлые и тёмные цвета сгруппированы отдельно. Для смены темы в макете выбери стили из соответствующей группы.
4. При повторном запуске плагин добавляет только отсутствующие стили. При сообщении об отсутствующем шрифте сделай Nunito и Inter доступными в Figma и запусти импорт ещё раз.

[Apple HIG — Materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [Figma — Import a development plugin](https://help.figma.com/hc/en-us/articles/360042786733-Create-a-classic-plugin-for-development)
