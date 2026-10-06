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
import time
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
    # Tours. El listado da el teaser —sin paradas— y la ficha da el tour
    # entero, así que las dos formas se comprueban: son respuestas distintas
    # del mismo schema y la app tiene que aguantar las dos.
    ("Tour", "/api/tours/", lambda d: d["tours"][0] if d["tours"] else None),
    ("Tour", "/api/tours/free", lambda d: d["tours"][0] if d["tours"] else None),
    ("Tour", "__ficha_de_tour__", lambda d: d),
    ("TourStatistics", "/api/tours/",
     lambda d: d["tours"][0]["statistics"] if d["tours"] else None),
]

# Sondas que necesitan una cuenta CON el contenido desbloqueado. Son las que
# miran la mitad de pago de cada respuesta, que es justo donde el teaser manda
# nulos y el modelo se puede equivocar.
SONDAS_DESBLOQUEADAS = [
    ("Tour", "__ficha_de_tour__", lambda d: d),
    ("TourStop", "__ficha_de_tour__", lambda d: (d.get("stops") or [None])[0]),
    ("TourAudio", "__ficha_de_tour__",
     lambda d: ((d.get("stops") or [{}])[0] or {}).get("audio")),
    ("Place", "__primer_sitio__", lambda d: d),
    ("HistoricalArticle", "__primer_articulo__", lambda d: d),
]

# `__ficha_de_tour__` no es una ruta: se resuelve al arrancar pidiendo el
# listado y quedándose con el primer id. Escribir un id a mano ataría la
# comprobación a la siembra actual, y la siembra cambia.
def resolver(base, marcador, token=None):
    """Convierte un marcador `__x__` en la ruta de un objeto que exista ahora.

    Escribir los ids a mano ataría estas comprobaciones a la siembra actual, y
    la siembra cambia cada vez que se toca el catálogo.
    """
    if marcador == "__ficha_de_tour__":
        datos = (pedir(base, "/api/tours/", token) or {}).get("data") or {}
        tours = datos.get("tours") or []
        return "/api/tours/" + tours[0]["id"] if tours else None

    if marcador == "__primer_sitio__":
        datos = (pedir(base, "/api/places/", token) or {}).get("data") or {}
        sitios = datos.get("places") or []
        return "/api/places/" + sitios[0]["id"] if sitios else None

    if marcador == "__primer_articulo__":
        datos = ((pedir(base, "/api/historical/chronology", token) or {})
                 .get("data") or {})
        articulos = datos.get("content") or []
        return ("/api/historical/content/" + articulos[0]["id"]
                if articulos else None)

    return marcador


def resolver_ficha_de_tour(base):
    """La ruta de la ficha del primer tour que haya, o None si no hay ninguno."""
    datos = (pedir(base, "/api/tours/") or {}).get("data") or {}
    if not datos.get("tours"):
        return None
    return "/api/tours/" + datos["tours"][0]["id"]

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
    # El tipo puede llevar genéricos: `as List<dynamic>?`. Sin admitirlos, el
    # (\w+) paraba en 'List', el '?' quedaba fuera y la lectura se daba por
    # obligatoria. Salía como un fallo inventado en cuanto un modelo leía una
    # lista opcional.
    tipo = r"(\w+(?:<[^>]*>)?)"
    for m in re.finditer(r"\b\w+\[['\"](\w+)['\"]\]\s+as\s+" + tipo + r"(\?)?", cuerpo):
        salida.append((m.group(1), m.group(2).split("<")[0], m.group(3) is not None))
    for m in re.finditer(
            r"\(\s*\w+\[['\"](\w+)['\"]\]\s+as\s+" + tipo + r"\s*\)", cuerpo):
        salida.append((m.group(1), m.group(2).split("<")[0], False))
    return salida


def claves_con_guarda(cuerpo: str):
    """Claves protegidas por `j['x'] == null ? null : ...`.

    Ese ternario hace la lectura segura aunque el cast de dentro no lleve '?':
    la rama del cast solo se ejecuta cuando el valor no es nulo.
    """
    guardadas = set(re.findall(r"\b\w+\[['\"](\w+)['\"]\]\s*==\s*null", cuerpo))
    # `(j['x'] as List?) ?? const []` es igual de seguro que el ternario.
    guardadas |= set(re.findall(
        r"\b\w+\[['\"](\w+)['\"]\][^)]*\)\s*\?\?", cuerpo))
    return guardadas


def pedir(base, ruta, token=None, metodo="GET", cuerpo=None):
    cabeceras = {"Accept": "application/json"}
    if token:
        cabeceras["Authorization"] = "Bearer " + token
    datos = None
    if cuerpo is not None:
        cabeceras["Content-Type"] = "application/json"
        datos = json.dumps(cuerpo).encode()
    req = urllib.request.Request(
        base + ruta, headers=cabeceras, method=metodo, data=datos)
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode())


def cuenta_desbloqueada(base):
    """Una cuenta de usar y tirar con el contenido de pago desbloqueado.

    Es lo que hace falta para poder mirar la MITAD DE PAGO de las respuestas:
    las paradas de un tour, el audio, el cuerpo de un artículo, el `whyVisit` de
    un sitio. Sin ella, este comprobador solo veía los teasers —justo donde no
    hay campos que puedan llegar nulos— y daba luz verde sin haber mirado lo que
    la app enseña a quien pagó.

    Solo funciona con PAYMENTS_ALLOW_UNVERIFIED encendido, que es como corre el
    backend en local. Si no lo está, se devuelve None y esas sondas se saltan
    diciéndolo, en vez de fallar.
    """
    email = f"contrato-{int(time.time() * 1000)}@example.com"
    try:
        alta = pedir(base, "/api/users/register", metodo="POST",
                     cuerpo={"email": email, "password": "testpassword123"})
        token = alta["data"]["accessToken"]
        pedir(base, "/api/payments/confirm", token=token, metodo="POST",
              cuerpo={"provider": "apple", "externalId": f"contrato-{email}"})
        return token
    except (urllib.error.HTTPError, urllib.error.URLError, KeyError, OSError):
        return None


def main():
    base = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:5001").rstrip("/")
    trozos = clases_dart(MODELOS.read_text())

    problemas, revisadas = [], 0

    token = cuenta_desbloqueada(base)
    if token is None:
        print("aviso  no pude crear una cuenta con el contenido desbloqueado.")
        print("       Las sondas de la mitad de pago se saltan. Para que "
              "corran, levanta el")
        print("       backend con PAYMENTS_ALLOW_UNVERIFIED=true.")

    sondas = [(c, r, e, None) for c, r, e in SONDAS]
    if token:
        sondas += [(c, r, e, token) for c, r, e in SONDAS_DESBLOQUEADAS]

    for clase, ruta, extraer, tok in sondas:
        if ruta.startswith("__"):
            resuelta = resolver(base, ruta, tok)
            if resuelta is None:
                print(f"aviso  no hay datos sembrados para {ruta}; "
                      f"me salto {clase}")
                continue
            ruta = resuelta

        try:
            sobre = pedir(base, ruta, tok)
        except (urllib.error.URLError, OSError) as e:
            print(f"ERROR  no pude llamar a {base}{ruta}: {e}", file=sys.stderr)
            print("       ¿está levantado el backend (o el mock)?", file=sys.stderr)
            return 2

        etiqueta = f"{ruta}{' (desbloqueado)' if tok else ''}"
        muestra = extraer(sobre.get("data") or {})
        if muestra is None:
            print(f"aviso  {etiqueta} no devolvió ejemplos de {clase}; "
                  "me lo salto")
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
                        f"{etiqueta} no lo manda")
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
