# Разработка и проверки

Этот документ собирает технические сведения, которые нужны для локальной
разработки Pivotfall: headless-import, smoke-тесты, Web export, CI-контракт и
диагностику. Правила JSON и полный интерфейс редактора находятся отдельно в
[LEVEL_EDITOR.md](LEVEL_EDITOR.md), а история механик и арен — в
[WORKLOG.md](WORKLOG.md).

Все команды ниже выполняются из корня репозитория.

## Окружение

`project.godot` требует Godot 4.6.x. Команды в этом документе проверены на
Godot 4.6.1, и эту же версию закрепляет CI. Для Web export нужны официальные
templates той же версии, что и запущенный Godot.

Проверить окружение и открыть главное меню:

```sh
godot --version
godot --path .
```

Полезные прямые точки входа:

```sh
godot --path . res://scenes/level_editor.tscn
godot --path . res://scenes/level_runtime_arena.tscn
```

Первая команда открывает встроенный редактор. Вторая запускает изолированный
standalone runtime Arena 01 и нужна в основном для диагностики; обычная игра
начинается с главного меню.

## Импорт после свежего checkout

Перед первым headless-тестом соберите импортированные ресурсы и реестр
`class_name`:

```sh
godot --headless --path . --import
```

Без этого шага свежий checkout может выдать parse/load errors при запуске
скрипта через `--script`, хотя исходники не повреждены. CI всегда выполняет
import до тестов.

## Smoke-тесты

### Полный runner

```sh
bash tests/run_smoke_tests.sh
```

Runner автоматически находит все `tests/*_smoke.gd`. Сейчас это 36 тестов.
Для каждого теста он:

- запускает Godot в headless-режиме с фиксированной частотой 60 кадров;
- пишет отдельный лог в `builds/logs/smoke`;
- проверяет код завершения;
- считает `SCRIPT ERROR:` и `Failed to load script` ошибками;
- требует финальный маркер, составленный из имени теста, например
  `CAMPAIGN_SMOKE_OK` для `campaign_smoke.gd`;
- останавливается после первой ошибки.

### Выбранные тесты

Runner принимает один или несколько путей внутри `tests/`:

```sh
bash tests/run_smoke_tests.sh tests/campaign_smoke.gd
```

```sh
bash tests/run_smoke_tests.sh \
  tests/level_editor_smoke.gd \
  tests/level_import_export_smoke.gd
```

Тот же тест можно запустить напрямую, если нужен чистый вывод Godot без
проверок runner:

```sh
godot --headless --fixed-fps 60 --path . \
  --script res://tests/campaign_smoke.gd
```

### Настройки runner

Runner понимает переменные окружения:

- `GODOT_BIN` — путь к Godot; по умолчанию `godot`;
- `SMOKE_LOG_DIR` — каталог логов; по умолчанию
  `builds/logs/smoke`;
- `SMOKE_TEST_TIMEOUT_SECONDS` — лимит одного теста; по умолчанию 300 секунд,
  `0` отключает лимит.

Для timeout runner использует `timeout` или `gtimeout`. Если ни одной команды
нет, он печатает предупреждение и продолжает без локального лимита; в CI
`timeout` доступен.

Пример с другим бинарником и увеличенным лимитом:

```sh
GODOT_BIN=/path/to/godot \
SMOKE_TEST_TIMEOUT_SECONDS=600 \
bash tests/run_smoke_tests.sh tests/campaign_smoke.gd
```

### Карта покрытия

Источник истины — сами файлы `tests/*_smoke.gd`; runner не хранит отдельный
ручной список. Текущее покрытие удобно делить на четыре группы:

- кампания и оболочка: `arena_select`, `campaign`, `campaign_progress`,
  `community_levels`, `level_foundation`, `main_menu`, `pause_menu`;
- данные и редактор: `level_editor`, `level_import_export`,
  `level_object_catalog`, `linked_mechanisms`;
- механики и арены: `catapult_platform`, `counterweight_arena`, `domino_arena`,
  `double_jump_arena`, `double_jump_pickup`, `exam_arena`, `gate_arena`,
  `pressure_plate`, `shooter_enemy`, `shove_enemy`, `spike_arena`,
  `spike_trap`, `toggle_wall`, `vertical_platform`;
- управление, feedback и анимации: `enemy_elimination_feedback`,
  `hazard_feedback`, `impact_feedback`, `lethal_enemy`, `mechanism_animation`,
  `mobile_controls`, `patrol_enemy_animation`, `player_attack_animation`,
  `player_locomotion_animation`, `shooter_enemy_animation`,
  `shove_enemy_animation`.

К имени из списка нужно добавить `tests/` и суффикс `_smoke.gd`.

## Локальный Web export

Установите официальные Web export templates, совпадающие с версией Godot, и
выполните:

```sh
mkdir -p builds/web
godot --headless --path . --export-release Web builds/web/index.html
python3 -m http.server 8060 --directory builds/web
```

Сборка будет доступна по адресу `http://localhost:8060`. Открывать
`builds/web/index.html` напрямую через `file://` нельзя: WebAssembly и
связанные файлы должны загружаться по HTTP.

Preset `Web`:

- включает JSON-уровни в export;
- исключает `tests/*` и `builds/*`;
- создаёт однопоточную сборку без GDExtension и PWA;
- не требует специальных cross-origin headers для thread support.

## CI и GitHub Pages

Workflow находится в
[`.github/workflows/deploy-pages.yml`](../.github/workflows/deploy-pages.yml).
Он закрепляет Godot и export templates версии 4.6.1 и проверяет контрольные
суммы загружаемых архивов.

Для pull request workflow выполняет:

1. checkout;
2. headless-import проекта;
3. полный `bash tests/run_smoke_tests.sh`;
4. Web export и проверку обязательных `index.html`, `index.js`, `index.pck` и
   `index.wasm`.

Push в `main` и ручной запуск после тех же проверок дополнительно загружают
Pages artifact и выполняют deploy. Pull request никогда не публикует Pages.
При ошибке workflow сохраняет import, smoke и Web-export logs как artifact.

Опубликованная сборка доступна по адресу
[vinatorul.github.io/pivotfall](https://vinatorul.github.io/pivotfall/).

## Архитектурные контракты

### Кампания и runtime

- `campaign.json` — единственный источник порядка, ID, путей и названий 16
  встроенных арен.
- До запуска кампания проверяет manifest и все перечисленные JSON-уровни.
  Частично загруженный каталог не передаётся в `CampaignRunner`.
- Во время игры runner держит один дочерний runtime. Переход, поражение и
  restart заменяют его целиком, поэтому состояние механик не протекает между
  попытками.
- Replay из `ВЫБОР АРЕН` и прямой debug-переход через `F1` не продвигают
  постоянное сохранение.
- Прогресс записывается через проверяемый временный файл и резервную копию;
  загрузчик валидирует данные до использования.

### Уровни и редактор

Путь данных остаётся общим для кампании, импортированных уровней и теста в
редакторе:

```text
JSON → codec → validator → builder → LevelRuntimeArena
```

- JSON использует закрытую версионированную схему и не может ссылаться на
  произвольные сцены, скрипты или ресурсы.
- Builder создаёт runtime только после успешной проверки данных и разрешает
  связи механизмов после регистрации стабильных ID.
- Embedded playtest получает неизменяемый снимок черновика. Restart тестирует
  тот же снимок, а состояние runtime не возвращается в модель редактора.
- Новый data-driven тип требует согласованных изменений каталога объектов,
  проверки и кодирования, builder, редактора и smoke-покрытия. Одна новая
  сцена не считается завершённой поддержкой типа.

Полная schema, лимиты, правила связей, import/export и безопасное сохранение
описаны в [LEVEL_EDITOR.md](LEVEL_EDITOR.md).

## Диагностика

### Parse error на свежем checkout

Сначала выполните:

```sh
godot --headless --path . --import
```

Затем повторите выбранный smoke-тест через runner.

### Runner завершился без понятной ошибки

Откройте соответствующий файл в `builds/logs/smoke`. Runner отдельно проверяет
код завершения, script/load errors и success marker, поэтому строка `FAILED`
в терминале обычно указывает, какой из трёх контрактов нарушен.

### Нет локального timeout

Предупреждение об отсутствии `timeout` и `gtimeout` не означает падение теста.
Runner продолжит работу без лимита. Сам CI запускается в окружении с
`timeout` и дополнительно ограничен на уровне job.

### Web export не находит templates

Установите официальные templates той же версии, которую показывает
`godot --version`. CI использует пару Godot 4.6.1 + templates 4.6.1.

### Web-сборка не открывается с диска

Не используйте `file://`. Запустите локальный HTTP-сервер командой из раздела
«Локальный Web export» и откройте `http://localhost:8060`.

## Связанные документы

- [README проекта](../README.md)
- [Концепция игры](CONCEPT.md)
- [Редактор уровней и формат данных](LEVEL_EDITOR.md)
- [Журнал работы](WORKLOG.md)
- [Исходное исследование](RESEARCH.md)
