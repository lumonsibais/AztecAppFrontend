import 'package:flutter/material.dart';

import '../screens/profile/account_screen.dart';
import '../services/session_scope.dart';

/// Acceso a la cuenta, para el `actions` de una AppBar.
///
/// Va en la barra de Explore, History y Saved, y NO en la de Map: ahí ya está el
/// conmutador 1500/2026 y meter otro icono al lado deja la barra apretada. Se
/// llega a la cuenta desde cualquiera de las otras tres pestañas, que es
/// suficiente.
///
/// El icono cambia según haya sesión o no —silueta rellena cuando sí—, que es la
/// única pista que necesita alguien para saber si está dentro sin tener que
/// entrar a comprobarlo.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dentro = SessionScope.of(context).haySesion;

    return IconButton(
      icon: Icon(dentro ? Icons.person : Icons.person_outline),
      tooltip: dentro ? 'Account' : 'Sign in',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AccountScreen()),
      ),
    );
  }
}
