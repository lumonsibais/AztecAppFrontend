import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'models.dart';

/// Error de la API con el mensaje que mandó el servidor.
///
/// El backend contesta `{"success": false, "error": "...", "details": {...}}`.
/// Enseñar ese `error` al usuario es mejor que un "algo salió mal" genérico.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? details;

  ApiException(this.statusCode, this.message, [this.details]);

  /// El contenido existe pero hace falta el desbloqueo.
  bool get necesitaDesbloqueo => statusCode == 403;
  bool get noAutenticado => statusCode == 401;
  bool get noEncontrado => statusCode == 404;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Cliente de la API de AztecApp.
///
/// Todas las respuestas del backend vienen envueltas en
/// `{"success": bool, "data": {...}}`. Ese desenvoltorio se hace UNA vez, aquí,
/// para que ninguna pantalla tenga que saber que el sobre existe.
class ApiClient {
  ApiClient({http.Client? cliente, String? baseUrl})
      : _http = cliente ?? http.Client(),
        _base = baseUrl ?? Config.apiBase;

  final http.Client _http;
  final String _base;

  String? _accessToken;
  String? _refreshToken;

  /// Se llama cuando el token de acceso se renueva, para que la sesión lo
  /// guarde. Lo enchufa `Session`; sin ello el token nuevo viviría solo en
  /// memoria y al reabrir la app se volvería a usar el viejo.
  Future<void> Function(String accessToken)? alRenovar;

  /// Se llama cuando el refresco falla y la sesión ya no vale. Lo enchufa
  /// `Session` para limpiar el almacén y mandar a la pantalla de entrada.
  Future<void> Function()? alExpirar;

  bool get haySesion => _accessToken != null;

  void usarTokens(AuthTokens tokens) {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
  }

  void olvidarSesion() {
    _accessToken = null;
    _refreshToken = null;
  }

  /// `token` fuerza cuál se manda. Solo lo usa el refresco, que tiene que
  /// firmar con el token de refresco en lugar del de acceso.
  Map<String, String> _cabeceras({bool conCuerpo = false, String? token}) {
    final h = <String, String>{
      'Accept': 'application/json',
      // El backend compara por prefijo de dos letras: es-MX resuelve a es.
      'Accept-Language': Config.locale,
    };
    if (conCuerpo) h['Content-Type'] = 'application/json';
    final bearer = token ?? _accessToken;
    if (bearer != null) h['Authorization'] = 'Bearer $bearer';
    return h;
  }

  Uri _uri(String ruta, [Map<String, dynamic>? query]) {
    final limpio = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) limpio[k] = '$v';
    });
    return Uri.parse('$_base$ruta').replace(
      queryParameters: limpio.isEmpty ? null : limpio,
    );
  }

  /// Ejecuta y devuelve el contenido de `data` ya desenvuelto.
  ///
  /// Si el servidor contesta 401 y hay token de refresco, lo canjea por un
  /// token de acceso nuevo y repite la petición UNA vez. `reintentando` es lo
  /// que evita que un 401 del propio refresco entre en bucle.
  Future<dynamic> _enviar(
    String metodo,
    String ruta, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? cuerpo,
    bool reintentando = false,
  }) async {
    final r = await _crudo(metodo, ruta, query: query, cuerpo: cuerpo);

    if (r.statusCode == 401 &&
        !reintentando &&
        _refreshToken != null &&
        !_sinRenovar(ruta)) {
      if (await _refrescar()) {
        return _enviar(metodo, ruta,
            query: query, cuerpo: cuerpo, reintentando: true);
      }
      await alExpirar?.call();
    }

    return _desenvolver(r);
  }

  Future<http.Response> _crudo(
    String metodo,
    String ruta, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? cuerpo,
    String? token,
  }) async {
    final uri = _uri(ruta, query);
    final cabeceras = _cabeceras(conCuerpo: cuerpo != null, token: token);
    final payload = cuerpo == null ? null : jsonEncode(cuerpo);

    switch (metodo) {
      case 'GET':
        return _http.get(uri, headers: cabeceras);
      case 'POST':
        return _http.post(uri, headers: cabeceras, body: payload);
      case 'PUT':
        return _http.put(uri, headers: cabeceras, body: payload);
      case 'DELETE':
        return _http.delete(uri, headers: cabeceras, body: payload);
      default:
        throw ArgumentError('Unsupported HTTP method: $metodo');
    }
  }

  dynamic _desenvolver(http.Response r) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(r.body) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException(r.statusCode, 'Unreadable response from the server');
    }

    if (r.statusCode >= 400 || json['success'] != true) {
      throw ApiException(
        r.statusCode,
        (json['error'] as String?) ?? 'Error ${r.statusCode}',
        json['details'] as Map<String, dynamic>?,
      );
    }

    return json['data'];
  }

  // -------------------------------------------------------------------------
  // Renovación del token
  // -------------------------------------------------------------------------

  /// Un solo refresco en vuelo a la vez.
  ///
  /// Al abrir la app se disparan varias peticiones juntas —Explore, el estado de
  /// acceso, el perfil— y si el token ha caducado, TODAS reciben 401 a la vez.
  /// Sin esto, cada una pediría su propio token: el servidor emitiría varios y
  /// el último en llegar sobrescribiría a los demás, dejando peticiones en vuelo
  /// firmadas con un token que ya nadie tiene guardado. Con el Future compartido
  /// se refresca una vez y las demás esperan ese mismo resultado.
  /// Rutas cuyo 401 NO significa "el token caducó".
  ///
  ///   /users/login y /users/register  no llevan token: su 401 es "contraseña
  ///       incorrecta". Renovar y repetir sería gastar un refresco para volver a
  ///       recibir el mismo 401, y peor: si el refresco fallara, un intento de
  ///       entrar con la contraseña mal borraría la sesión que ya había.
  ///
  ///   /users/refresh  es el propio refresco. Sin esta salida, su 401 llamaría
  ///       al refresco otra vez.
  static const _rutasSinRenovar = [
    '/api/users/login',
    '/api/users/register',
    '/api/users/refresh',
  ];

  bool _sinRenovar(String ruta) =>
      _rutasSinRenovar.any((r) => ruta.startsWith(r));

  Future<bool>? _refrescoEnVuelo;

  Future<bool> _refrescar() {
    return _refrescoEnVuelo ??= _hacerRefresco().whenComplete(() {
      _refrescoEnVuelo = null;
    });
  }

  Future<bool> _hacerRefresco() async {
    final refresh = _refreshToken;
    if (refresh == null) return false;

    try {
      // OJO: este endpoint se autentica con el token de REFRESCO, no con el de
      // acceso. Mandar el de acceso da 401 aunque sea válido.
      final r = await _crudo('POST', '/api/users/refresh', token: refresh);
      if (r.statusCode != 200) return false;

      final data = (jsonDecode(r.body) as Map<String, dynamic>)['data'];
      final nuevo = (data as Map<String, dynamic>?)?['accessToken'] as String?;
      if (nuevo == null) return false;

      // El servidor devuelve SOLO un access token nuevo: el de refresco sigue
      // siendo el mismo y no hay que tocarlo.
      _accessToken = nuevo;
      await alRenovar?.call(nuevo);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _obj(String metodo, String ruta,
      {Map<String, dynamic>? query, Map<String, dynamic>? cuerpo}) async {
    final data = await _enviar(metodo, ruta, query: query, cuerpo: cuerpo);
    return (data as Map<String, dynamic>?) ?? const {};
  }

  // -------------------------------------------------------------------------
  // sitios
  // -------------------------------------------------------------------------

  /// Pestaña Explore. `curation` filtra por Must See / Quick Stops.
  Future<List<Place>> listarSitios({String? curation, int limit = 50}) async {
    final data = await _obj('GET', '/api/places/',
        query: {'curation': curation, 'limit': limit});
    return _sitios(data['places']);
  }

  /// Pestaña Near. La distancia llega calculada en `location.distanceKm`.
  Future<List<Place>> sitiosCercanos({
    required double lat,
    required double lon,
    double radioKm = 5,
    String? curation,
  }) async {
    final data = await _obj('GET', '/api/places/nearby', query: {
      'latitude': lat,
      'longitude': lon,
      'radius': radioKm,
      'curation': curation,
    });
    return _sitios(data['places']);
  }

  Future<Place> sitio(String id) async =>
      Place.fromJson(await _obj('GET', '/api/places/$id'));

  /// Pestaña Saved. Requiere sesión.
  Future<List<Place>> sitiosGuardados() async {
    final data = await _obj('GET', '/api/places/saved');
    return _sitios(data['places']);
  }

  /// Idempotente en el servidor: guardarlo dos veces no duplica nada.
  Future<void> guardarSitio(String id) =>
      _enviar('POST', '/api/places/$id/save');

  Future<void> quitarSitio(String id) =>
      _enviar('DELETE', '/api/places/$id/save');

  List<Place> _sitios(dynamic lista) => ((lista as List<dynamic>?) ?? const [])
      .map((p) => Place.fromJson(p as Map<String, dynamic>))
      .toList();

  // -------------------------------------------------------------------------
  // guía histórica
  // -------------------------------------------------------------------------

  /// La cronología llega ya ordenada por el backend. No la reordenes.
  Future<List<HistoricalArticle>> cronologia() async {
    final data = await _obj('GET', '/api/historical/chronology');
    return ((data['content'] as List<dynamic>?) ?? const [])
        .map((a) => HistoricalArticle.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<List<Topic>> temas() async {
    final data = await _obj('GET', '/api/historical/topics');
    return ((data['topics'] as List<dynamic>?) ?? const [])
        .map((t) => Topic.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  Future<HistoricalArticle> articulo(String id) async =>
      HistoricalArticle.fromJson(
          await _obj('GET', '/api/historical/content/$id'));

  Future<void> marcarLeido(String id) =>
      _enviar('POST', '/api/historical/content/$id/read');

  Future<void> desmarcarLeido(String id) =>
      _enviar('DELETE', '/api/historical/content/$id/read');

  /// Overlay del mapa. Con `year` del presente la colección llega vacía a
  /// propósito: ahí el diseño enseña el mapa actual sin capa encima.
  Future<LakeOverlay> overlayDelLago({int? year, String? bbox}) async =>
      LakeOverlay.fromJson(await _obj('GET', '/api/historical/lake-view',
          query: {'year': year, 'bbox': bbox}));

  // -------------------------------------------------------------------------
  // cuenta y desbloqueo
  // -------------------------------------------------------------------------

  Future<AuthTokens> registrar(String email, String password) async {
    final tokens = AuthTokens.fromJson(await _obj('POST', '/api/users/register',
        cuerpo: {'email': email, 'password': password}));
    usarTokens(tokens);
    return tokens;
  }

  Future<AuthTokens> entrar(String email, String password) async {
    final tokens = AuthTokens.fromJson(await _obj('POST', '/api/users/login',
        cuerpo: {'email': email, 'password': password}));
    usarTokens(tokens);
    return tokens;
  }

  /// Cierra la sesión revocando LOS DOS tokens.
  ///
  /// `/users/logout` revoca el token con el que se le llama, uno por llamada.
  /// Llamarlo solo con el de acceso dejaba el de refresco vivo 90 días, y con él
  /// se piden tokens de acceso nuevos sin contraseña: el "cerrar sesión" no
  /// cerraba nada, solo lo escondía de esta app.
  ///
  /// Las dos revocaciones van por separado y ninguna puede impedir la otra: si
  /// la primera falla, la segunda tiene que intentarse igual.
  Future<void> salir() async {
    final access = _accessToken;
    final refresh = _refreshToken;

    for (final token in [access, refresh]) {
      if (token == null) continue;
      try {
        await _crudo('POST', '/api/users/logout', token: token);
      } catch (_) {
        // Sin red no hay revocación posible. La sesión local se borra de todas
        // formas: quien pulsa "salir" se queda fuera.
      }
    }

    olvidarSesion();
  }

  Future<User> perfil() async =>
      User.fromJson(await _obj('GET', '/api/users/profile'));

  Future<AccessState> estadoDeAcceso() async =>
      AccessState.fromJson(await _obj('GET', '/api/payments/access'));

  void dispose() => _http.close();
}
