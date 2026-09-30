import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/session_scope.dart';
import '../../theme.dart';
import '../../widgets/account_button.dart';
import 'tour_detail_screen.dart';

/// El catálogo de tours autoguiados.
///
/// Esta parte del producto no existía en el front: el backend lleva siete
/// operaciones de tours —listado, ficha con paradas, empezar, guardar avance,
/// completar— desde el primer sprint, y la app no llamaba a ninguna. Es la
/// tercera historia de usuario del MVP.
///
/// Dos listas en una: los que la cuenta ya empezó arriba, el resto debajo. Al
/// abrir la app, retomar lo que dejaste a medias importa más que descubrir algo
/// nuevo, y quien no ha empezado ninguno no ve la primera sección.
class ToursScreen extends StatefulWidget {
  const ToursScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ToursScreen> createState() => _ToursScreenState();
}

class _ToursScreenState extends State<ToursScreen> {
  late Future<List<Tour>> _todos = widget.api.listarTours();
  Future<List<Tour>>? _empezados;
  bool _habiaSesion = false;

  Future<void> _recargar() async {
    final sesion = SessionScope.sin(context);
    setState(() {
      _todos = widget.api.listarTours();
      _empezados = sesion.haySesion ? widget.api.misTours() : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sesion = SessionScope.of(context);

    // Igual que en Saved: entrar o salir cambia lo que hay que pedir.
    if (sesion.haySesion != _habiaSesion) {
      _habiaSesion = sesion.haySesion;
      _empezados = sesion.haySesion ? widget.api.misTours() : null;
      _todos = widget.api.listarTours();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tours'),
        actions: const [AccountButton()],
      ),
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: FutureBuilder<List<Tour>>(
          future: _todos,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _mensaje('${snap.error}');
            }

            final tours = snap.data ?? const <Tour>[];
            if (tours.isEmpty) {
              return _mensaje('No tours yet.');
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_empezados != null) _Continuar(
                  futuro: _empezados!,
                  onAbrir: _abrir,
                ),
                for (final t in tours) ...[
                  _TarjetaTour(tour: t, onTap: () => _abrir(t.id)),
                  const SizedBox(height: 14),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _abrir(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TourDetailScreen(api: widget.api, tourId: id),
    ));
    // Al volver puede haber cambiado el avance, así que se vuelve a pedir.
    if (mounted) await _recargar();
  }

  Widget _mensaje(String texto) => ListView(
        padding: const EdgeInsets.all(36),
        children: [
          const SizedBox(height: 70),
          Text(texto,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AztecTheme.tintaSuave, height: 1.5, fontSize: 15)),
        ],
      );
}

/// "Continuar" — los tours empezados y sin terminar.
class _Continuar extends StatelessWidget {
  const _Continuar({required this.futuro, required this.onAbrir});

  final Future<List<Tour>> futuro;
  final ValueChanged<String> onAbrir;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Tour>>(
      future: futuro,
      builder: (context, snap) {
        final empezados = (snap.data ?? const <Tour>[])
            .where((t) => t.progress != null && !t.progress!.isCompleted)
            .toList();
        if (empezados.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Continue',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AztecTheme.tintaSuave)),
            const SizedBox(height: 10),
            for (final t in empezados) ...[
              _TarjetaTour(
                tour: t,
                onTap: () => onAbrir(t.id),
                avance: t.progress,
              ),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 10),
            const Text('All tours',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AztecTheme.tintaSuave)),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }
}

class _TarjetaTour extends StatelessWidget {
  const _TarjetaTour({required this.tour, required this.onTap, this.avance});

  final Tour tour;
  final VoidCallback onTap;
  final UserTourProgress? avance;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(tour.title, style: AztecTheme.tituloTarjeta),
                  ),
                  if (tour.bajoCandado)
                    const Padding(
                      padding: EdgeInsets.only(left: 8, top: 2),
                      child: Icon(Icons.lock,
                          size: 16, color: AztecTheme.tintaSuave),
                    )
                  else if (tour.isFree)
                    const _Etiqueta(texto: 'FREE'),
                ],
              ),
              if (tour.description != null) ...[
                const SizedBox(height: 6),
                Text(tour.description!,
                    style: AztecTheme.tagline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 14, runSpacing: 6, children: [
                if (tour.durationText != null)
                  _Dato(icono: Icons.schedule, texto: tour.durationText!),
                _Dato(
                    icono: Icons.place_outlined,
                    texto: '${tour.stopsCount} stops'),
                if (tour.totalDistance != null)
                  _Dato(
                      icono: Icons.straighten,
                      texto: '${tour.totalDistance!.toStringAsFixed(1)} km'),
                if (tour.includesAudio)
                  const _Dato(icono: Icons.headphones, texto: 'Audio'),
                if (tour.hasEntryFees)
                  const _Dato(
                      icono: Icons.confirmation_number_outlined,
                      texto: 'Entry fees'),
              ]),
              if (avance != null) ...[
                const SizedBox(height: 12),
                _Barra(
                  hechas: (avance!.currentStopIndex ?? 0),
                  total: tour.stopsCount,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.hechas, required this.total});

  final int hechas;
  final int total;

  @override
  Widget build(BuildContext context) {
    // `total` puede llegar a 0 si el tour está bloqueado y no viajan paradas.
    // Dividir por cero en Dart da NaN y LinearProgressIndicator revienta.
    final fraccion = total <= 0 ? 0.0 : (hechas / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraccion,
            minHeight: 5,
            backgroundColor: AztecTheme.linea,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AztecTheme.coral),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          total <= 0 ? 'In progress' : 'Stop $hechas of $total',
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: AztecTheme.tintaSuave),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 15, color: AztecTheme.tintaSuave),
          const SizedBox(width: 5),
          Text(texto,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AztecTheme.tintaSuave)),
        ],
      );
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AztecTheme.arena.withOpacity(0.45),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(texto,
            style: AztecTheme.etiqueta.copyWith(color: AztecTheme.tinta)),
      );
}
