#!/usr/bin/env python3
"""Compara `theme.dart` con los valores del diseño de Figma.

    python3 tools/check_tokens.py

Por qué existe
--------------
El tema venía con una paleta *parecida* al diseño y ninguno de sus colores era
el del archivo: el coral estaba a dos puntos de distancia, el gris de texto a
bastantes más. Nadie lo había notado porque a ojo cuadra, y porque no había
nada que lo comprobara. Esa es exactamente la clase de error que se queda
dentro para siempre.

La tabla de abajo son los valores leídos del archivo de Figma (*The Az App*,
`g2Tqob4TmmYOxI5IahNDoE`) en las pantallas HU 2 y HU3, HU6 y `s2`. Cuando se
lea otra pantalla y aparezca un color nuevo, se añade aquí y deja de poder
desaparecer sin que nadie se entere.

También comprueba que lo que el tema declara como fuente esté declarado en el
pubspec, porque una familia mal escrita no falla: Flutter cae a la del sistema
en silencio, que es justo lo que llevaba pasando.
"""
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
TEMA = RAIZ / "lib" / "theme.dart"
PUBSPEC = RAIZ / "pubspec.yaml"

# nombre en theme.dart -> color del diseño
COLORES = {
    "coral": "FFE8613A",
    "hueso": "FFFAF7F4",
    "tinta": "FF1A1A1A",
    "tintaSuave": "FF8A8A9A",
    "cuerpo": "FF6B7A8D",
    "linea": "FFEDE8E1",
    "mustSee": "FFD24B1A",
    "quickStop": "FF26CDF1",
    "gratis": "FFF5C4B5",
    "chipFondo": "FFFFF0EB",
    "chipBorde": "FFFFBDAA",
    "navActivo": "FF0066FF",
}

# estilo nombrado en Figma -> (constante en theme.dart, familia, tamaño, peso)
TIPOGRAFIA = {
    "H1 content": ("h1", "serif", 30, 700),
    "H2 Content": ("h2", "serif", 24, 700),
    "H3 content": ("h3", "serif", 22, 700),
    "Quote": ("cita", "serif", 16, 600),
    "Site Title": ("tituloSitio", "grotesca", 20, 700),
    "Caption/Site description": ("descripcion", "grotesca", 14, 500),
    "TEXT": ("texto", "grotesca", 16, None),
    "Button text": ("textoBoton", "grotesca", 16, 600),
    "Capsule text": ("capsula", "grotesca", 12, 700),
    "Capsule text 2": ("capsulaPequena", "grotesca", 9, 600),
    "H4 site text": ("h4", "grotesca", 14, 700),
}

FAMILIAS = {"serif": "PlayfairDisplay", "grotesca": "Inter"}

VERDE, ROJO, FIN = "\033[32m", "\033[31m", "\033[0m"


def main():
    fuente = TEMA.read_text()
    pubspec = PUBSPEC.read_text()
    problemas = []

    # --- colores ---
    for nombre, esperado in COLORES.items():
        m = re.search(
            rf"static const Color {nombre}\s*=\s*Color\(0x([0-9A-Fa-f]{{8}})\)",
            fuente)
        if not m:
            problemas.append(f"falta el color '{nombre}' en theme.dart")
            continue
        if m.group(1).upper() != esperado:
            problemas.append(
                f"{nombre}: el tema dice #{m.group(1).upper()[2:]} y el diseño "
                f"#{esperado[2:]}")

    # --- tipografía ---
    for estilo, (constante, familia, tamano, peso) in TIPOGRAFIA.items():
        m = re.search(rf"static const {constante} = TextStyle\((.*?)\);",
                      fuente, re.S)
        if not m:
            problemas.append(
                f"falta el estilo '{constante}' ({estilo} en el diseño)")
            continue
        cuerpo = m.group(1)

        if f"fontFamily: {familia}" not in cuerpo:
            problemas.append(
                f"{constante}: el diseño lo quiere en {FAMILIAS[familia]}")

        mt = re.search(r"fontSize:\s*([\d.]+)", cuerpo)
        if not mt or abs(float(mt.group(1)) - tamano) > 0.01:
            dice = mt.group(1) if mt else "nada"
            problemas.append(
                f"{constante}: tamaño {dice}, el diseño dice {tamano}")

        if peso is not None and f"FontWeight.w{peso}" not in cuerpo:
            problemas.append(
                f"{constante}: el diseño lo quiere en peso {peso}")

    # --- las familias existen en el pubspec ---
    for familia, nombre in FAMILIAS.items():
        if f"static const String {familia} = '{nombre}'" not in fuente:
            problemas.append(f"theme.dart no declara la familia '{nombre}'")
        if f"family: {nombre}" not in pubspec:
            problemas.append(
                f"pubspec.yaml no declara la familia '{nombre}'. Una familia "
                "que no existe NO falla: Flutter cae a la del sistema en "
                "silencio.")

    # --- y los archivos están ---
    for m in re.finditer(r"asset:\s*(assets/fonts/[^\s]+)", pubspec):
        ruta = RAIZ / m.group(1)
        if not ruta.exists() or ruta.stat().st_size == 0:
            problemas.append(
                f"falta {m.group(1)} — tráelo con `bash tools/traer-fuentes.sh`")

    if problemas:
        print(f"{ROJO}{len(problemas)} desajuste(s) con el diseño:{FIN}\n")
        for p in problemas:
            print(f"  - {p}")
        return 1

    print(f"{VERDE}OK  el tema concuerda con el diseño de Figma.{FIN}")
    print(f"    {len(COLORES)} colores y {len(TIPOGRAFIA)} estilos "
          "contrastados.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
