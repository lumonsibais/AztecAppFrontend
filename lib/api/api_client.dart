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

  bool get haySesion => _accessToken != null;

  void usarTokens(AuthTokens tokens) {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
  }

  void olvidarSesion() {
    _accessToken = null;
    _refreshToken = null;
  }

  Map<String, String> _cabeceras({bool conCuerpo = false}) {
    final h = <String, String>{
      'Accept': 'application/json',
      // El backend compara por prefijo de dos letras: es-MX resuelve a es.
      'Accept-Language': Config.locale,
    };
    if (conCuerpo) h['Content-Type'] = 'application/json';
    if (_accessToken != null) h['Authorization'] = 'Bearer $_accessToken';
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
  Future<dynamic> _enviar(
    String metodo,
    String ruta, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? cuerpo,
  }) async {
    final uri = _uri(ruta, query);
    final cabeceras = _cabeceras(conCuerpo: cuerpo != null);
    final payload = cuerpo == null ? null : jsonEncode(cuerpo);

    late http.Response r;
    switch (metodo) {
      case 'GET':
        r = await _http.get(uri, headers: cabeceras);
      case 'POST':
        r = await _http.post(uri, headers: cabeceras, body: payload);
      case 'PUT':
        r = await _http.put(uri, headers: cabeceras, body: payload);
      case 'DELETE':
        r = await _http.delete(uri, headers: cabeceras, body: payload);
      default:
        throw ArgumentError('Unsupported HTTP method: $metodo');
    }

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

  Future<void> salir() async {
    try {
      await _enviar('POST', '/api/users/logout');
    } finally {
      olvidarSesion();
    }
  }

  Future<User> perfil() async =>
      User.fromJson(await _obj('GET', '/api/users/profile'));

  Future<AccessState> estadoDeAcceso() async =>
      AccessState.fromJson(await _obj('GET', '/api/payments/access'));

  void dispose() => _http.close();
}
