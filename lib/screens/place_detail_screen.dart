import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme.dart';

/// Ficha de un sitio.
///
/// Esta pantalla es donde se ve la línea del paywall, y conviene entenderla al
/// mirarla: la LOGÍSTICA —taquilla, horarios, cómo llegar, avisos de
/// seguridad— se pinta siempre, porque son datos del mundo real. Lo que se
/// esconde tras el candado es lo que escribimos nosotros.
class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({
    super.key,
    required this.api,
    required this.placeId,
  });

  final ApiClient api;
  final String placeId;

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  late Future<Place> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = widget.api.sitio(widget.placeId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Place>(
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

          final p = snap.data!;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                backgroundColor: AztecTheme.hueso,
                flexibleSpace: FlexibleSpaceBar(
                  background: p.imageUrl == null
                      ? Container(color: AztecTheme.arena.withOpacity(0.4))
                      : Image.network(p.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: AztecTheme.arena.withOpacity(0.4))),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(p.name,
                        style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.6)),
                    if (p.tagline != null) ...[
                      const SizedBox(height: 8),
                      Text(p.tagline!,
                          style: const TextStyle(
                              fontSize: 16,
                              color: AztecTheme.tintaSuave,
                              height: 1.4)),
                    ],
                    if (p.location.neighborhood != null) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        const Icon(Icons.place_outlined,
                            size: 17, color: AztecTheme.tintaSuave),
                        const SizedBox(width: 5),
                        Text(p.location.neighborhood!,
                            style: const TextStyle(
                                color: AztecTheme.tintaSuave, fontSize: 14)),
                      ]),
                    ],

                    // --- LOGÍSTICA: siempre visible ---
                    const SizedBox(height: 26),
                    if (p.entryFee != null) _Taquilla(fee: p.entryFee!),
                    if (p.openingHours != null)
                      _Fila(
                          icono: Icons.schedule,
                          titulo: 'Hours',
                          texto: p.openingHours!),
                    if (p.visitDurationText != null)
                      _Fila(
                          icono: Icons.hourglass_empty,
                          titulo: 'How long',
                          texto: p.visitDurationText!),
                    if (p.howToGetThere != null)
                      _Fila(
                          icono: Icons.directions_subway_outlined,
                          titulo: 'Getting there',
                          texto: p.howToGetThere!),
                    if (p.safetyRecommendations != null)
                      _Fila(
                          icono: Icons.info_outline,
                          titulo: 'Good to know',
                          texto: p.safetyRecommendations!),

                    // --- CONTENIDO: detrás del desbloqueo ---
                    const SizedBox(height: 22),
                    if (p.muestraCandado)
                      const _Candado()
                    else ...[
                      if (p.description != null)
                        _Bloque(titulo: 'About', texto: p.description!),
                      if (p.whyVisit != null)
                        _Bloque(titulo: 'Why visit', texto: p.whyVisit!),
                      if (p.historicalSignificance != null)
                        _Bloque(
                            titulo: 'Historical significance',
                            texto: p.historicalSignificance!),
                      if (p.historicalContext?.tenochtitlanName != null)
                        _Bloque(
                            titulo: 'In Tenochtitlan',
                            texto: p.historicalContext!.tenochtitlanName!),
                    ],
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Taquilla extends StatelessWidget {
  const _Taquilla({required this.fee});

  final EntryFee fee;

  @override
  Widget build(BuildContext context) {
    final importes = <String>[
      if (fee.mxn != null) '${fee.mxn!.toStringAsFixed(0)} MXN',
      if (fee.usd != null) '\$${fee.usd!.toStringAsFixed(2)} USD',
    ];

    return _Fila(
      icono: Icons.confirmation_number_outlined,
      titulo: 'Entry',
      texto: fee.isFree
          ? (fee.text ?? 'Free')
          : [importes.join('  ·  '), if (fee.text != null) fee.text!]
              .where((s) => s.isNotEmpty)
              .join('\n'),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icono,
    required this.titulo,
    required this.texto,
  });

  final IconData icono;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 19, color: AztecTheme.coral),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: AztecTheme.etiqueta
                        .copyWith(color: AztecTheme.tintaSuave)),
                const SizedBox(height: 3),
                Text(texto, style: const TextStyle(fontSize: 15, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bloque extends StatelessWidget {
  const _Bloque({required this.titulo, required this.texto});

  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, height: 1.3)),
          const SizedBox(height: 7),
          Text(texto,
              style: const TextStyle(fontSize: 15.5, height: 1.55)),
        ],
      ),
    );
  }
}

/// El teaser. Lo que se ofrece a cambio de los 15 dólares.
class _Candado extends StatelessWidget {
  const _Candado();

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
            Text('Unlock the full story',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          Text(
            'One payment of \$15 unlocks every site, every article and every '
            'audio tour. No subscription — it never expires.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 14.5,
                height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AztecTheme.coral,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              // La pasarela todavía no existe: providers.verificar() responde
              // 501 a propósito. Enchufar esto es el siguiente sprint.
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payments are not wired up yet.'),
                ),
              ),
              child: const Text('Unlock for \$15',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
