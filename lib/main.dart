import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/home_shell.dart';
import 'services/session.dart';
import 'services/session_scope.dart';
import 'theme.dart';

void main() => runApp(const AztecApp());

class AztecApp extends StatefulWidget {
  const AztecApp({super.key});

  @override
  State<AztecApp> createState() => _AztecAppState();
}

class _AztecAppState extends State<AztecApp> with WidgetsBindingObserver {
  // Un solo cliente para toda la app, y una sola sesión encima de él.
  final _api = ApiClient();
  late final Session _sesion = Session(api: _api);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // El cliente renueva el token de acceso solo cuando el servidor contesta
    // 401. Estos dos enganches son lo que hace que esa renovación llegue al
    // almacén: sin el primero, el token nuevo viviría en memoria y al reabrir
    // la app se volvería a mandar el viejo; sin el segundo, una sesión muerta
    // se quedaría pintada como viva.
    _api.alRenovar = _sesion.guardarAccessToken;
    _api.alExpirar = _sesion.expirar;

    _sesion.restaurar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sesion.dispose();
    _api.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Al volver del segundo plano se vuelve a preguntar por el perfil. Es lo que
    // hará que el candado se abra sin reiniciar nada cuando la compra se cierre
    // en la tienda: el sistema devuelve la app al frente y aquí se pregunta.
    if (estado == AppLifecycleState.resumed) {
      _sesion.refrescarUsuario();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: _sesion,
      child: MaterialApp(
        title: 'AztecApp Explorer',
        debugShowCheckedModeBanner: false,
        theme: AztecTheme.claro,
        home: const _Arranque(),
      ),
    );
  }
}

/// Espera a saber si había sesión guardada antes de pintar la app.
///
/// Sin esto se ve un parpadeo: la app arranca sin sesión, pinta Saved con el
/// "necesitas una cuenta", y medio segundo después aparecen los sitios
/// guardados. Leer el Keychain es rápido, pero no instantáneo.
class _Arranque extends StatelessWidget {
  const _Arranque();

  @override
  Widget build(BuildContext context) {
    final sesion = SessionScope.of(context);

    if (sesion.cargando) {
      return const Scaffold(
        backgroundColor: AztecTheme.hueso,
        body: Center(
          child: SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: AztecTheme.coral),
          ),
        ),
      );
    }

    return HomeShell(api: sesion.api);
  }
}
