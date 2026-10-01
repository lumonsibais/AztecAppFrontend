import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../services/session_scope.dart';
import '../theme.dart';
import 'auth/auth_screen.dart';
import 'explore_screen.dart';
import 'history_screen.dart';
import 'map_screen.dart';
import 'saved_screen.dart';

/// Las cuatro pestañas del MVP, en el orden del diseño.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.api});

  final ApiClient api;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _indice = 1; // arranca en Explore, que es donde hay contenido

  @override
  Widget build(BuildContext context) {
    // Se escucha la sesión aquí para que entrar o salir repinte las pestañas de
    // golpe: Saved pasa de "necesitas una cuenta" a la lista, y al revés, sin
    // que cada pantalla tenga que enterarse por su cuenta.
    SessionScope.of(context);

    final pantallas = [
      MapScreen(api: widget.api),
      ExploreScreen(api: widget.api),
      HistoryScreen(api: widget.api),
      SavedScreen(
        api: widget.api,
        onPedirEntrar: () => pedirEntrar(
          context,
          motivo: 'Sign in to keep your saved places on your account.',
        ),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _indice, children: pantallas),
      bottomNavigationBar: _BarraInferior(
        indice: _indice,
        onCambio: (i) => setState(() => _indice = i),
      ),
    );
  }
}

/// La barra de las cuatro pestañas, como la dibuja el diseño.
///
/// Dos cosas que no son de Material y están así a propósito, porque salen
/// iguales en las dos pantallas del archivo que hemos leído:
///
///   - **los iconos son emojis**, no iconos de Material;
///   - **el elemento activo va en azul** `#0066FF`, no en el coral de la marca.
///
/// Lo segundo chirría con el resto de la paleta y está pendiente de confirmar
/// con quien diseñó. Mientras tanto se respeta el archivo: si es un descuido, se
/// cambia una constante en `theme.dart` y queda; si es intencional, ya está.
///
/// `NavigationBar` de Material no sirve aquí: impone su propia altura, su
/// píldora de selección y el tamaño de sus iconos.
class _BarraInferior extends StatelessWidget {
  const _BarraInferior({required this.indice, required this.onCambio});

  final int indice;
  final ValueChanged<int> onCambio;

  static const _pestanas = [
    ('🗺️', 'Map'),
    ('🏛️', 'Explore'),
    ('📖', 'History'),
    ('❤️', 'Saved'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AztecTheme.hueso,
      padding: const EdgeInsets.only(top: 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _pestanas.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onCambio(i),
                child: SizedBox(
                  width: 78,
                  height: 54,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_pestanas[i].$1,
                          style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text(
                        _pestanas[i].$2,
                        style: TextStyle(
                          fontFamily: AztecTheme.grotesca,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: i == indice
                              ? AztecTheme.navActivo
                              : AztecTheme.tintaSuave,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
