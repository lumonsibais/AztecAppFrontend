import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
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
    final pantallas = [
      MapScreen(api: widget.api),
      ExploreScreen(api: widget.api),
      HistoryScreen(api: widget.api),
      SavedScreen(api: widget.api, onPedirEntrar: _pedirEntrar),
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

  /// Alta rápida, solo para poder probar Saved contra el backend real.
  ///
  /// La pantalla de autenticación de verdad —con Google y Apple, y guardando
  /// los tokens en secure storage— es tarea del siguiente sprint. Esto es un
  /// atajo de desarrollo y lo dice en voz alta.
  Future<void> _pedirEntrar() async {
    final email = TextEditingController();
    final password = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Development shortcut: creates an account against the local '
              'backend. The real sign-in screen lands next sprint.',
              style: TextStyle(fontSize: 13, color: AztecTheme.tintaSuave),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
            ),
            TextField(
              controller: password,
              decoration: const InputDecoration(
                  labelText: 'Password (8 characters minimum)'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign in')),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      // Si el email ya existe el registro da 409; entonces se prueba a entrar.
      try {
        await widget.api.registrar(email.text.trim(), password.text);
      } on ApiException catch (e) {
        if (e.statusCode == 409) {
          await widget.api.entrar(email.text.trim(), password.text);
        } else {
          rethrow;
        }
      }
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}
