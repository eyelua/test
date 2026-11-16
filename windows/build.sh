#!/bin/bash
# Dark Crown Browser — сборка форка LibreWolf.
# Запускать в Linux или WSL2 (Ubuntu): sudo apt install git make python3 curl
set -e

WORK="$HOME/darkcrown-build"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORK" && cd "$WORK"

# 1. Исходники LibreWolf (патчи, тема, Makefile) с подмодулями
if [ ! -d source ]; then
  git clone --recursive https://codeberg.org/librewolf/source.git
fi

# 2. Репозиторий настроек LibreWolf
if [ ! -d settings ]; then
  git clone https://codeberg.org/librewolf/settings.git
fi

# 3. Добавляем наши настройки в конец librewolf.cfg (один раз)
if ! grep -q "Dark Crown" settings/librewolf.cfg; then
  cat "$HERE/darkcrown.cfg" >> settings/librewolf.cfg
  echo "Настройки Dark Crown добавлены в settings/librewolf.cfg"
fi

# 4. Сборка (первая — несколько часов, нужно ~60 ГБ места)
cd source
make bootstrap   # один раз: ставит зависимости для сборки
make build
make package
echo "Готово. Результат лежит в папке source/."
echo "Переименование в Dark Crown делай после первой удачной сборки: bash $HERE/find-name.sh"
