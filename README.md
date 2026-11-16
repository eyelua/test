# Dark Crown Browser

Один репозиторий для двух версий:

- `windows/` — Dark Crown для Windows (на основе LibreWolf), установщик `DarkCrown-Setup.exe`
- `android/` — Dark Crown для Android (на движке Gecko), файл `DarkCrown.apk`

Сборку делает GitHub, ничего ставить на свой компьютер не нужно.

## Как получить файлы

1. Загрузи содержимое этого проекта в репозиторий на GitHub (папки `windows`, `android`, `.github` и этот файл).
2. Открой вкладку **Actions**. Должны запуститься две сборки: **Build Dark Crown for Windows** и **Build Dark Crown for Android**. Если не запустились, выбери нужную слева и нажми **Run workflow**.
3. Когда появится зелёная галочка, открой запуск и внизу в разделе **Artifacts** скачай:
   - `DarkCrown-Setup` — внутри `DarkCrown-Setup.exe` (для Windows)
   - `DarkCrown-APK` — внутри `DarkCrown.apk` (для телефона)

Если какая-то сборка упала, пришли последние 50-80 строк лога упавшего шага.

Подробности по каждой версии: `windows/README.md` и `android/README.md`.
