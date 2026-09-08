/// Configuración de entorno.
///
/// El backend y el mock de Prism hablan el MISMO contrato (`openapi.json`), así
/// que la app funciona contra cualquiera de los dos sin tocar una línea. Eso es
/// lo que permite programar pantallas sin tener Postgres levantado.
///
/// Se elige al arrancar:
///
///   flutter run --dart-define=API_BASE=http://localhost:4010   // mock Prism
///   flutter run --dart-define=API_BASE=http://localhost:5001   // backend real
///
/// En el emulador de Android `localhost` es el propio emulador, no el Mac: ahí
/// la dirección del anfitrión es 10.0.2.2:5001. En el simulador de iOS,
/// localhost funciona tal cual.
class Config {
  /// 5001 y no 5000: el 5000 lo tiene la API de iBet en las máquinas del
  /// equipo, y en macOS también AirPlay Receiver. Es el puerto que
  /// docker-compose publica al Mac; dentro del contenedor el backend sigue en
  /// el 5000.
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:5001',
  );

  /// Idioma que se manda en `Accept-Language`. El backend compara por prefijo
  /// de dos letras, así que `es-MX` resuelve a español.
  static const String locale = String.fromEnvironment(
    'LOCALE',
    defaultValue: 'en',
  );

  /// Centro del Zócalo. Se usa como origen para "cerca de mí" mientras no haya
  /// permiso de ubicación concedido.
  static const double fallbackLat = 19.4326;
  static const double fallbackLon = -99.1332;
}
