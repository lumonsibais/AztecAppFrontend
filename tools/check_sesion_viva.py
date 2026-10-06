#!/usr/bin/env python3
"""Prueba la lógica de sesión del cliente contra el backend de verdad.

    python3 tools/check_sesion_viva.py http://localhost:5001

Por qué existe
--------------
`ApiClient` hace tres cosas que no se pueden comprobar leyendo el código: renovar
el token cuando el servidor contesta 401, no entrar en bucle si la renovación
también falla, y revocar LOS DOS tokens al salir. Son cosas del protocolo, no de
Dart, y aquí se reproducen paso por paso contra el servidor.

No sustituye a probar la app en el móvil —eso hay que hacerlo— pero sí responde
a la pregunta que importa antes de compilar: ¿el servidor se comporta como este
cliente supone? Si algún día cambia el backend, esto se rompe aquí en vez de en
un dispositivo.

Lo que se replica es exactamente lo que hace `lib/api/api_client.dart`; si esa
lógica cambia, este archivo cambia con ella.
"""
import json
import sys
import time
import urllib.error
import urllib.request

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:5001").rstrip("/")

VERDE, ROJO, GRIS, FIN = "\033[32m", "\033[31m", "\033[90m", "\033[0m"

fallos = []


def ok(texto):
    print(f"  {VERDE}ok{FIN}   {texto}")


def mal(texto):
    print(f"  {ROJO}FALLO{FIN} {texto}")
    fallos.append(texto)


def nota(texto):
    print(f"       {GRIS}{texto}{FIN}")


class Cliente:
    """El mismo comportamiento que ApiClient, en Python.

    Incluye el contador de peticiones, que es lo único que prueba que no hay
    bucle: un cliente mal hecho seguiría intentándolo y aquí se vería.
    """

    def __init__(self):
        self.access = None
        self.refresh = None
        self.peticiones = 0
        self.renovaciones = 0
        self.expirada = False

    # -- transporte -----------------------------------------------------------

    def _crudo(self, metodo, ruta, cuerpo=None, token=None):
        self.peticiones += 1
        req = urllib.request.Request(BASE + ruta, method=metodo)
        req.add_header("Accept", "application/json")
        bearer = token or self.access
        if bearer:
            req.add_header("Authorization", "Bearer " + bearer)
        datos = None
        if cuerpo is not None:
            req.add_header("Content-Type", "application/json")
            datos = json.dumps(cuerpo).encode()
        try:
            with urllib.request.urlopen(req, datos) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read() or b"{}")

    # -- lo que hace _enviar --------------------------------------------------

    def enviar(self, metodo, ruta, cuerpo=None, _reintentando=False):
        estado, cuerpo_r = self._crudo(metodo, ruta, cuerpo)

        if (estado == 401 and not _reintentando and self.refresh
                and not self._sin_renovar(ruta)):
            if self._refrescar():
                return self.enviar(metodo, ruta, cuerpo, _reintentando=True)
            self.expirada = True

        return estado, cuerpo_r

    # Rutas cuyo 401 no es "el token caducó": login y register no llevan token
    # —su 401 es la contraseña— y /refresh es el propio refresco.
    SIN_RENOVAR = ("/api/users/login", "/api/users/register",
                   "/api/users/refresh")

    def _sin_renovar(self, ruta):
        return ruta.startswith(self.SIN_RENOVAR)

    def _refrescar(self):
        self.renovaciones += 1
        # Se firma con el token de REFRESCO, no con el de acceso.
        estado, cuerpo = self._crudo("POST", "/api/users/refresh",
                                     token=self.refresh)
        if estado != 200:
            return False
        nuevo = (cuerpo.get("data") or {}).get("accessToken")
        if not nuevo:
            return False
        self.access = nuevo          # el de refresco NO cambia
        return True

    # -- sesión ---------------------------------------------------------------

    def entrar(self, email, password):
        estado, cuerpo = self.enviar("POST", "/api/users/login",
                                     {"email": email, "password": password})
        if estado == 200:
            self.access = cuerpo["data"]["accessToken"]
            self.refresh = cuerpo["data"]["refreshToken"]
        return estado

    def registrar(self, email, password):
        estado, cuerpo = self.enviar("POST", "/api/users/register",
                                     {"email": email, "password": password})
        if estado == 201:
            self.access = cuerpo["data"]["accessToken"]
            self.refresh = cuerpo["data"]["refreshToken"]
        return estado

    def salir(self):
        """Revoca los dos tokens, uno por llamada, sin que una impida la otra."""
        for token in (self.access, self.refresh):
            if token:
                self._crudo("POST", "/api/users/logout", token=token)
        self.access = self.refresh = None


def cuenta_nueva(cliente, etiqueta):
    email = f"sesion-{etiqueta}-{int(time.time() * 1000)}@example.com"
    estado = cliente.registrar(email, "testpassword123")
    if estado != 201:
        mal(f"no se pudo crear la cuenta de prueba ({estado})")
        return None
    return email


# ---------------------------------------------------------------------------

def caso_renovacion():
    print("\n1. El token caducado se renueva y la petición se repite")
    c = Cliente()
    if not cuenta_nueva(c, "renov"):
        return

    # Se revoca el access token a mano: es la forma de provocar el 401 sin
    # esperar 30 días a que caduque.
    c._crudo("POST", "/api/users/logout", token=c.access)
    nota("access token revocado a mano para provocar el 401")

    antes = c.peticiones
    estado, cuerpo = c.enviar("GET", "/api/users/profile")
    gastadas = c.peticiones - antes

    if estado == 200:
        ok(f"el perfil llegó igual ({estado}) tras renovar por dentro")
    else:
        mal(f"el perfil devolvió {estado}: la renovación no funcionó")

    if c.renovaciones == 1 and gastadas == 3:
        ok("3 peticiones: la que falló, el refresco y el reintento")
    else:
        mal(f"{gastadas} peticiones y {c.renovaciones} renovaciones "
            "(se esperaban 3 y 1)")

    if not c.expirada:
        ok("la sesión NO se marcó como expirada")
    else:
        mal("la sesión se marcó como expirada habiendo podido renovar")


def caso_sin_salida():
    print("\n2. Si el refresco también falla, se rinde en vez de dar vueltas")
    c = Cliente()
    if not cuenta_nueva(c, "muerta"):
        return

    # Se guardan los tokens, se revocan los dos, y se le devuelven al cliente:
    # es la situación de una app que llevaba meses cerrada y arranca con lo que
    # tenía guardado.
    muerto_a, muerto_r = c.access, c.refresh
    c.salir()
    c.access, c.refresh = muerto_a, muerto_r
    nota("los dos tokens revocados; el cliente arranca con ellos igualmente")

    c2 = c
    antes = c2.peticiones
    estado, _ = c2.enviar("GET", "/api/users/profile")
    gastadas = c2.peticiones - antes

    if estado == 401:
        ok("devuelve 401 al llamador")
    else:
        mal(f"devolvió {estado}, se esperaba 401")

    if gastadas == 2 and c2.renovaciones == 1:
        ok("2 peticiones: la que falló y el refresco. Sin bucle")
    else:
        mal(f"{gastadas} peticiones y {c2.renovaciones} renovaciones "
            "(se esperaban 2 y 1) — posible bucle")

    if c2.expirada:
        ok("la sesión se marcó como expirada: la app vuelve a pedir entrada")
    else:
        mal("la sesión no se marcó como expirada")


def caso_salir_de_verdad():
    print("\n3. Salir revoca LOS DOS tokens")
    c = Cliente()
    if not cuenta_nueva(c, "salir"):
        return
    refresh = c.refresh

    c.salir()

    estado, _ = c._crudo("POST", "/api/users/refresh", token=refresh)
    if estado == 401:
        ok("el token de refresco ya no vale")
    else:
        mal(f"el refresco devolvió {estado}: con él se pueden pedir tokens "
            "nuevos después de 'cerrar sesión'")
        nota("esto es lo que pasaba antes: /logout revoca UN token por llamada, "
             "y solo se llamaba con el de acceso")


def caso_guardados():
    print("\n4. Saved funciona de punta a punta con la sesión")
    c = Cliente()
    if not cuenta_nueva(c, "saved"):
        return

    estado, cuerpo = c.enviar("GET", "/api/places/")
    sitios = (cuerpo.get("data") or {}).get("places") or []
    if not sitios:
        nota("el catálogo está vacío; siembra la base para probar esto")
        return
    pid = sitios[0]["id"]

    estado, _ = c.enviar("POST", f"/api/places/{pid}/save")
    if estado in (200, 201):
        ok(f"guardado ({estado})")
    else:
        mal(f"guardar devolvió {estado}")

    estado, cuerpo = c.enviar("GET", "/api/places/saved")
    guardados = (cuerpo.get("data") or {}).get("places") or []
    if any(p["id"] == pid for p in guardados):
        ok("aparece en la lista de guardados")
    else:
        mal("no aparece en la lista de guardados")

    estado, _ = c.enviar("DELETE", f"/api/places/{pid}/save")
    estado, cuerpo = c.enviar("GET", "/api/places/saved")
    guardados = (cuerpo.get("data") or {}).get("places") or []
    if not any(p["id"] == pid for p in guardados):
        ok("y desaparece al quitarlo")
    else:
        mal("sigue en la lista después de quitarlo")


def caso_invitado():
    print("\n5. Sin sesión, lo de la cuenta pide entrar y lo público no")
    c = Cliente()

    estado, _ = c.enviar("GET", "/api/places/")
    if estado == 200:
        ok("el catálogo se ve como invitado")
    else:
        mal(f"el catálogo devolvió {estado} sin sesión")

    estado, _ = c.enviar("GET", "/api/places/saved")
    if estado == 401:
        ok("Saved pide entrar (401)")
    else:
        mal(f"Saved devolvió {estado} sin sesión, se esperaba 401")

    if c.renovaciones == 0:
        ok("no se intentó renovar nada sin token de refresco")
    else:
        mal("intentó renovar sin tener token de refresco")


def caso_contrasena_mala():
    print("\n6. Entrar con la contraseña mal no toca la sesión que ya había")
    c = Cliente()
    email = cuenta_nueva(c, "pwmala")
    if not email:
        return
    refresh = c.refresh

    antes = c.renovaciones
    estado = c.entrar(email, "estanoeslacontrasena")

    if estado == 401:
        ok("devuelve 401, como debe")
    else:
        mal(f"entrar con la contraseña mal devolvió {estado}")

    if c.renovaciones == antes:
        ok("no se gastó ningún refresco")
    else:
        mal("renovó el token por un 401 que era de contraseña incorrecta")
        nota("por eso /users/login y /users/register están excluidos del "
             "reintento: su 401 no significa 'el token caducó'")

    if not c.expirada:
        ok("la sesión anterior sigue en pie")
    else:
        mal("un intento de entrada fallido borró la sesión que ya había")

    estado, _ = c._crudo("POST", "/api/users/refresh", token=refresh)
    if estado == 200:
        ok("y el token de refresco sigue valiendo")
    else:
        mal(f"el token de refresco quedó inservible ({estado})")


def main():
    print(f"backend: {BASE}")
    try:
        urllib.request.urlopen(BASE + "/api/places/", timeout=5)
    except Exception as e:
        print(f"{ROJO}No se pudo hablar con el backend: {e}{FIN}")
        print("Levántalo con:  docker compose up -d")
        return 2

    caso_renovacion()
    caso_sin_salida()
    caso_salir_de_verdad()
    caso_guardados()
    caso_invitado()
    caso_contrasena_mala()

    print()
    if fallos:
        print(f"{ROJO}{len(fallos)} fallo(s).{FIN}")
        return 1
    print(f"{VERDE}OK  la lógica de sesión concuerda con el backend.{FIN}")
    print(f"    {GRIS}Falta probarlo en el móvil: esto comprueba el protocolo, "
          f"no la app.{FIN}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
