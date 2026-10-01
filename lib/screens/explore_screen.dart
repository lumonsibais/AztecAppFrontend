import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets/account_button.dart';
import '../widgets/place_card.dart';
import 'auth/auth_screen.dart' show pedirEntrar;
import 'place_detail_screen.dart';
import 'tours/tours_screen.dart';

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
    // Sin sesión el corazón no se quedaba quieto sin explicar nada: se pide la
    // cuenta en ese momento, diciendo para qué, y si se consigue entrar se
    // guarda el sitio que se quería guardar. Obligar a entrar ANTES de poder
    // tocar el corazón haría que nadie llegara a saber para qué sirve.
    if (!widget.api.haySesion) {
      final entro = await pedirEntrar(
        context,
        motivo: 'Sign in to save ${p.name} and find it again later.',
        registro: true,
      );
      if (!entro || !mounted) return;
      // Al entrar, el servidor ya sabe qué tiene guardado esta cuenta: se
      // recarga la lista para que los corazones reflejen eso y no lo que se
      // veía como invitado.
      setState(() => _futuro = _cargar());
    }

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
    // Sin AppBar: el diseño pone un encabezado dentro del contenido —"Start
    // exploring" en Playfair sobre la ciudad— y el acceso a la cuenta como un
    // círculo coral a su derecha. Una AppBar de Material no da esa forma.
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => setState(() => _futuro = _cargar()),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _Encabezado()),
              SliverToBoxAdapter(
                child: _BarraDeFiltros(
                    actual: _filtro, onCambio: _cambiarFiltro),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 14),
                  child: Text('Aztec Sites in Mexico City',
                      style: AztecTheme.h2),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(17, 0, 17, 14),
                  child: _EntradaTours(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ToursScreen(api: widget.api),
                    )),
                  ),
                ),
              ),
              _cuadricula(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cuadricula() {
    return FutureBuilder<List<Place>>(
      future: _futuro,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snap.hasError) {
          return SliverToBoxAdapter(
            child: _Error(
              error: snap.error!,
              onReintentar: () => setState(() => _futuro = _cargar()),
            ),
          );
        }

        final sitios = snap.data ?? const <Place>[];
        if (sitios.isEmpty) {
          return const SliverToBoxAdapter(
            child: _Vacio(mensaje: 'No places match this filter.'),
          );
        }

        // Dos columnas, como el diseño. `childAspectRatio` sale de las medidas
        // del archivo: tarjetas de 170×274.
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(17, 0, 17, 28),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 10,
              childAspectRatio: 170 / 274,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final p = sitios[i];
                return PlaceCard(
                  place: p,
                  // Siempre activo, con o sin sesión: si no hay, el propio
                  // callback pide la cuenta.
                  onToggleSaved: () => _alternarGuardado(p),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          PlaceDetailScreen(api: widget.api, placeId: p.id),
                    ));
                    if (mounted) setState(() => _futuro = _cargar());
                  },
                );
              },
              childCount: sitios.length,
            ),
          ),
        );
      },
    );
  }
}

/// "Start exploring" y la ciudad, con el acceso a la cuenta a la derecha.
class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Start exploring', style: AztecTheme.h1),
                SizedBox(height: 2),
                // La ciudad es fija a propósito: el producto es la CDMX. El día
                // que haya otra, sale de la ubicación.
                Text('📍 Mexico City, MX', style: AztecTheme.descripcion),
              ],
            ),
          ),
          AccountButton(),
        ],
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
    // Píldoras de 44 de alto, no `ChoiceChip`: el chip de Material trae su
    // propia forma, su propio relleno y su propia animación de selección, y
    // ninguna de las tres es la del diseño.
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        children: _etiquetas.entries.map((e) {
          final activo = e.key == actual;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onCambio(e.key),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: activo ? AztecTheme.coral : Colors.white,
                  borderRadius:
                      BorderRadius.circular(AztecTheme.radioPildora),
                  border: Border.all(
                      color: activo ? AztecTheme.coral : AztecTheme.linea),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(activo ? 0.17 : 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  e.value,
                  style: AztecTheme.textoBoton.copyWith(
                    color: activo ? Colors.white : AztecTheme.tinta,
                  ),
                ),
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


/// La entrada a los tours, arriba del listado de Explore.
///
/// DECISIÓN DE DISEÑO, y conviene que se vea: el diseño tiene cuatro pestañas y
/// los tours no son una de ellas, así que hay que meterlos por algún lado.
/// Aquí, porque un tour es una forma de recorrer sitios y Explore es donde se
/// buscan sitios. Si el Figma dice otra cosa, esto es una tarjeta y se mueve de
/// sitio en dos minutos.
class _EntradaTours extends StatelessWidget {
  const _EntradaTours({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AztecTheme.arena.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.route_outlined,
                    size: 22, color: AztecTheme.tinta),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Self-guided tours',
                        style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            height: 1.2)),
                    SizedBox(height: 3),
                    Text('Walk a route with the story along the way.',
                        style: AztecTheme.tagline),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AztecTheme.tintaSuave),
            ],
          ),
        ),
      ),
    );
  }
}
