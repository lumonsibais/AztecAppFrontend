import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services/session_scope.dart';
import '../../theme.dart';
import '../auth/auth_screen.dart';

/// La cuenta: quién está dentro, si tiene el contenido desbloqueado, y salir.
///
/// El estado de acceso se pide a `/payments/access` y no se saca del usuario
/// guardado, aunque el perfil también lo traiga: es el endpoint que la app
/// consultará después de comprar, así que es el que tiene que estar bien
/// enchufado desde ya.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Future<AccessState>? _acceso;
  bool _saliendo = false;

  @override
  void initState() {
    super.initState();
    _cargarAcceso();
  }

  void _cargarAcceso() {
    final sesion = SessionScope.sin(context);
    if (sesion.haySesion) {
      _acceso = sesion.api.estadoDeAcceso();
    }
  }

  Future<void> _salir() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your saved places stay on your account. You can sign back in any '
          'time.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AztecTheme.coral),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    setState(() => _saliendo = true);
    await SessionScope.sin(context).salir();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final sesion = SessionScope.of(context);
    final usuario = sesion.usuario;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: usuario == null
          ? _SinCuenta(onEntrar: () async {
              final entro = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
              );
              if (entro == true && mounted) setState(_cargarAcceso);
            })
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _Ficha(
                  titulo: 'Signed in as',
                  valor: usuario.email,
                  icono: Icons.person_outline,
                ),
                const SizedBox(height: 14),
                _TarjetaAcceso(
                  futuro: _acceso,
                  onReintentar: () => setState(_cargarAcceso),
                ),
                const SizedBox(height: 14),
                _Ficha(
                  titulo: 'Places visited',
                  valor: '${usuario.stats.placesVisited}',
                  icono: Icons.place_outlined,
                ),
                const SizedBox(height: 14),
                _Ficha(
                  titulo: 'Tours completed',
                  valor: '${usuario.stats.toursCompleted}',
                  icono: Icons.route_outlined,
                ),
                const SizedBox(height: 30),
                OutlinedButton.icon(
                  onPressed: _saliendo ? null : _salir,
                  icon: const Icon(Icons.logout, size: 19),
                  label: Text(_saliendo ? 'Signing out…' : 'Sign out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AztecTheme.coral,
                    side: const BorderSide(color: AztecTheme.linea),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
    );
  }
}

class _TarjetaAcceso extends StatelessWidget {
  const _TarjetaAcceso({required this.futuro, required this.onReintentar});

  final Future<AccessState>? futuro;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccessState>(
      future: futuro,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Ficha(
              titulo: 'Full access', valor: '…', icono: Icons.lock_outline);
        }
        if (snap.hasError || !snap.hasData) {
          return _Ficha(
            titulo: 'Full access',
            valor: 'Could not check',
            icono: Icons.lock_outline,
            alPulsar: onReintentar,
          );
        }

        final acceso = snap.data!;
        if (acceso.hasFullAccess) {
          return const _Ficha(
            titulo: 'Full access',
            valor: 'Unlocked',
            icono: Icons.lock_open_outlined,
            resaltado: true,
          );
        }

        // Aquí NO se pinta el precio, aunque el endpoint lo traiga. El de
        // `/payments/access` es de referencia; el que ve el comprador lo fija la
        // tienda, en la moneda de su país y al escalón elegido en App Store
        // Connect y en Play Console. Enseñar "$15" y que la tienda cobre otra
        // cosa es la clase de detalle por la que Apple rechaza una entrega.
        return const _Ficha(
          titulo: 'Full access',
          valor: 'Locked',
          icono: Icons.lock_outline,
        );
      },
    );
  }
}

class _Ficha extends StatelessWidget {
  const _Ficha({
    required this.titulo,
    required this.valor,
    required this.icono,
    this.resaltado = false,
    this.alPulsar,
  });

  final String titulo;
  final String valor;
  final IconData icono;
  final bool resaltado;
  final VoidCallback? alPulsar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: alPulsar,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: resaltado ? AztecTheme.coral : AztecTheme.linea),
        ),
        child: Row(
          children: [
            Icon(icono,
                size: 22,
                color: resaltado ? AztecTheme.coral : AztecTheme.tintaSuave),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AztecTheme.tintaSuave)),
                  const SizedBox(height: 3),
                  Text(valor,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color:
                            resaltado ? AztecTheme.coral : AztecTheme.tinta,
                      )),
                ],
              ),
            ),
            if (alPulsar != null)
              const Icon(Icons.refresh,
                  size: 19, color: AztecTheme.tintaSuave),
          ],
        ),
      ),
    );
  }
}

class _SinCuenta extends StatelessWidget {
  const _SinCuenta({required this.onEntrar});

  final VoidCallback onEntrar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline,
                size: 46, color: AztecTheme.tintaSuave),
            const SizedBox(height: 16),
            const Text('You are browsing as a guest',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Everything free is already open. An account is only needed to '
              'save places and to unlock the full guides.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AztecTheme.tintaSuave, height: 1.45),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: onEntrar,
              style: FilledButton.styleFrom(backgroundColor: AztecTheme.coral),
              child: const Text('Create account or sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
