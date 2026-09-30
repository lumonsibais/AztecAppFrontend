import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../services/session_scope.dart';
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map'),
          NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Explore'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'History'),
          NavigationDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite),
              label: 'Saved'),
        ],
      ),
    );
  }
}
