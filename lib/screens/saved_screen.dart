import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/place_card.dart';
import 'place_detail_screen.dart';

/// Pestaña Saved. Sin sesión no hay nada que enseñar, así que lo dice.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key, required this.api, required this.onPedirEntrar});

  final ApiClient api;
  final VoidCallback onPedirEntrar;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  Future<List<Place>>? _futuro;

  @override
  void initState() {
    super.initState();
    if (widget.api.haySesion) _futuro = widget.api.sitiosGuardados();
  }

  @override
  void didUpdateWidget(SavedScreen old) {
    super.didUpdateWidget(old);
    if (widget.api.haySesion && _futuro == null) {
      setState(() => _futuro = widget.api.sitiosGuardados());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: !widget.api.haySesion
          ? _SinSesion(onEntrar: widget.onPedirEntrar)
          : RefreshIndicator(
              onRefresh: () async =>
                  setState(() => _futuro = widget.api.sitiosGuardados()),
              child: FutureBuilder<List<Place>>(
                future: _futuro,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _centrado('${snap.error}');
                  }

                  final sitios = snap.data ?? const <Place>[];
                  if (sitios.isEmpty) {
                    return _centrado(
                        'Nothing saved yet.\n'
                        'Tap the heart on any place in Explore.');
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: sitios.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) => PlaceCard(
                      place: sitios[i],
                      onToggleSaved: () async {
                        await widget.api.quitarSitio(sitios[i].id);
                        setState(
                            () => _futuro = widget.api.sitiosGuardados());
                      },
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlaceDetailScreen(
                              api: widget.api, placeId: sitios[i].id),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _centrado(String texto) => ListView(
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

class _SinSesion extends StatelessWidget {
  const _SinSesion({required this.onEntrar});

  final VoidCallback onEntrar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_border,
                size: 46, color: AztecTheme.tintaSuave),
            const SizedBox(height: 16),
            const Text('Save the places you care about',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('You need an account to sync them across devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AztecTheme.tintaSuave, height: 1.45)),
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
