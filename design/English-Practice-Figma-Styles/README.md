# English Practice Styles

Импорт создаёт 46 локальных стилей цвета (23 роли × Light и Dark) и 9 стилей текста.

1. Распакуй архив целиком и открой нужный файл Figma Design в приложении для macOS или Windows.
2. Выбери **Plugins → Development → Import plugin from manifest…** и укажи `manifest.json`.
3. Запусти **English Practice Styles** через **Plugins → Development**.
4. Применяй цвета из `English Practice/Color/Light` или `English Practice/Color/Dark`, а типографику из `English Practice/Type`.

Для текстовых стилей нужны Nunito ExtraBold и Inter Regular, Medium и Semi Bold. Если начертания недоступны в редакторе, установи их и повтори запуск. Сборка и подключение к сети плагину не требуются. При повторном запуске уже существующие одноимённые стили сохраняют свои значения.

Если Figma просит выдать новый ID, создай локальный плагин через **Plugins → Development → New plugin…** и перенеси ID из сгенерированного Figma манифеста в `manifest.json` этого пакета. Затем импортируй этот манифест. Публиковать плагин для использования в своём файле не нужно.

Справка: [импорт локального плагина](https://help.figma.com/hc/en-us/articles/360042786733-Create-a-classic-plugin-for-development).
