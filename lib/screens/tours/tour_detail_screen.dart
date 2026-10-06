import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/session_scope.dart';
import '../../theme.dart';
import '../auth/auth_screen.dart' show pedirEntrar;
import '../place_detail_screen.dart';

/// La ficha de un tour: sus paradas, y el avance dentro de él.
///
/// La línea del candado aquí es la misma que en la ficha de un sitio, y tiene
/// la misma forma: **las paradas no viajan** si el tour está bloqueado. No se
/// esconden en el cliente, no llegan. Por eso una lista vacía con
/// `stopsCount: 5` no es un error, es el teaser.
///
/// El avance lo lleva el servidor. Cada vez que se pasa de parada se manda un
/// PUT y se pinta LO QUE DEVUELVE, no lo que se acaba de mandar: con la app
/// abierta en el móvil y en la tablet, fiarse de lo enviado es divergir sin que
/// nadie se entere.
class TourDetailScreen extends StatefulWidget {
  const TourDetailScreen({super.key, required this.api, required this.tourId});

  final ApiClient api;
  final String tourId;

  @override
  State<TourDetailScreen> createState() => _TourDetailScreenState();
}

class _TourDetailScreenState extends State<TourDetailScreen> {
  late Future<Tour> _futuro = widget.api.tour(widget.tourId);

  /// El avance vivo, tal como lo devolvió el servidor en la última llamada.
  /// null mientras no se haya empezado en esta pantalla ni viniera de antes.
  TourProgress? _avance;
  bool _ocupado = false;
  bool? _accesoAnterior;

  Future<void> _empezar() async {
    final sesion = SessionScope.sin(context);

    if (!sesion.haySesion) {
      final entro = await pedirEntrar(
        context,
        motivo: 'Sign in so your progress through the tour is saved.',
        registro: true,
      );
      if (!entro || !mounted) return;
      setState(() => _futuro = widget.api.tour(widget.tourId));
      return;
    }

    await _llamar(() => widget.api.empezarTour(widget.tourId));
  }

  Future<void> _irAParada(int indice) =>
      _llamar(() => widget.api.guardarProgreso(widget.tourId,
          paradaActual: indice));

  Future<void> _completar() async {
    await _llamar(() => widget.api.completarTour(widget.tourId));
    if (mounted && _avance?.isCompleted == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tour completed. Nicely done.')),
      );
    }
  }

  /// Envoltorio común: bloquea los botones mientras viaja la petición y traduce
  /// los errores a algo legible.
  Future<void> _llamar(Future<TourProgress> Function() accion) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final avance = await accion();
      if (!mounted) return;
      setState(() {
        _avance = avance;
        _ocupado = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.statusCode == 403
            ? 'This tour is part of the full guide.'
            : e.message),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not reach the server. Check your connection.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = SessionScope.of(context);

    // Al desbloquear, las paradas pasan a viajar: hay que volver a pedir la
    // ficha, no basta con repintarla.
    if (_accesoAnterior != null &&
        _accesoAnterior != sesion.tieneAccesoCompleto) {
      _futuro = widget.api.tour(widget.tourId);
      _avance = null;
    }
    _accesoAnterior = sesion.tieneAccesoCompleto;

    return Scaffold(
      body: FutureBuilder<Tour>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AztecTheme.tintaSuave)),
              ),
            );
          }

          final t = snap.data!;
          final paradaActual = _avance?.currentStopIndex ?? 0;
          final empezado = _avance != null;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: t.imageUrl != null ? 200 : 0,
                flexibleSpace: t.imageUrl == null
                    ? null
                    : FlexibleSpaceBar(
                        background: Image.network(
                          t.imageUrl!,
                          fit: BoxFit.cover,
                          // Una imagen que no carga no puede romper la ficha.
                          errorBuilder: (_, __, ___) =>
                              Container(color: AztecTheme.arena),
                        ),
                      ),
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 16, runSpacing: 6, children: [
                          // La zona va primero: es lo que decide si el
                          // recorrido cae cerca de donde ya estás.
                          if (t.neighborhood != null)
                            _dato(Icons.location_on_outlined, t.neighborhood!),
                          if (t.durationText != null)
                            _dato(Icons.schedule, t.durationText!),
                          _dato(Icons.place_outlined, '${t.stopsCount} stops'),
                          if (t.totalDistance != null)
                            _dato(Icons.straighten,
                                '${t.totalDistance!.toStringAsFixed(1)} km'),
                          if (t.difficultyLevel != null)
                            _dato(Icons.terrain, t.difficultyLevel!),
                        ]),
                        if (t.description != null) ...[
                          const SizedBox(height: 18),
                          Text(t.description!,
                              style: const TextStyle(
                                  fontSize: 16, height: 1.55)),
                        ],
                        if (t.contentDescription != null) ...[
                          const SizedBox(height: 14),
                          Text(t.contentDescription!,
                              style: const TextStyle(
                                  fontSize: 15.5,
                                  height: 1.55,
                                  color: AztecTheme.tintaSuave)),
                        ],

                        const SizedBox(height: 24),

                        if (t.bajoCandado)
                          _CandadoTour(stopsCount: t.stopsCount)
                        else ...[
                          _Boton(
                            texto: empezado
                                ? (_avance!.isCompleted
                                    ? 'Completed'
                                    : 'In progress')
                                : 'Start this tour',
                            icono: empezado
                                ? Icons.check_circle_outline
                                : Icons.play_arrow,
                            activo: !_ocupado && !empezado,
                            onPulsar: _empezar,
                          ),
                          const SizedBox(height: 26),
                          if (t.stops.isEmpty)
                            const Text(
                              'This tour has no stops loaded yet.',
                              style: TextStyle(color: AztecTheme.tintaSuave),
                            )
                          else
                            ...[
                              const Text('STOPS',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1,
                                      color: AztecTheme.tintaSuave)),
                              const SizedBox(height: 12),
                              for (var i = 0; i < t.stops.length; i++)
                                _Parada(
                                  parada: t.stops[i],
                                  indice: i,
                                  esUltima: i == t.stops.length - 1,
                                  hecha: empezado && i < paradaActual,
                                  actual: empezado && i == paradaActual,
                                  puedeAvanzar: empezado &&
                                      !_ocupado &&
                                      !(_avance?.isCompleted ?? false),
                                  onLlegue: () => _irAParada(i + 1),
                                  onAbrirSitio: () =>
                                      _abrirSitio(t.stops[i].placeId),
                                ),
                              if (empezado &&
                                  !(_avance?.isCompleted ?? false) &&
                                  paradaActual >= t.stops.length) ...[
                                const SizedBox(height: 8),
                                _Boton(
                                  texto: 'Finish tour',
                                  icono: Icons.flag_outlined,
                                  activo: !_ocupado,
                                  onPulsar: _completar,
                                ),
                              ],
                            ],
                        ],
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  void _abrirSitio(String placeId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaceDetailScreen(api: widget.api, placeId: placeId),
    ));
  }

  Widget _dato(IconData icono, String texto) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: AztecTheme.tintaSuave),
          const SizedBox(width: 5),
          Text(texto,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AztecTheme.tintaSuave)),
        ],
      );
}

class _Parada extends StatelessWidget {
  const _Parada({
    required this.parada,
    required this.indice,
    required this.esUltima,
    required this.hecha,
    required this.actual,
    required this.puedeAvanzar,
    required this.onLlegue,
    required this.onAbrirSitio,
  });

  final TourStop parada;
  final int indice;
  final bool esUltima;
  final bool hecha;
  final bool actual;
  final bool puedeAvanzar;
  final VoidCallback onLlegue;
  final VoidCallback onAbrirSitio;

  @override
  Widget build(BuildContext context) {
    final sitio = parada.place;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // La columna del hilo: número y la línea que une las paradas.
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hecha
                      ? AztecTheme.coral
                      : actual
                          ? AztecTheme.tinta
                          : AztecTheme.arena.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: hecha
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text('${indice + 1}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: actual ? Colors.white : AztecTheme.tinta)),
              ),
              if (!esUltima)
                Expanded(
                  child: Container(width: 2, color: AztecTheme.linea),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: esUltima ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: onAbrirSitio,
                    child: Text(
                      sitio?.name ?? 'Stop ${indice + 1}',
                      style: AztecTheme.tituloTarjeta.copyWith(fontSize: 17),
                    ),
                  ),
                  if (sitio?.tagline != null) ...[
                    const SizedBox(height: 4),
                    Text(sitio!.tagline!, style: AztecTheme.tagline),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    if (parada.audio.hayAudio)
                      _AudioPendiente(audio: parada.audio),
                  ]),
                  if (parada.transitionText != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AztecTheme.arena.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('“${parada.transitionText!}”',
                          style: const TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              fontStyle: FontStyle.italic)),
                    ),
                  ],
                  if (actual && puedeAvanzar) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: onLlegue,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AztecTheme.coral,
                        side: const BorderSide(color: AztecTheme.linea),
                      ),
                      child: const Text("I'm here — next stop"),
                    ),
                  ],
                  // El conector: cuánto se anda hasta la parada siguiente. Va
                  // al pie del bloque, pegado a la línea del hilo, que es
                  // donde el diseño lo pinta. La última parada no lo tiene
                  // porque no hay siguiente, y con el tour bloqueado sí viaja:
                  // es logística, no guion.
                  if (!esUltima && parada.walkMinutesToNext != null) ...[
                    const SizedBox(height: 14),
                    _Caminata(minutos: parada.walkMinutesToNext!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El tramo a pie entre una parada y la siguiente.
///
/// Un dato pequeño que cambia la decisión entera: «18 min» entre dos paradas no
/// se planifica igual que «3 min». Por eso va escrito, y no implícito en la
/// distancia total del recorrido.
class _Caminata extends StatelessWidget {
  const _Caminata({required this.minutos});

  final int minutos;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: AztecTheme.separador,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emoji y no un icono de Material: el diseño usa 🚶 y además se
            // lee igual en las dos plataformas sin pedir una fuente de iconos.
            const Text('🚶', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(
              'Walk $minutos min',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AztecTheme.cuerpo),
            ),
          ],
        ),
      );
}

/// El audio de una parada, que todavía no suena.
///
/// Reproducirlo necesita un paquete más (`just_audio` o `audioplayers`) y, sobre
/// todo, necesita poder probarse: un reproductor escrito a ciegas, que no puedo
/// ejecutar ni una vez, es exactamente el tipo de código que luego falla en el
/// móvil de otro. Mientras tanto se enseña que la narración existe y cuánto
/// dura, que es la información que hace falta para decidir si se camina hasta
/// allí.
class _AudioPendiente extends StatelessWidget {
  const _AudioPendiente({required this.audio});

  final TourAudio audio;

  @override
  Widget build(BuildContext context) {
    final segundos = audio.durationSeconds;
    final duracion = segundos == null
        ? null
        : '${(segundos / 60).floor()}:'
            '${(segundos % 60).toString().padLeft(2, '0')}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(audio.isLocked ? Icons.lock_outline : Icons.headphones,
            size: 15, color: AztecTheme.tintaSuave),
        const SizedBox(width: 5),
        Text(
          audio.isLocked
              ? 'Audio with the full guide'
              : 'Audio${duracion == null ? '' : ' · $duracion'}',
          style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AztecTheme.tintaSuave),
        ),
      ],
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({
    required this.texto,
    required this.icono,
    required this.activo,
    required this.onPulsar,
  });

  final String texto;
  final IconData icono;
  final bool activo;
  final VoidCallback onPulsar;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: activo ? onPulsar : null,
          icon: Icon(icono, size: 20),
          label: Text(texto,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
          style: FilledButton.styleFrom(
            backgroundColor: AztecTheme.coral,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
}

/// El teaser de un tour de pago.
class _CandadoTour extends StatelessWidget {
  const _CandadoTour({required this.stopsCount});

  final int stopsCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AztecTheme.tinta,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lock_outline, color: Colors.white, size: 20),
            SizedBox(width: 9),
            Text('Part of the full guide',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          Text(
            '$stopsCount stops with narration, the route between them and the '
            'story of each one. One payment unlocks every tour — no '
            'subscription, it never expires.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 14.5,
                height: 1.5),
          ),
        ],
      ),
    );
  }
}
