#!/usr/bin/env python3
"""Contrasta los modelos Dart contra el OpenAPI del backend.

    python3 tools/check_dart_contract.py

Por qué existe: los modelos de `lib/api/models.dart` están escritos a mano, y
un modelo escrito a mano se desincroniza del contrato en silencio. El compilador
de Dart no ayuda —para él `j['nombreMalEscrito']` es null perfectamente válido,
y el fallo aparece en el móvil, no en el build.

Esto revisa dos cosas, que son justo las que rompen en producción:

  1. TODA clave que un `fromJson` lee existe en el schema correspondiente del
     spec. Una errata como `j['tagLine']` se caza aquí.
  2. TODO campo que el spec marca `nullable` se lee de forma que admita null.
     Leer `j['imageUrl'] as String` cuando el servidor manda null es un crash
     en tiempo de ejecución.

No sustituye a compilar la app: comprueba el contrato, no la sintaxis.
"""
import json
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
MODELOS = RAIZ / "lib" / "api" / "models.dart"

# Dónde vive el spec. Se acepta que el repo del backend esté al lado.
CANDIDATOS = [
    RAIZ / "openapi.json",
    RAIZ.parent / "AztecApp" / "openapi.json",
]

# Clase Dart -> schema del spec.
MAPA = {
    "PlaceLocation": "Location",
    "Badges": "Badges",
    "ContentAccess": "ContentAccess",
    "NearbyServices": "NearbyServices",
    "EntryFee": "EntryFee",
    "HistoricalContext": "HistoricalContext",
    "Place": "Place",
    "HistoricalArticle": "HistoricalContent",
    "Topic": "Topic",
    "LakeOverlay": "LakeOverlay",
    "AccessState": "AccessState",
    "UserStats": "UserStats",
    "User": "User",
    "AuthTokens": "Auth",
}

# LakeFeature lee de dos sitios a la vez (properties y geometry), así que se
# comprueba aparte.
ESPECIALES = {
    "LakeFeature": {
        "props": ("LakeFeatureProperties",
                  {"name", "surfaceType", "yearEstimate",
                   "tenochtitlanName", "description"}),
        "raiz": ("LakeFeature", {"id", "properties", "geometry"}),
    }
}


def cargar_spec():
    for ruta in CANDIDATOS:
        if ruta.exists():
            return json.loads(ruta.read_text()), ruta
    print("ERROR  no encuentro openapi.json. Buscado en:", file=sys.stderr)
    for r in CANDIDATOS:
        print(f"         {r}", file=sys.stderr)
    print("       Genéralo con `python spec.py` en el repo del backend.",
          file=sys.stderr)
    sys.exit(2)


def clases_dart(fuente: str):
    """Trocea el archivo en {NombreClase: cuerpo}."""
    trozos = {}
    marcas = [(m.group(1), m.start()) for m in re.finditer(r"^class (\w+)", fuente, re.M)]
    for i, (nombre, inicio) in enumerate(marcas):
        fin = marcas[i + 1][1] if i + 1 < len(marcas) else len(fuente)
        trozos[nombre] = fuente[inicio:fin]
    return trozos


def claves_leidas(cuerpo: str):
    """Las claves JSON que el cuerpo de la clase lee: j['x'], props['x']..."""
    return set(re.findall(r"\b\w+\[['\"](\w+)['\"]\]", cuerpo))


def lecturas_no_nulas(cuerpo: str):
    """Claves leídas con un cast que NO admite null: `as String` sin `?`."""
    sin_null = set()
    for m in re.finditer(
        r"\b\w+\[['\"](\w+)['\"]\]\s+as\s+(\w+)(\?)?", cuerpo
    ):
        clave, _tipo, interrogante = m.group(1), m.group(2), m.group(3)
        if interrogante is None:
            sin_null.add(clave)
    # `(j['x'] as num).toDouble()` también es una lectura no nula.
    for m in re.finditer(r"\(\s*\w+\[['\"](\w+)['\"]\]\s+as\s+num\s*\)", cuerpo):
        sin_null.add(m.group(1))
    return sin_null


def claves_con_guarda(cuerpo: str):
    """Claves protegidas por `j['x'] == null ? null : ...`.

    Ese ternario hace la lectura segura aunque el cast de dentro no lleve '?':
    la rama del cast solo se ejecuta cuando el valor no es nulo.
    """
    return set(re.findall(r"\b\w+\[['\"](\w+)['\"]\]\s*==\s*null", cuerpo))


def campos_del_schema(spec, nombre):
    esquema = spec["components"]["schemas"].get(nombre)
    if esquema is None:
        return None, set()
    props = esquema.get("properties", {})
    nulos = {
        k for k, v in props.items()
        if v.get("nullable") or (isinstance(v.get("type"), list) and "null" in v["type"])
    }
    return set(props), nulos


def main():
    spec, ruta_spec = cargar_spec()
    fuente = MODELOS.read_text()
    trozos = clases_dart(fuente)

    problemas = []
    revisadas = 0

    for clase, schema in MAPA.items():
        cuerpo = trozos.get(clase)
        if cuerpo is None:
            problemas.append(f"{clase}: no encuentro la clase en models.dart")
            continue

        campos, nulos = campos_del_schema(spec, schema)
        if campos is None:
            problemas.append(f"{clase}: el spec no tiene el schema '{schema}'")
            continue

        revisadas += 1
        leidas = claves_leidas(cuerpo)

        inventadas = leidas - campos
        if inventadas:
            problemas.append(
                f"{clase} lee claves que el spec ({schema}) no declara: "
                f"{sorted(inventadas)}"
            )

        arriesgadas = (lecturas_no_nulas(cuerpo) - claves_con_guarda(cuerpo)) & nulos
        if arriesgadas:
            problemas.append(
                f"{clase} lee sin admitir null campos que el spec marca "
                f"nullable: {sorted(arriesgadas)}"
            )

    # LakeFeature, que mezcla dos schemas
    cuerpo = trozos.get("LakeFeature")
    if cuerpo:
        revisadas += 1
        campos_props, nulos_props = campos_del_schema(spec, "LakeFeatureProperties")
        campos_raiz, _ = campos_del_schema(spec, "LakeFeature")
        permitidas = campos_props | campos_raiz | {"coordinates"}
        inventadas = claves_leidas(cuerpo) - permitidas
        if inventadas:
            problemas.append(
                f"LakeFeature lee claves que el spec no declara: {sorted(inventadas)}")
        arriesgadas = (lecturas_no_nulas(cuerpo) - claves_con_guarda(cuerpo)) & nulos_props
        if arriesgadas:
            problemas.append(
                f"LakeFeature lee sin admitir null: {sorted(arriesgadas)}")

    print(f"spec: {ruta_spec}")
    print(f"clases contrastadas: {revisadas}")

    if problemas:
        print(f"\n{len(problemas)} problema(s):\n")
        for p in problemas:
            print(f"  - {p}")
        return 1

    print("\nOK  los modelos Dart concuerdan con el contrato.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
