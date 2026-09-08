#!/usr/bin/env python3
"""Revisión estructural de los archivos Dart.

No sustituye a `flutter analyze` —eso hay que correrlo en el Mac— pero caza los
fallos tontos antes de que cuesten un ciclo de compilación: llaves sin cerrar,
imports que apuntan a archivos que no existen, interpolaciones mal escritas.
"""
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
LIB = RAIZ / "lib"

PAREJAS = {")": "(", "]": "[", "}": "{"}
ABIERTOS = set(PAREJAS.values())

# APIs que solo existen a partir de cierta versión de Flutter, con la
# alternativa que compila en TODAS.
#
# Esto está aquí porque ya pasó: la primera versión de estas pantallas usaba
# `Color.withValues`, `WidgetStateProperty` y `CardThemeData`, y no compilaba en
# el Flutter del equipo. Escribir con el API viejo no cuesta nada —sigue
# funcionando en los Flutter nuevos, solo marcado como deprecado— mientras que
# el API nuevo directamente no existe en los viejos. La asimetría decide.
APIS_NUEVAS = [
    ("withValues(", "Flutter 3.27", "usa .withOpacity(0.4) en vez de .withValues(alpha: 0.4)"),
    ("WidgetStateProperty", "Flutter 3.22", "usa MaterialStateProperty"),
    ("WidgetStatesController", "Flutter 3.22", "usa MaterialStatesController"),
    ("WidgetState.", "Flutter 3.22", "usa MaterialState."),
    ("CardThemeData(", "Flutter 3.27", "usa CardTheme("),
    ("DialogThemeData(", "Flutter 3.27", "usa DialogTheme("),
    ("TabBarThemeData(", "Flutter 3.27", "usa TabBarTheme("),
]


def sin_comentarios_ni_cadenas(fuente: str) -> str:
    """Sustituye cadenas y comentarios por espacios, conservando longitudes."""
    salida = []
    i, n = 0, len(fuente)
    while i < n:
        c = fuente[i]
        dos = fuente[i:i + 2]

        if dos == "//":
            j = fuente.find("\n", i)
            j = n if j == -1 else j
            salida.append(" " * (j - i)); i = j; continue

        if dos == "/*":
            j = fuente.find("*/", i + 2)
            j = n if j == -1 else j + 2
            salida.append(" " * (j - i)); i = j; continue

        if c in "'\"":
            triple = fuente[i:i + 3]
            cierre = triple if triple in ("'''", '"""') else c
            j = i + len(cierre)
            while j < n:
                if fuente[j] == "\\":
                    j += 2; continue
                if fuente[j:j + len(cierre)] == cierre:
                    j += len(cierre); break
                j += 1
            # Se conservan las llaves de interpolación ${...}: son código.
            trozo = fuente[i:j]
            salida.append(re.sub(r"[^\s{}]", " ", trozo))
            i = j; continue

        salida.append(c); i += 1

    return "".join(salida)


def revisar(ruta: pathlib.Path):
    fuente = ruta.read_text()
    problemas = []

    # 1. delimitadores balanceados
    limpio = sin_comentarios_ni_cadenas(fuente)
    pila = []
    for pos, c in enumerate(limpio):
        if c in ABIERTOS:
            pila.append((c, pos))
        elif c in PAREJAS:
            if not pila or pila[-1][0] != PAREJAS[c]:
                linea = fuente[:pos].count("\n") + 1
                problemas.append(f"línea {linea}: '{c}' sin su pareja")
                break
            pila.pop()
    if pila and not problemas:
        c, pos = pila[0]
        linea = fuente[:pos].count("\n") + 1
        problemas.append(f"línea {linea}: '{c}' se queda sin cerrar")

    # 2. interpolación mal escrita: $ seguido de algo que no es identificador,
    #    { ni otro $. El `\$` escapado —un precio en dólares dentro de una
    #    cadena— es legítimo y no cuenta.
    for m in re.finditer(r"(?<!\\)\$(?![A-Za-z_{$])", fuente):
        linea = fuente[:m.start()].count("\n") + 1
        contexto = fuente[m.start():m.start() + 12].replace("\n", " ")
        problemas.append(
            f"línea {linea}: interpolación sospechosa cerca de '{contexto}'")

    # 3. APIs que exigen un Flutter más nuevo del que puede tener el equipo
    for aguja, version, arreglo in APIS_NUEVAS:
        for m in re.finditer(re.escape(aguja), limpio):
            linea = fuente[:m.start()].count("\n") + 1
            problemas.append(
                f"línea {linea}: '{aguja.rstrip('(')}' necesita {version} — {arreglo}")

    # 4. imports relativos que no existen
    for m in re.finditer(r"""import\s+['"](?!package:|dart:)([^'"]+)['"]""", fuente):
        destino = (ruta.parent / m.group(1)).resolve()
        if not destino.exists():
            linea = fuente[:m.start()].count("\n") + 1
            problemas.append(f"línea {linea}: import a '{m.group(1)}', que no existe")

    return problemas


def main():
    archivos = sorted(LIB.rglob("*.dart"))
    if not archivos:
        print("no encuentro archivos .dart en lib/", file=sys.stderr)
        return 2

    total = 0
    for ruta in archivos:
        problemas = revisar(ruta)
        rel = ruta.relative_to(RAIZ)
        if problemas:
            total += len(problemas)
            print(f"\n{rel}")
            for p in problemas:
                print(f"  - {p}")
        else:
            print(f"ok  {rel}")

    if total:
        print(f"\n{total} problema(s)")
        return 1

    print(f"\nOK  {len(archivos)} archivos sin problemas estructurales.")
    print("    Falta `flutter analyze` en el Mac: esto no comprueba tipos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
