#!/usr/bin/env python3
"""Contrasta los modelos Dart contra respuestas REALES del backend.

    python3 tools/check_against_live.py http://localhost:5001

`check_dart_contract.py` compara los modelos con el spec. Esto va un paso más
allá y compara los modelos con lo que el servidor manda AHORA MISMO, que es lo
único que la app va a recibir de verdad.

Busca lo que tumba una app Flutter en tiempo de ejecución:

  - una clave que el modelo lee con cast no nulo y llega como null
  - una clave requerida por el modelo que no viene en la respuesta
  - un tipo distinto del esperado (un int donde el modelo espera String)

Todo lo hace desde fuera, leyendo `models.dart`: no hace falta Dart instalado.
"""
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

RAIZ = pathlib.Path(__file__).resolve().parent.parent
MODELOS = RAIZ / "lib" / "api" / "models.dart"

# Clase Dart -> de dónde sacar un objeto de ejemplo en la respuesta.
# (ruta, extractor)
SONDAS = [
    ("Place", "/api/places/", lambda d: d["places"][0] if d["places"] else None),
    ("Place", "/api/places/nearby?latitude=19.4326&longitude=-99.1332&radius=8",
     lambda d: d["places"][0] if d["places"] else None),
    ("HistoricalArticle", "/api/historical/chronology",
     lambda d: d["content"][0] if d["content"] else None),
    ("Topic", "/api/historical/topics",
     lambda d: d["topics"][0] if d["topics"] else None),
    ("LakeOverlay", "/api/historical/lake-view?year=1500", lambda d: d),
]

TIPOS_DART = {
    "String": str,
    "bool": bool,
    "int": int,
    "double": float,
    "num": (int, float),
}


def clases_dart(fuente: str):
    trozos = {}
    marcas = [(m.group(1), m.start()) for m in re.finditer(r"^class (\w+)", fuente, re.M)]
    for i, (nombre, inicio) in enumerate(marcas):
        fin = marcas[i + 1][1] if i + 1 < len(marcas) else len(fuente)
        trozos[nombre] = fuente[inicio:fin]
    return trozos


def lecturas(cuerpo: str):
    """[(clave, tipo_dart, admite_null)] de los casts explícitos del fromJson."""
    salida = []
    for m in re.finditer(r"\b\w+\[['\"](\w+)['\"]\]\s+as\s+(\w+)(\?)?", cuerpo):
        salida.append((m.group(1), m.group(2), m.group(3) is not None))
    for m in re.finditer(r"\(\s*\w+\[['\"](\w+)['\"]\]\s+as\s+(\w+)\s*\)", cuerpo):
        salida.append((m.group(1), m.group(2), False))
    return salida


def claves_con_guarda(cuerpo: str):
    """Claves protegidas por `j['x'] == null ? null : ...`.

    Ese ternario hace la lectura segura aunque el cast de dentro no lleve '?':
    la rama del cast solo se ejecuta cuando el valor no es nulo.
    """
    return set(re.findall(r"\b\w+\[['\"](\w+)['\"]\]\s*==\s*null", cuerpo))


def pedir(base, ruta):
    req = urllib.request.Request(
        base + ruta, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode())


def main():
    base = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:5001").rstrip("/")
    trozos = clases_dart(MODELOS.read_text())

    problemas, revisadas = [], 0

    for clase, ruta, extraer in SONDAS:
        try:
            sobre = pedir(base, ruta)
        except (urllib.error.URLError, OSError) as e:
            print(f"ERROR  no pude llamar a {base}{ruta}: {e}", file=sys.stderr)
            print("       ¿está levantado el backend (o el mock)?", file=sys.stderr)
            return 2

        muestra = extraer(sobre.get("data") or {})
        if muestra is None:
            print(f"aviso  {ruta} no devolvió ejemplos de {clase}; me lo salto")
            continue

        cuerpo = trozos.get(clase)
        if cuerpo is None:
            problemas.append(f"{clase}: no está en models.dart")
            continue

        revisadas += 1
        guardadas = claves_con_guarda(cuerpo)
        for clave, tipo, admite_null in lecturas(cuerpo):
            admite_null = admite_null or clave in guardadas
            if clave not in muestra:
                # Puede ser un campo que solo aparece en otra vista; solo es
                # grave si el modelo lo lee sin admitir null.
                if not admite_null:
                    problemas.append(
                        f"{clase}.{clave}: el modelo lo lee obligatorio pero "
                        f"{ruta} no lo manda")
                continue

            valor = muestra[clave]
            if valor is None:
                if not admite_null:
                    problemas.append(
                        f"{clase}.{clave}: llega NULL y el modelo lo lee como "
                        f"'{tipo}' sin '?' — eso revienta en el móvil")
                continue

            esperado = TIPOS_DART.get(tipo)
            if esperado and not isinstance(valor, esperado):
                # bool es subclase de int en Python: se filtra el falso positivo.
                if not (tipo in ("int", "num") and isinstance(valor, bool)):
                    problemas.append(
                        f"{clase}.{clave}: el modelo espera {tipo} y llega "
                        f"{type(valor).__name__} ({valor!r})")

    print(f"servidor: {base}")
    print(f"clases contrastadas contra datos reales: {revisadas}")

    if problemas:
        print(f"\n{len(problemas)} problema(s):\n")
        for p in problemas:
            print(f"  - {p}")
        return 1

    print("\nOK  los modelos aguantan lo que el servidor manda de verdad.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
