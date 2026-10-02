#!/usr/bin/env bash
#
# Baja las dos tipografías del diseño a assets/fonts/.
#
#     bash tools/traer-fuentes.sh
#
# Hay que correrlo UNA vez por copia del repo, y después de clonar. Los .ttf no
# se versionan: son binarios de varios cientos de kilobytes que no cambian nunca
# y que cualquiera puede volver a bajar con esto.
#
# Por qué un script y no "bájalas de fonts.google.com": el nombre del archivo
# tiene que coincidir EXACTAMENTE con lo que declara pubspec.yaml. Si no
# coincide, Flutter falla al compilar con "unable to locate asset entry", que no
# dice cuál falta.
#
# Las dos son variables (un archivo cubre todos los pesos) y vienen del
# repositorio oficial de Google Fonts, con licencia SIL Open Font License 1.1.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p assets/fonts

BASE="https://raw.githubusercontent.com/google/fonts/main/ofl"

traer() {
  local destino="assets/fonts/$1"
  local url="$2"
  if [ -s "$destino" ]; then
    echo "  ya estaba: $1"
    return
  fi
  echo "  bajando:   $1"
  curl -fsSL "$url" -o "$destino"
}

echo "Tipografías del diseño:"
traer "PlayfairDisplay.ttf"        "$BASE/playfairdisplay/PlayfairDisplay%5Bwght%5D.ttf"
traer "PlayfairDisplay-Italic.ttf" "$BASE/playfairdisplay/PlayfairDisplay-Italic%5Bwght%5D.ttf"
traer "Inter.ttf"                  "$BASE/inter/Inter%5Bopsz,wght%5D.ttf"

echo
echo "Listo. Comprobación:"
for f in PlayfairDisplay.ttf PlayfairDisplay-Italic.ttf Inter.ttf; do
  if [ -s "assets/fonts/$f" ]; then
    printf '  ok  %-28s %s bytes\n' "$f" "$(wc -c < "assets/fonts/$f" | tr -d ' ')"
  else
    printf '  FALTA %s — sin esto `flutter run` no compila\n' "$f"
    exit 1
  fi
done
