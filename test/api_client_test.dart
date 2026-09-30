// Pruebas de la lógica de sesión de ApiClient.
//
// Sustituyen al `widget_test.dart` que venía de `flutter create`: aquel probaba
// un contador que esta app nunca tuvo y referenciaba una clase `MyApp` que no
// existe, así que `flutter test` llevaba roto desde el primer día sin que nadie
// lo notara.
//
// Lo que se prueba aquí es lo más enredado del cliente y lo que más caro sale si
// falla en un móvil: la renovación del token. Todo con `MockClient`, que ya
// viene en el paquete `http`, así que no hace falta ni backend ni plugins ni
// añadir una dependencia de pruebas.
//
// `tools/check_sesion_viva.py` cubre lo mismo contra el servidor de verdad. Los
// dos hacen falta y no se solapan: aquel comprueba que el SERVIDOR se comporta
// como este cliente supone; este comprueba que el CLIENTE hace lo que dice,
// incluidos los casos que son incómodos de provocar contra un servidor real.
import 'dart:convert';

import 'package:aztec_app/api/api_client.dart';
import 'package:aztec_app/api/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _base = 'http://servidor-de-prueba';

AuthTokens _tokens() => AuthTokens.fromJson({
      'accessToken': 'access-1',
      'refreshToken': 'refresh-1',
      'user': _usuario,
    });

const _usuario = {
  'id': 'u1',
  'email': 'yo@example.com',
  'hasFullAccess': false,
  'stats': {'toursCompleted': 0, 'placesVisited': 0},
};

/// El backend envuelve todo en {success, data}. Aquí se replica.
String _sobre(Object? data) => jsonEncode({'success': true, 'data': data});

String _fallo(String mensaje) =>
    jsonEncode({'success': false, 'error': mensaje});

http.Response _ok(Object? data) => http.Response(_sobre(data), 200);

http.Response _noAutorizado() =>
    http.Response(_fallo('Unauthorized'), 401);

void main() {
  test('un 401 renueva el token, repite la petición y avisa del token nuevo',
      () async {
    final llamadas = <String>[];
    String? renovado;

    final api = ApiClient(
      baseUrl: _base,
      cliente: MockClient((peticion) async {
        final auth = peticion.headers['Authorization'];
        llamadas.add('${peticion.url.path} $auth');

        if (peticion.url.path == '/api/users/refresh') {
          return _ok({'accessToken': 'access-2'});
        }
        // El token viejo ya no vale; el nuevo sí.
        if (auth == 'Bearer access-2') return _ok(_usuario);
        return _noAutorizado();
      }),
    );
    api.alRenovar = (token) async => renovado = token;
    api.usarTokens(_tokens());

    final usuario = await api.perfil();

    expect(usuario.email, 'yo@example.com');
    expect(llamadas, hasLength(3),
        reason: 'la que falló, el refresco y el reintento');
    expect(llamadas[0], '/api/users/profile Bearer access-1');
    // El refresco se firma con el token de REFRESCO. Con el de acceso, el
    // servidor devuelve 401 aunque sea válido.
    expect(llamadas[1], '/api/users/refresh Bearer refresh-1');
    expect(llamadas[2], '/api/users/profile Bearer access-2');
    expect(renovado, 'access-2',
        reason: 'sin esto el token nuevo no llega al almacén');
  });

  test('si el refresco también falla, se rinde en vez de dar vueltas', () async {
    var peticiones = 0;
    var expirada = false;

    final api = ApiClient(
      baseUrl: _base,
      cliente: MockClient((_) async {
        peticiones++;
        return _noAutorizado();
      }),
    );
    api.alExpirar = () async => expirada = true;
    api.usarTokens(_tokens());

    await expectLater(api.perfil(), throwsA(isA<ApiException>()));

    expect(peticiones, 2, reason: 'la que falló y el refresco. Sin bucle');
    expect(expirada, isTrue,
        reason: 'la app tiene que volver a pedir la entrada');
  });

  test('varias peticiones con el token caducado piden UN solo token nuevo',
      () async {
    var refrescos = 0;

    final api = ApiClient(
      baseUrl: _base,
      cliente: MockClient((peticion) async {
        final auth = peticion.headers['Authorization'];

        if (peticion.url.path == '/api/users/refresh') {
          refrescos++;
          // El retraso no es decorativo: sin él, el refresco podría terminar
          // antes de que las otras dos peticiones reciban su 401, y entonces
          // cada una pediría el suyo. La prueba dependería del orden de los
          // microtasks en vez de comprobar lo que dice comprobar.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _ok({'accessToken': 'access-2'});
        }
        if (auth != 'Bearer access-2') return _noAutorizado();

        switch (peticion.url.path) {
          case '/api/users/profile':
            return _ok(_usuario);
          case '/api/payments/access':
            return _ok({
              'hasFullAccess': false,
              'since': null,
              'product': 'full_access',
              'price': 15.0,
              'currency': 'USD',
            });
          default:
            return _ok({'places': <dynamic>[]});
        }
      }),
    );
    api.usarTokens(_tokens());

    // Es lo que pasa al abrir la app: tres peticiones a la vez y el token
    // caducado. Sin un refresco compartido, cada una pediría el suyo y el
    // último sobrescribiría a los demás.
    await Future.wait([
      api.perfil(),
      api.estadoDeAcceso(),
      api.sitiosGuardados(),
    ]);

    expect(refrescos, 1);
  });

  test('un 401 de entrada NO gasta un refresco', () async {
    final rutas = <String>[];

    final api = ApiClient(
      baseUrl: _base,
      cliente: MockClient((peticion) async {
        rutas.add(peticion.url.path);
        return _noAutorizado();
      }),
    );
    // Hay sesión guardada y aun así se intenta entrar con otra contraseña.
    api.usarTokens(_tokens());

    await expectLater(
      api.entrar('yo@example.com', 'contrasena-mala'),
      throwsA(isA<ApiException>()),
    );

    // El 401 de /login significa "contraseña incorrecta", no "token caducado".
    // Sin esta excepción se gastaría un refresco y, si fallara, se borraría la
    // sesión que ya había por escribir mal la contraseña.
    expect(rutas, ['/api/users/login']);
  });

  test('salir revoca los DOS tokens', () async {
    final revocados = <String>[];

    final api = ApiClient(
      baseUrl: _base,
      cliente: MockClient((peticion) async {
        if (peticion.url.path == '/api/users/logout') {
          revocados.add(peticion.headers['Authorization'] ?? '');
          return _ok(null);
        }
        return _noAutorizado();
      }),
    );
    api.usarTokens(_tokens());

    await api.salir();

    // /users/logout revoca UN token por llamada. Llamarlo solo con el de acceso
    // dejaba el de refresco vivo 90 días: con él se piden tokens de acceso
    // nuevos sin contraseña, así que "cerrar sesión" no cerraba nada.
    expect(revocados, ['Bearer access-1', 'Bearer refresh-1']);
    expect(api.haySesion, isFalse);
  });

  test('salir limpia la sesión aunque no haya red', () async {
    final api = ApiClient(
      baseUrl: _base,
      cliente: MockClient(
          (_) async => throw http.ClientException('Connection failed')),
    );
    api.usarTokens(_tokens());

    await api.salir();

    // Quien pulsa "salir" se queda fuera, haya cobertura o no.
    expect(api.haySesion, isFalse);
  });

  test('un error del servidor llega con su mensaje, no con uno genérico',
      () async {
    final api = ApiClient(
      baseUrl: _base,
      cliente: MockClient((_) async =>
          http.Response(_fallo('This account already has full access'), 409)),
    );

    try {
      await api.entrar('yo@example.com', 'x');
      fail('tenía que lanzar');
    } on ApiException catch (e) {
      expect(e.statusCode, 409);
      expect(e.message, 'This account already has full access');
    }
  });
}
