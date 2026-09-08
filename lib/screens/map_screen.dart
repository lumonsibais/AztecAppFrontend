import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme.dart';

/// Pestaña Map con el conmutador 1500 / 2026.
///
/// **Sin Google Maps todavía, y a propósito.** `google_maps_flutter` obliga a
/// dar de alta una clave de API y a tocar los proyectos nativos de iOS y
/// Android; eso es una tarde de configuración de cuentas, no de código, y
/// bloquearía poder ver la app funcionando hoy.
///
/// Mientras tanto, esto pinta los polígonos del backend con un CustomPainter
/// sobre coordenadas proyectadas a mano. No es el mapa final, pero prueba lo
/// que importa comprobar ahora: que el overlay llega bien, que `surfaceType`
/// decide el color y que el conmutador de época funciona de punta a punta.
///
/// Al enchufar Google Maps, `LakeFeature.rings` va tal cual a `Polygon(points:
/// ...)`; lo único que cambia es quién dibuja.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const int anioHistorico = 1500;
  static const int anioPresente = 2026;

  int _anio = anioHistorico;
  late Future<LakeOverlay> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = widget.api.overlayDelLago(year: _anio);
  }

  void _cambiarAnio(int anio) {
    setState(() {
      _anio = anio;
      _futuro = widget.api.overlayDelLago(year: anio);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _Conmutador(
              anio: _anio,
              onCambio: _cambiarAnio,
              historico: anioHistorico,
              presente: anioPresente,
            ),
          ),
        ],
      ),
      body: FutureBuilder<LakeOverlay>(
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

          final overlay = snap.data!;

          // Colección vacía: es el año presente. No es un error, es que el
          // overlay solo existe para la época histórica.
          if (overlay.features.isEmpty) {
            return const _SinOverlay();
          }

          return Column(
            children: [
              Expanded(
                child: Container(
                  color: AztecTheme.hueso,
                  child: CustomPaint(
                    painter: _PintorDelLago(overlay.features),
                    size: Size.infinite,
                  ),
                ),
              ),
              _Leyenda(features: overlay.features),
            ],
          );
        },
      ),
    );
  }
}

class _Conmutador extends StatelessWidget {
  const _Conmutador({
    required this.anio,
    required this.onCambio,
    required this.historico,
    required this.presente,
  });

  final int anio;
  final ValueChanged<int> onCambio;
  final int historico;
  final int presente;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AztecTheme.linea),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [historico, presente].map((a) {
          final activo = a == anio;
          return GestureDetector(
            onTap: () => onCambio(a),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                color: activo ? AztecTheme.coral : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text('$a',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: activo ? Colors.white : AztecTheme.tintaSuave)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SinOverlay extends StatelessWidget {
  const _SinOverlay();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 46, color: AztecTheme.tintaSuave),
            SizedBox(height: 14),
            Text('Mexico City, today',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            SizedBox(height: 7),
            Text(
              'No historical layer today — this is the city as it is. '
              'Tap 1500 to bring back the lake.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AztecTheme.tintaSuave, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.features});

  final List<LakeFeature> features;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: features.map((f) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: f.esAgua ? AztecTheme.agua : AztecTheme.arena,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(f.tenochtitlanName ?? f.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Text(f.esAgua ? 'water' : 'land',
                  style: const TextStyle(
                      fontSize: 12, color: AztecTheme.tintaSuave)),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

/// Dibuja los polígonos proyectando lon/lat al lienzo.
///
/// Proyección plana: a la escala de una ciudad la distorsión es irrelevante y
/// esto es un sustituto temporal del mapa de verdad.
class _PintorDelLago extends CustomPainter {
  _PintorDelLago(this.features);

  final List<LakeFeature> features;

  @override
  void paint(Canvas canvas, Size size) {
    if (features.isEmpty) return;

    // Encuadre común a todos los polígonos.
    double minLon = double.infinity, maxLon = -double.infinity;
    double minLat = double.infinity, maxLat = -double.infinity;

    for (final f in features) {
      for (final anillo in f.rings) {
        for (final punto in anillo) {
          if (punto.length < 2) continue;
          minLon = punto[0] < minLon ? punto[0] : minLon;
          maxLon = punto[0] > maxLon ? punto[0] : maxLon;
          minLat = punto[1] < minLat ? punto[1] : minLat;
          maxLat = punto[1] > maxLat ? punto[1] : maxLat;
        }
      }
    }

    final anchoGeo = maxLon - minLon;
    final altoGeo = maxLat - minLat;
    if (anchoGeo <= 0 || altoGeo <= 0) return;

    const margen = 24.0;
    // `.toDouble()` explícito: `clamp` está declarado en `num` y según la
    // versión del SDK devuelve `num`, que no se puede pasar donde `Offset`
    // espera un `double`.
    final double escala = ((size.width - margen * 2) / anchoGeo)
        .clamp(0.0, (size.height - margen * 2) / altoGeo)
        .toDouble();

    Offset proyectar(List<double> p) => Offset(
          margen + (p[0] - minLon) * escala,
          // La latitud crece hacia el norte y la Y del lienzo hacia abajo.
          size.height - margen - (p[1] - minLat) * escala,
        );

    // El agua primero y la tierra encima: el backend ya los manda en ese
    // orden, así que basta con respetarlo.
    for (final f in features) {
      final relleno = Paint()
        ..style = PaintingStyle.fill
        ..color = f.esAgua ? AztecTheme.agua : AztecTheme.arena;
      final borde = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = (f.esAgua ? AztecTheme.agua : AztecTheme.arena)
            .withOpacity(0.9);

      for (final anillo in f.rings) {
        if (anillo.length < 3) continue;
        final ruta = Path()..moveTo(
            proyectar(anillo.first).dx, proyectar(anillo.first).dy);
        for (final punto in anillo.skip(1)) {
          if (punto.length < 2) continue;
          final o = proyectar(punto);
          ruta.lineTo(o.dx, o.dy);
        }
        ruta.close();
        canvas.drawPath(ruta, relleno);
        canvas.drawPath(ruta, borde);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PintorDelLago anterior) =>
      anterior.features != features;
}
