const colors = [
  ["Surface/Canvas","#F7F6FF","#131221","Фон экрана урока и плана."],
  ["Surface/Card","#FFFFFF","#1E1C30","Карточки заданий и поверхность поля ввода."],
  ["Surface/Subtle","#EFEDF8","#27253B","Нейтральные плашки и фон примеров."],
  ["Text/Primary","#211B3D","#F5F2FF","Основной текст."],
  ["Text/Secondary","#5E5675","#BDB5D4","Пояснения, перевод, подсказка в поле."],
  ["Border/Decorative","#E0DCEF","#38334F","Декоративные разделители и края карточек."],
  ["Border/Control","#817899","#837A9D","Контур активного поля и варианта ответа."],
  ["Brand/Action","#5146C6","#B8AAFF","Основное действие."],
  ["Brand/Action edge","#352B95","#7863D7","Нижняя грань основной кнопки."],
  ["Brand/On action","#FFFFFF","#211744","Текст и иконка основной кнопки."],
  ["Brand/Soft","#ECE8FF","#332855","Выбранный ответ и тематическая плашка."],
  ["Brand/On soft","#44369E","#D7CEFF","Текст и иконка на Brand/Soft."],
  ["State/Success/Background","#DDF7ED","#18362F","Подложка верного ответа."],
  ["State/Success/Foreground","#145D47","#98E6C8","Текст и иконка верного ответа."],
  ["State/Error/Background","#FCE8ED","#412431","Подложка ошибки."],
  ["State/Error/Foreground","#982944","#FFBACB","Текст и иконка ошибки."],
  ["State/Reward/Background","#FFECCD","#403021","Подложка достижения."],
  ["State/Reward/Foreground","#794806","#FFD498","Текст и иконка достижения."],
  ["State/Disabled/Background","#E8E5F0","#2E2A43","Подложка недоступного действия."],
  ["State/Disabled/Foreground","#655E78","#A9A1BF","Текст недоступного действия."],
  ["Progress/Track","#E4DFF5","#3D355A","Дорожка индикатора."],
  ["Progress/Fill","#6554D8","#B8AAFF","Заполненная часть индикатора."],
  ["Focus/Ring","#5146C6","#C2B5FF","Контур клавиатурного фокуса."],
];

const typography = [
  ["Display","Nunito",800,36,44,-0.6,"Итог урока, крупное число результата."],
  ["Screen title","Nunito",800,28,36,-0.35,"Заголовок экрана."],
  ["Section title","Nunito",800,22,28,0,"Название раздела или учебной карточки."],
  ["Exercise prompt","Inter",600,24,34,0,"Английская фраза или главный вопрос."],
  ["Body","Inter",400,16,24,0,"Русская инструкция, перевод и объяснение."],
  ["Answer","Inter",500,17,26,0,"Вариант ответа и введённый текст."],
  ["Button","Inter",600,16,22,0,"Надпись на кнопке."],
  ["Label","Inter",600,14,20,0,"Метка задания, статус и счётчик."],
  ["Caption","Inter",400,13,18,0,"Второстепенные метаданные."],
];

const prefix = "English Practice";
const weights = { 400: "Regular", 500: "Medium", 600: "Semi Bold", 800: "Extra Bold" };

function normalized(style) {
  return style.toLowerCase().replace(/[^a-z]/g, "");
}

function solidPaint(hex) {
  const rgb = Number.parseInt(hex.slice(1), 16);
  return {
    type: "SOLID",
    color: { r: (rgb >> 16) / 255, g: ((rgb >> 8) & 255) / 255, b: (rgb & 255) / 255 },
  };
}

async function importStyles() {
  const [localPaints, localText] = await Promise.all([
    figma.getLocalPaintStylesAsync(),
    figma.getLocalTextStylesAsync(),
  ]);
  const paintNames = new Set(localPaints.map(style => style.name));
  const textNames = new Set(localText.map(style => style.name));

  const paints = ["Light", "Dark"].flatMap((mode, index) =>
    colors.map(([role, light, dark, description]) => ({
      name: `${prefix}/Color/${mode}/${role}`,
      hex: index === 0 ? light : dark,
      description,
    })),
  ).filter(style => !paintNames.has(style.name));

  const textStyles = typography.map(([role, family, weight, size, lineHeight, tracking, description]) => ({
    name: `${prefix}/Type/${role}`,
    family,
    weight,
    size,
    lineHeight,
    tracking,
    description,
  })).filter(style => !textNames.has(style.name));

  const fonts = new Map();
  if (textStyles.length > 0) {
    const available = await figma.listAvailableFontsAsync();
    for (const { family, weight } of textStyles) {
      const styleName = weights[weight];
      const key = `${family}/${weight}`;
      if (fonts.has(key)) continue;

      const match = available.find(({ fontName }) =>
        fontName.family === family && normalized(fontName.style) === normalized(styleName)
      );
      if (!match) throw new Error(`Шрифт ${family} ${styleName} недоступен в Figma.`);

      fonts.set(key, { family: match.fontName.family, style: match.fontName.style });
    }
    await Promise.all(Array.from(fonts.values(), font => figma.loadFontAsync(font)));
  }

  const created = [];
  try {
    for (const spec of paints) {
      const style = figma.createPaintStyle();
      created.push(style);
      style.name = spec.name;
      style.description = spec.description;
      style.paints = [solidPaint(spec.hex)];
    }
    for (const spec of textStyles) {
      const style = figma.createTextStyle();
      created.push(style);
      style.name = spec.name;
      style.description = spec.description;
      style.fontName = fonts.get(`${spec.family}/${spec.weight}`);
      style.fontSize = spec.size;
      style.lineHeight = { unit: "PIXELS", value: spec.lineHeight };
      style.letterSpacing = { unit: "PIXELS", value: spec.tracking };
    }
  } catch (error) {
    for (const style of created.reverse()) style.remove();
    throw error;
  }

  return created.length
    ? `Добавлено стилей: ${paints.length} цвета и ${textStyles.length} текста.`
    : "Все стили English Practice уже есть в файле.";
}

importStyles().then(
  message => figma.closePlugin(message),
  error => figma.closePlugin(`Импорт прерван. ${error.message}`),
);
