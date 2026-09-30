import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/models.dart';

/// La sesión de la app: quién está dentro y cómo se le sigue reconociendo
/// después de cerrar y volver a abrir.
///
/// Por qué `flutter_secure_storage` y no `shared_preferences`
/// ---------------------------------------------------------
/// El token de refresco vive 90 días y con él se piden tokens de acceso nuevos
/// sin contraseña: es, a efectos prácticos, la contraseña. `shared_preferences`
/// lo guardaría en un fichero en claro dentro del sandbox de la app, legible en
/// cualquier dispositivo con root o con jailbreak y en cualquier copia de
/// seguridad sin cifrar. `flutter_secure_storage` lo mete en el Keychain de iOS
/// y en el Keystore de Android, que es donde va algo así.
///
/// Es un `ChangeNotifier` porque media app depende de si hay sesión o no: la
/// pestaña Saved, el candado del contenido, el botón de comprar. Con esto, esas
/// pantallas escuchan un solo sitio en vez de preguntar cada una por su cuenta.
class Session extends ChangeNotifier {
  Session({required this.api, FlutterSecureStorage? almacen})
      : _almacen = almacen ??
            const FlutterSecureStorage(
              // `first_unlock` y no el defecto: sin esto, si el sistema abre la
              // app en segundo plano con el móvil todavía bloqueado —una
              // notificación, un refresco— el Keychain no suelta el valor y la
              // sesión parece haberse perdido.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final ApiClient api;
  final FlutterSecureStorage _almacen;

  static const _kAccess = 'aztec.accessToken';
  static const _kRefresh = 'aztec.refreshToken';
  static const _kUsuario = 'aztec.user';

  User? _usuario;
  bool _cargando = true;

  /// Quién está dentro. `null` es "nadie", y es un estado válido: la app se
  /// puede recorrer entera sin cuenta, solo sin guardar ni desbloquear nada.
  User? get usuario => _usuario;

  bool get haySesion => _usuario != null;

  /// Mientras es true todavía no se sabe si había sesión guardada. La pantalla
  /// de arranque espera esto; sin ello se vería un parpadeo de "entra" a quien
  /// ya estaba dentro.
  bool get cargando => _cargando;

  bool get tieneAccesoCompleto => _usuario?.hasFullAccess ?? false;

  // ---------------------------------------------------------------------------
  // Arranque
  // ---------------------------------------------------------------------------

  /// Recupera la sesión guardada, si la hay.
  ///
  /// El usuario se guarda en local para poder pintar la primera pantalla sin
  /// esperar a la red, pero después se refresca contra `/users/profile`: lo
  /// guardado puede estar viejo —el acceso completo pudo comprarse en otro
  /// dispositivo, o haberse reembolsado— y quien manda es el servidor.
  Future<void> restaurar() async {
    try {
      final access = await _almacen.read(key: _kAccess);
      final refresh = await _almacen.read(key: _kRefresh);
      final usuarioGuardado = await _almacen.read(key: _kUsuario);

      if (access == null || refresh == null || usuarioGuardado == null) {
        _cargando = false;
        notifyListeners();
        return;
      }

      api.usarTokens(AuthTokens(
        accessToken: access,
        refreshToken: refresh,
        user: User.fromJson(
            jsonDecode(usuarioGuardado) as Map<String, dynamic>),
      ));
      _usuario =
          User.fromJson(jsonDecode(usuarioGuardado) as Map<String, dynamic>);
      _cargando = false;
      notifyListeners();

      // Y ahora la verdad, sin bloquear el arranque.
      await refrescarUsuario();
    } catch (e) {
      // Un almacén que no se puede leer no debe dejar la app en la pantalla de
      // carga para siempre: se entra como invitado y ya.
      debugPrint('No se pudo restaurar la sesión: $e');
      await _borrar();
      _cargando = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Entrar y salir
  // ---------------------------------------------------------------------------

  Future<void> entrar(String email, String password) async {
    await _guardar(await api.entrar(email, password));
  }

  Future<void> registrar(String email, String password) async {
    await _guardar(await api.registrar(email, password));
  }

  /// Cierra la sesión y revoca los tokens en el servidor.
  ///
  /// Se limpia el estado local SIEMPRE, incluso si la revocación falla: alguien
  /// que pulsa "salir" sin cobertura tiene que quedarse fuera de todas formas.
  Future<void> salir() async {
    try {
      await api.salir();
    } catch (e) {
      debugPrint('No se pudieron revocar los tokens: $e');
    }
    await _borrar();
    _usuario = null;
    notifyListeners();
  }

  /// Lo que hace el cliente cuando el refresco falla: la sesión ya no vale.
  Future<void> expirar() async {
    await _borrar();
    api.olvidarSesion();
    _usuario = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Puesta al día
  // ---------------------------------------------------------------------------

  /// Vuelve a preguntar por el perfil. Es lo que hay que llamar después de una
  /// compra, y al volver del segundo plano.
  Future<void> refrescarUsuario() async {
    if (!api.haySesion) return;
    try {
      _usuario = await api.perfil();
      await _almacen.write(
          key: _kUsuario, value: jsonEncode(_aJson(_usuario!)));
      notifyListeners();
    } on ApiException catch (e) {
      // El cliente ya intentó refrescar el token antes de llegar aquí, así que
      // un 401 a estas alturas significa que la sesión está muerta de verdad.
      if (e.noAutenticado) await expirar();
    } catch (e) {
      // Sin red: se queda lo que había guardado. No es motivo para echar a
      // nadie.
      debugPrint('No se pudo refrescar el perfil: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Interno
  // ---------------------------------------------------------------------------

  Future<void> _guardar(AuthTokens tokens) async {
    await _almacen.write(key: _kAccess, value: tokens.accessToken);
    await _almacen.write(key: _kRefresh, value: tokens.refreshToken);
    await _almacen.write(
        key: _kUsuario, value: jsonEncode(_aJson(tokens.user)));
    _usuario = tokens.user;
    _cargando = false;
    notifyListeners();
  }

  /// El token de acceso cambia solo cuando se refresca. Lo llama el cliente.
  Future<void> guardarAccessToken(String access) =>
      _almacen.write(key: _kAccess, value: access);

  Future<void> _borrar() async {
    await _almacen.delete(key: _kAccess);
    await _almacen.delete(key: _kRefresh);
    await _almacen.delete(key: _kUsuario);
  }

  /// `User` no trae `toJson` porque el contrato solo lo manda en una dirección.
  /// Esto reconstruye la forma que espera `User.fromJson`, para poder guardarlo.
  Map<String, dynamic> _aJson(User u) => {
        'id': u.id,
        'email': u.email,
        'firstName': u.firstName,
        'lastName': u.lastName,
        'preferredLocale': u.preferredLocale,
        'hasFullAccess': u.hasFullAccess,
        'stats': {
          'toursCompleted': u.stats.toursCompleted,
          'placesVisited': u.stats.placesVisited,
        },
      };
}
