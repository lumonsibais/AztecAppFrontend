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
PRUEBAS = RAIZ / "test"

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


def sin_comentarios_ni_cadenas(fuente: str, cadenas: bool = False) -> str:
    """Sustituye comentarios —y por defecto cadenas— por espacios.

    Las longitudes se conservan para que los números de línea sigan cuadrando.

    `cadenas=True` deja las cadenas tal cual. Lo usa la regla de interpolación,
    que necesita mirar DENTRO de las cadenas (ahí es donde va la interpolación)
    pero no dentro de los comentarios: un `$` en un comentario no interpola
    nada. Antes esa regla leía el archivo en bruto y cantaba un falso positivo
    cada vez que un comentario mencionaba un precio en dólares.
    """
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
            trozo = fuente[i:j]
            # Se conservan las llaves de interpolación ${...}: son código.
            salida.append(trozo if cadenas else re.sub(r"[^\s{}]", " ", trozo))
            i = j; continue

        salida.append(c); i += 1

    return "".join(salida)


SCROLLABLES = ("ListView(", "GridView(", "SingleChildScrollView(",
               "ListView.builder(", "ListView.separated(", "GridView.builder(")


def scrollable_dentro_de_sliver(fuente: str):
    """Un scrollable vertical como hijo de un sliver: altura infinita.

    Dentro de un `SliverToBoxAdapter` la altura que llega es ilimitada, y ahí un
    ListView revienta con "Vertical viewport was given unbounded height".

    Esto ya pasó y costó caro: `_Error` y `_Vacio` de Explore eran ListView, y
    funcionaban mientras Explore era una lista y ellos ERAN el cuerpo. Al pasar
    la pantalla a cuadrícula quedaron dentro de un sliver, y el resultado fue
    que un error de red **no enseñaba nada**: pantalla en blanco. `flutter
    analyze` no lo ve —compila perfectamente— y solo aparece al provocar el
    error con la app corriendo.

    Se mira solo el caso inequívoco: un widget que se pasa como `child:` de un
    SliverToBoxAdapter y cuyo `build` DEVUELVE un scrollable directamente. Si
    devuelve otra cosa —un SizedBox que le acota la altura, por ejemplo— está
    bien y no se toca: así la barra de filtros, que es un ListView horizontal
    dentro de un SizedBox, no da un falso positivo.
    """
    problemas = []
    hijos = set(re.findall(r"SliverToBoxAdapter\(\s*child:\s*(_?\w+)\(", fuente))

    for clase in hijos:
        m = re.search(
            rf"class {re.escape(clase)} extends StatelessWidget.*?"
            r"Widget build\(BuildContext \w+\) \{(.*?)\n  \}",
            fuente, re.S)
        if not m:
            continue
        cuerpo = m.group(1)
        devuelve = re.search(r"return\s+(?:const\s+)?(\w+[.\w]*\()", cuerpo)
        if not devuelve:
            continue
        if devuelve.group(1) in SCROLLABLES:
            linea = fuente[:m.start()].count("\n") + 1
            problemas.append(
                f"línea {linea}: {clase} devuelve un {devuelve.group(1)[:-1]} y "
                "se usa dentro de un SliverToBoxAdapter, donde la altura es "
                "infinita: no se verá nada")
    return problemas


def cuerpos_de_clase(fuente: str):
    """{NombreClase: (cuerpo, posición)} troceando por declaraciones de clase."""
    marcas = [(m.group(1), m.start())
              for m in re.finditer(r"^class (\w+)", fuente, re.M)]
    salida = {}
    for i, (nombre, inicio) in enumerate(marcas):
        fin = marcas[i + 1][1] if i + 1 < len(marcas) else len(fuente)
        salida[nombre] = (fuente[inicio:fin], inicio)
    return salida


def _nombres_declarados(cuerpo: str):
    """Identificadores que el propio State declara: locales y parámetros.

    No hace falta que sea exhaustivo —solo evitar cantar un campo que en
    realidad está sombreado por algo de dentro.
    """
    nombres = set()
    for m in re.finditer(
            r"\b(?:final|const|var|late|late\s+final)\s+"
            r"(?:[\w<>?,\s]+?\s+)?(\w+)\s*[=;]", cuerpo):
        nombres.add(m.group(1))
    # parámetros de métodos y de lambdas: (a, b) => ... / (BuildContext c) {
    for m in re.finditer(r"\(([^()]*)\)\s*(?:async\s*)?(?:=>|\{)", cuerpo):
        for trozo in m.group(1).split(","):
            palabras = re.findall(r"\w+", trozo)
            if palabras:
                nombres.add(palabras[-1])
    return nombres


def campos_sin_widget(fuente: str):
    """Campos de un StatefulWidget referidos sin `widget.` desde su State.

    Por qué existe: convertir un StatelessWidget en StatefulWidget mueve los
    campos de sitio. Dentro del `State` ya no se llaman `place` y `onToggleSaved`
    sino `widget.place` y `widget.onToggleSaved`, y olvidar el prefijo es el
    error clásico de ese refactor. Compila a veces —si el State tiene algo con
    el mismo nombre— y cuando no compila, el fallo aparece en el Mac, que es
    donde no estoy. `_Hero` de la ficha de sitio pasó por ese refactor justo
    antes de escribir esta regla.
    """
    problemas = []
    clases = cuerpos_de_clase(fuente)

    for nombre, (cuerpo, _) in clases.items():
        if f"class {nombre} extends StatefulWidget" not in cuerpo:
            continue

        campos = set(re.findall(r"^\s+final\s+[\w<>?,\s]*?\b(\w+);",
                                cuerpo, re.M))
        if not campos:
            continue

        estado = next(
            (c for c, (b, _p) in clases.items()
             if re.search(rf"class {re.escape(c)} extends State<{re.escape(nombre)}>", b)),
            None)
        if estado is None:
            continue

        cuerpo_estado, pos = clases[estado]
        # `widget.place` es correcto: se tapa antes de buscar los desnudos.
        desnudo = re.sub(r"\bwidget\.\w+", " ", cuerpo_estado)
        propios = _nombres_declarados(cuerpo_estado)

        for campo in sorted(campos - propios):
            # Ni detrás de un punto (otro.campo) ni como etiqueta de argumento
            # con nombre (campo: ...), que no son referencias al campo.
            m = re.search(rf"(?<![.\w$]){re.escape(campo)}\b(?!\s*:)", desnudo)
            if m:
                linea = fuente[:pos + m.start()].count("\n") + 1
                problemas.append(
                    f"línea {linea}: {estado} usa '{campo}' a secas; es un campo "
                    f"de {nombre}, así que aquí se llama 'widget.{campo}'")
    return problemas


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
    #
    #    Se mira el código SIN COMENTARIOS pero CON cadenas: la interpolación
    #    vive dentro de las cadenas, y un `$` en un comentario no interpola.
    #    Y `.$1` NO es interpolación: son los campos posicionales de un record
    #    de Dart 3 (`pestanas[i].$1`). Por eso se excluye el `$` precedido de
    #    punto; dentro de una cadena eso es rarísimo y fuera es código normal.
    sin_comentarios = sin_comentarios_ni_cadenas(fuente, cadenas=True)
    for m in re.finditer(r"(?<!\\)(?<!\.)\$(?![A-Za-z_{$])", sin_comentarios):
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

    # 5. scrollables verticales dentro de un sliver
    problemas.extend(scrollable_dentro_de_sliver(limpio))

    # 6. campos del widget usados sin `widget.` dentro de su State
    problemas.extend(campos_sin_widget(limpio))

    return problemas


def main():
    # También `test/`: ahí vivía el `widget_test.dart` que generó
    # `flutter create`, con una clase `MyApp` que esta app nunca tuvo. Llevaba
    # roto desde el primer día y nadie lo vio, porque nada lo miraba.
    archivos = sorted(LIB.rglob("*.dart")) + sorted(PRUEBAS.rglob("*.dart"))
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
