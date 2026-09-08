import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets/place_card.dart';
import 'place_detail_screen.dart';

/// Pestaña Explore: el listado de sitios con los filtros de la barra.
///
/// Los filtros son los cuatro del diseño. "Near" no es una curaduría sino otro
/// endpoint —el que trae la distancia calculada por PostGIS—, así que se trata
/// aparte.
enum FiltroExplore { todos, cerca, mustSee, quickStops }

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  FiltroExplore _filtro = FiltroExplore.todos;
  late Future<List<Place>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<List<Place>> _cargar() {
    return switch (_filtro) {
      FiltroExplore.todos => widget.api.listarSitios(),
      FiltroExplore.mustSee => widget.api.listarSitios(curation: 'must_see'),
      FiltroExplore.quickStops =>
        widget.api.listarSitios(curation: 'quick_stop'),
      FiltroExplore.cerca => widget.api.sitiosCercanos(
          lat: Config.fallbackLat,
          lon: Config.fallbackLon,
        ),
    };
  }

  void _cambiarFiltro(FiltroExplore f) {
    setState(() {
      _filtro = f;
      _futuro = _cargar();
    });
  }

  Future<void> _alternarGuardado(Place p) async {
    if (!widget.api.haySesion) return;
    try {
      if (p.isSaved == true) {
        await widget.api.quitarSitio(p.id);
      } else {
        await widget.api.guardarSitio(p.id);
      }
      setState(() => _futuro = _cargar());
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _BarraDeFiltros(actual: _filtro, onCambio: _cambiarFiltro),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _futuro = _cargar()),
        child: FutureBuilder<List<Place>>(
          future: _futuro,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Error(
                error: snap.error!,
                onReintentar: () => setState(() => _futuro = _cargar()),
              );
            }

            final sitios = snap.data ?? const <Place>[];
            if (sitios.isEmpty) {
              return const _Vacio(mensaje: 'No places match this filter.');
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: sitios.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                final p = sitios[i];
                return PlaceCard(
                  place: p,
                  onToggleSaved:
                      widget.api.haySesion ? () => _alternarGuardado(p) : null,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          PlaceDetailScreen(api: widget.api, placeId: p.id),
                    ));
                    if (mounted) setState(() => _futuro = _cargar());
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BarraDeFiltros extends StatelessWidget {
  const _BarraDeFiltros({required this.actual, required this.onCambio});

  final FiltroExplore actual;
  final ValueChanged<FiltroExplore> onCambio;

  static const _etiquetas = {
    FiltroExplore.todos: 'All',
    FiltroExplore.cerca: 'Near',
    FiltroExplore.mustSee: 'Must See',
    FiltroExplore.quickStops: 'Quick Stops',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _etiquetas.entries.map((e) {
          final activo = e.key == actual;
          return Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 10),
            child: ChoiceChip(
              label: Text(e.value),
              selected: activo,
              onSelected: (_) => onCambio(e.key),
              showCheckmark: false,
              selectedColor: AztecTheme.coral,
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: activo ? Colors.white : AztecTheme.tinta,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.error, required this.onReintentar});

  final Object error;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final mensaje = error is ApiException
        ? (error as ApiException).message
        : "Couldn't reach the server.\n\n"
            'Check the backend is running at ${Config.apiBase}, or start the '
            'app against the mock:\n'
            'flutter run --dart-define=API_BASE=http://localhost:4010';

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.cloud_off, size: 46, color: AztecTheme.tintaSuave),
        const SizedBox(height: 16),
        Text(mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AztecTheme.tintaSuave, height: 1.5)),
        const SizedBox(height: 20),
        Center(
          child: FilledButton(
            onPressed: onReintentar,
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Text(mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AztecTheme.tintaSuave)),
      ],
    );
  }
}
