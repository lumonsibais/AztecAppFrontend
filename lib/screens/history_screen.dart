import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme.dart';

/// Pestaña History: la guía histórica, con sus dos vistas del diseño.
///
/// La cronología llega ya ordenada por `sortOrder` desde el backend; aquí no se
/// reordena nada. El tiempo de lectura y el tema los pone el catálogo.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Future<List<HistoricalArticle>> _cronologia;
  late Future<List<Topic>> _temas;

  @override
  void initState() {
    super.initState();
    _cronologia = widget.api.cronologia();
    _temas = widget.api.temas();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AztecTheme.coral,
          unselectedLabelColor: AztecTheme.tintaSuave,
          indicatorColor: AztecTheme.coral,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [Tab(text: 'Chronology'), Tab(text: 'Topics')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          FutureBuilder<List<HistoricalArticle>>(
            future: _cronologia,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _mensaje('${snap.error}');
              }
              final articulos = snap.data ?? const <HistoricalArticle>[];
              if (articulos.isEmpty) {
                return _mensaje('No articles yet.');
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                itemCount: articulos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) =>
                    _TarjetaArticulo(articulo: articulos[i], indice: i),
              );
            },
          ),
          FutureBuilder<List<Topic>>(
            future: _temas,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _mensaje('${snap.error}');
              }
              final temas = snap.data ?? const <Topic>[];
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                itemCount: temas.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => Card(
                  child: ListTile(
                    title: Text(temas[i].topic,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: Text('${temas[i].count}',
                        style: const TextStyle(color: AztecTheme.tintaSuave)),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _mensaje(String texto) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AztecTheme.tintaSuave)),
        ),
      );
}

class _TarjetaArticulo extends StatelessWidget {
  const _TarjetaArticulo({required this.articulo, required this.indice});

  final HistoricalArticle articulo;
  final int indice;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: articulo.isRead == true
                    ? AztecTheme.coral
                    : AztecTheme.arena.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: articulo.isRead == true
                  ? const Icon(Icons.check, size: 17, color: Colors.white)
                  : Text('${indice + 1}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(articulo.title,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                height: 1.2)),
                      ),
                      if (articulo.muestraCandado)
                        const Padding(
                          padding: EdgeInsets.only(left: 8, top: 2),
                          child: Icon(Icons.lock,
                              size: 15, color: AztecTheme.tintaSuave),
                        ),
                    ],
                  ),
                  if (articulo.description != null) ...[
                    const SizedBox(height: 5),
                    Text(articulo.description!,
                        style: AztecTheme.tagline),
                  ],
                  const SizedBox(height: 9),
                  Wrap(spacing: 12, runSpacing: 4, children: [
                    if (articulo.topic != null)
                      Text(articulo.topic!,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AztecTheme.coral)),
                    if (articulo.readingTimeMinutes != null)
                      Text('${articulo.readingTimeMinutes} min read',
                          style: const TextStyle(
                              fontSize: 12.5, color: AztecTheme.tintaSuave)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
