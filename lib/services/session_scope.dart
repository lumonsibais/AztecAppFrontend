import 'package:flutter/material.dart';

import 'session.dart';

/// Pone la sesión al alcance de cualquier pantalla, sin paquete de estado.
///
/// `InheritedNotifier` hace las dos cosas que se necesitan: reparte el objeto
/// hacia abajo y reconstruye a quien lo lea cuando la sesión cambia. Es parte de
/// Flutter, así que no añade una dependencia por algo que el framework ya trae.
///
/// Se lee de dos maneras, y la diferencia importa:
///
///   SessionScope.of(context)     se suscribe: el widget se reconstruye cuando
///                                la sesión cambia. Es lo que quiere una
///                                pantalla que pinta según haya sesión o no.
///
///   SessionScope.sin(context)    no se suscribe. Para llamar a `entrar()` o
///                                `salir()` desde un callback, donde volver a
///                                construir no hace falta y suscribirse solo
///                                provoca reconstrucciones de más.
class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({
    super.key,
    required Session session,
    required super.child,
  }) : super(notifier: session);

  static Session of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope?.notifier != null, 'No hay un SessionScope encima de esto');
    return scope!.notifier!;
  }

  static Session sin(BuildContext context) {
    final scope =
        context.getElementForInheritedWidgetOfExactType<SessionScope>()?.widget
            as SessionScope?;
    assert(scope?.notifier != null, 'No hay un SessionScope encima de esto');
    return scope!.notifier!;
  }
}
