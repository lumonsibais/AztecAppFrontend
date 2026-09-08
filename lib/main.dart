import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

void main() => runApp(const AztecApp());

class AztecApp extends StatefulWidget {
  const AztecApp({super.key});

  @override
  State<AztecApp> createState() => _AztecAppState();
}

class _AztecAppState extends State<AztecApp> {
  // Un solo cliente para toda la app: guarda los tokens en memoria y así una
  // sesión iniciada en Saved vale también para el corazón de Explore.
  //
  // Persistirlos entre arranques es del próximo sprint, y va con secure
  // storage: un JWT en SharedPreferences es texto plano en el disco.
  final _api = ApiClient();

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AztecApp Explorer',
      debugShowCheckedModeBanner: false,
      theme: AztecTheme.claro,
      home: HomeShell(api: _api),
    );
  }
}
