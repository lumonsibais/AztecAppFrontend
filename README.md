# AztecApp Explorer — frontend

App Flutter para las cuatro pestañas del MVP: **Map, Explore, History y Saved**.

## Arrancar

El proyecto trae `lib/` y `pubspec.yaml`, pero no las carpetas nativas. Se
generan una vez, sin tocar nada de lo que ya hay:

```bash
cd AztecAppFrontend
flutter create --platforms=ios,android --project-name aztec_app .
flutter pub get
```

> **`--project-name aztec_app` no es opcional, y va en CADA `flutter create`**
> que corras en esta carpeta. Sin él, Flutter toma el nombre del directorio
> —`AztecAppFrontend`— y se planta: los nombres de paquete Dart solo admiten
> minúsculas, dígitos y guiones bajos. El error es claro, pero deja el comando
> a medias sin añadir la plataforma, y luego uno se pregunta por qué el
> dispositivo no aparece.

> `flutter create` sobre un proyecto existente solo añade lo que falta. Si aun
> así te reescribe `pubspec.yaml` o `lib/main.dart`, recupéralos con
> `git checkout -- pubspec.yaml lib/main.dart`.

### Para verlo sin simulador

En un Mac con macOS 12 el simulador de iOS da guerra (Xcode se queda en la 14.2
en Monterey). Para el día a día del front van mejor estas dos:

```bash
# Chrome — sin Xcode, sin CocoaPods. El backend trae CORS abierto para /api/*.
flutter create --platforms=web --project-name aztec_app .
flutter run -d chrome --dart-define=API_BASE=http://localhost:5001

# App nativa de macOS — necesita Xcode.
flutter create --platforms=macos --project-name aztec_app .
/usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" macos/Runner/DebugProfile.entitlements
/usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" macos/Runner/Release.entitlements
flutter run -d macos --dart-define=API_BASE=http://localhost:5001
```

Las dos líneas de `PlistBuddy` no son opcionales: las apps de macOS corren en
sandbox y **sin `network.client` la app abre pero toda petición falla**, sin
decir por qué.

Después, contra el backend local:

```bash
# en AztecApp/
docker compose up          # levanta base, migra, siembra y sirve

# en AztecAppFrontend/
flutter run --dart-define=API_BASE=http://localhost:5001
```

O **sin backend ni base de datos**, contra el mock del contrato:

```bash
# en AztecApp/
npx @stoplight/prism-cli mock openapi.json --port 4010

# en AztecAppFrontend/
flutter run --dart-define=API_BASE=http://localhost:4010
```

En español: `--dart-define=LOCALE=es-MX`.

**El puerto es el 5001, no el 5000:** en las máquinas del equipo el 5000 ya lo
tiene la API de iBet, y en macOS también AirPlay Receiver. Dentro del
contenedor el backend sigue en el 5000; lo que cambia es el puerto que
docker-compose publica al Mac.

**Emulador de Android:** `localhost` es el propio emulador, no tu Mac. Usa
`--dart-define=API_BASE=http://10.0.2.2:5001`. En el simulador de iOS
`localhost` funciona tal cual.

## Cómo está montado

```
lib/
  config.dart          entorno: a qué servidor apunta y en qué idioma
  api/
    models.dart        los modelos, escritos a mano contra openapi.json
    api_client.dart    el cliente: desenvuelve {success, data} una sola vez
                       y renueva el token cuando el servidor da 401
  services/
    session.dart       quién está dentro; tokens en el Keychain/Keystore
    session_scope.dart reparte la sesión por el árbol de widgets
  screens/             una pantalla por pestaña, más la ficha de sitio
    auth/              crear cuenta y entrar
    profile/           la cuenta: correo, desbloqueo y salir
  widgets/             la tarjeta de sitio y el botón de cuenta
  theme.dart           colores y tipografía del diseño
```

Una sola dependencia de red: `http`. Sin dio, sin retrofit, sin `build_runner`.
La capa de datos son dos archivos que se leen de una sentada y no hay un paso
de generación que se pueda quedar a medias.

## Por qué los modelos están escritos a mano

El generador de OpenAPI para Dart arrastra `build_runner` y unos ciento
cincuenta archivos para un contrato de treinta y seis operaciones. Para este
tamaño no compensa.

El riesgo de escribirlos a mano es que se desincronicen del backend en
silencio, y ese riesgo está cubierto por tres verificaciones que **no
necesitan Dart instalado**:

```bash
python3 tools/check_dart_contract.py                       # modelos vs. openapi.json
python3 tools/check_against_live.py http://localhost:5001  # modelos vs. respuestas reales
python3 tools/sanity_dart.py                               # llaves, imports, interpolaciones
python3 tools/check_sesion_viva.py http://localhost:5001   # la lógica de sesión vs. el backend
```

La segunda es la que más vale: compara los modelos con lo que el servidor manda
**ahora mismo**. Caza justo lo que tumba una app Flutter en el móvil —un campo
que llega `null` y se lee sin `?`, una clave mal escrita, un tipo que no
cuadra— y que el compilador de Dart no ve, porque para él `j['claveMalEscrita']`
es un `null` perfectamente legal.

La cuarta reproduce en Python la lógica de sesión de `api_client.dart` y la corre
contra el backend: que un 401 renueve el token y repita la petición, que no entre
en bucle si la renovación también falla, que salir revoque los dos tokens, y que
un 401 por contraseña incorrecta no se confunda con un token caducado. Son cosas
del protocolo, no de Dart, y así se rompen aquí en vez de en un dispositivo.

Ninguna sustituye a `flutter analyze`, que comprueba tipos y sintaxis y hay que
correr en el Mac.

## La sesión

El token de acceso vive 30 días y el de refresco 90. Con el de refresco se piden
tokens de acceso nuevos **sin contraseña**, así que a efectos prácticos ES la
contraseña: por eso los dos van a `flutter_secure_storage` —Keychain en iOS,
Keystore en Android— y no a `shared_preferences`, que los dejaría en un fichero
en claro dentro del sandbox de la app.

Tres cosas que no se ven leyendo las pantallas:

- **La renovación es automática y de una sola vez.** Al abrir la app salen varias
  peticiones juntas; si el token ha caducado todas reciben 401 a la vez. El
  cliente comparte un único `Future` de refresco, así que se pide un token y las
  demás esperan ese mismo resultado.
- **Salir revoca los dos tokens.** `/users/logout` revoca el token con el que se
  le llama, uno por llamada. Llamarlo solo con el de acceso —que era lo que
  había— dejaba el de refresco vivo 90 días: "cerrar sesión" no cerraba nada.
- **Se puede recorrer la app entera sin cuenta.** La cuenta se pide en el momento
  en que hace falta —al tocar un corazón, al abrir Saved, al pulsar desbloquear—
  y diciendo para qué. Obligar a entrar en el arranque haría que nadie llegara a
  ver para qué sirve.

**Android:** `minSdkVersion` está fijado a **23** en `android/app/build.gradle`,
no en `flutter.minSdkVersion` (que es 21). Lo exige
`flutter_secure_storage` con `encryptedSharedPreferences`. Con 21 la compilación
falla en el manifest merger y el error no menciona el paquete por ningún lado.

## Lo que falta, y por qué

- **Google Maps.** `google_maps_flutter` exige dar de alta una clave de API y
  tocar los proyectos nativos de iOS y Android: es configuración de cuentas,
  no de código. Mientras tanto, `map_screen.dart` pinta los polígonos del
  backend con un `CustomPainter`, que prueba lo que hay que probar ahora —que
  el overlay llega, que `surfaceType` decide el color y que el conmutador
  1500/2026 funciona de punta a punta—. Al enchufar Google Maps,
  `LakeFeature.rings` va tal cual a `Polygon(points: ...)`.
- **Entrar con Google y con Apple.** Los dos necesitan configuración en sus
  consolas y un endpoint que el backend todavía no tiene. No se pinta un botón
  que no funciona: por ahora la cuenta es correo y contraseña, que sí funciona de
  punta a punta.
- **La compra.** El backend ya cobra por las tiendas —verifica recibos de la App
  Store y de Google Play, tiene `/payments/confirm` y `/payments/restore`— y lo
  que falta es la parte del cliente con `in_app_purchase`. No se puede escribir
  entera sin que existan los productos dados de alta en App Store Connect y en
  Play Console, porque no habría contra qué probarla. El botón de desbloquear ya
  hace la mitad que sí depende de nosotros: pedir la cuenta, que es a quien se le
  concede el acceso.
- **Restore Purchases.** Apple lo exige en revisión para productos no
  consumibles. El endpoint está; el botón va con la compra.

## La línea del paywall

Conviene tenerla clara al mirar la ficha de un sitio, porque no es la obvia:

| Se ve siempre | Va con el desbloqueo |
|---|---|
| Tarifa de taquilla en MXN y USD | Descripción |
| Horarios | `whyVisit` |
| Cómo llegar | Contexto histórico |
| Avisos de seguridad | Audio de los tours |

Los 15 dólares son lo que cobramos nosotros. Los 95 pesos son lo que cobra el
Museo de Antropología en su taquilla: información del mundo real que está en
internet, y esconderla solo mandaría al viajero a buscarla fuera de la app.
