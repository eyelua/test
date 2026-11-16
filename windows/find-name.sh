#!/bin/bash
# Показывает, где в исходниках LibreWolf встречается имя бренда.
# Ничего не меняет — только выводит список, чтобы переименовать осознанно.
# Запуск после первой сборки:  bash find-name.sh

SRC="$HOME/darkcrown-build/source"
[ -d "$SRC" ] || { echo "Нет $SRC — сначала запусти build.sh"; exit 1; }

echo "=== Файлы, где есть 'LibreWolf' (кроме строк с URL) ==="
grep -rIl "LibreWolf" "$SRC" --exclude-dir=.git --exclude-dir=obj-* 2>/dev/null | head -100

echo
echo "=== Строки с брендом в локализации (то, что видит пользователь) ==="
grep -rIn "LibreWolf" "$SRC" --include="*.ftl" --include="*.dtd" --include="*.properties" \
  --exclude-dir=.git 2>/dev/null | head -50

echo
echo "Меняй только отображаемое имя (окно, меню, about). Адреса обновлений и пути оставляй."
