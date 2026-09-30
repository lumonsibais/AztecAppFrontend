import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/session_scope.dart';
import '../../theme.dart';
import '../auth/auth_screen.dart' show pedirEntrar;

/// Leer un artículo de la guía histórica.
///
/// Hasta ahora la cronología era un callejón: la lista se pintaba y al tocar un
/// artículo no pasaba nada. `articulo()`, `marcarLeido()` y `desmarcarLeido()`
/// llevaban escritos en el cliente desde el primer sprint sin que nadie los
/// llamara.
///
/// El `nextContentId` que trae el detalle es lo que encadena la cronología: se
/// lee un artículo y se sigue al siguiente sin volver a la lista. Lo calcula el
/// backend por `sortOrder`, así que aquí no se ordena nada.
class ArticleScreen extends StatefulWidget {
  const ArticleScreen({super.key, required this.api, required this.articleId});

  final ApiClient api;
  final String articleId;

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late String _id = widget.articleId;
  late Future<HistoricalArticle> _futuro = widget.api.articulo(_id);

  /// El estado de leído se pinta desde aquí y no desde el artículo recargado:
  /// marcar y esperar un viaje de red entero para ver la palomita se siente
  /// roto. Si la petición falla, se revierte.
  bool? _leidoLocal;

  void _ir(String id) {
    setState(() {
      _id = id;
      _leidoLocal = null;
      _futuro = widget.api.articulo(id);
    });
  }

  Future<void> _alternarLeido(HistoricalArticle a) async {
    final sesion = SessionScope.sin(context);

    if (!sesion.haySesion) {
      final entro = await pedirEntrar(
        context,
        motivo: 'Sign in to keep track of what you have already read.',
      );
      if (!entro || !mounted) return;
      setState(() => _futuro = widget.api.articulo(_id));
      return;
    }

    final estaba = _leidoLocal ?? a.isRead ?? false;
    setState(() {
      _leidoLocal = !estaba;
    });

    try {
      if (estaba) {
        await widget.api.desmarcarLeido(a.id);
      } else {
        await widget.api.marcarLeido(a.id);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _leidoLocal = estaba);   // se revierte
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Al desbloquear en otra pantalla, el contenido de este artículo pasa a
    // viajar en la respuesta. Escuchar la sesión es lo que hace que se note.
    SessionScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: FutureBuilder<HistoricalArticle>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _centrado('${snap.error}');
          }

          final a = snap.data!;
          final leido = _leidoLocal ?? a.isRead ?? false;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            children: [
              Text(a.title,
                  style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.5)),
              const SizedBox(height: 10),
              Wrap(spacing: 14, runSpacing: 4, children: [
                if (a.topic != null) _dato(a.topic!),
                if (a.era != null) _dato(a.era!),
                if (a.readingTimeMinutes != null)
                  _dato('${a.readingTimeMinutes} min read'),
              ]),
              const SizedBox(height: 20),

              if (a.description != null) ...[
                Text(a.description!,
                    style: const TextStyle(
                        fontSize: 17,
                        height: 1.5,
                        color: AztecTheme.tintaSuave)),
                const SizedBox(height: 20),
              ],

              if (a.content != null)
                Text(a.content!,
                    style: const TextStyle(fontSize: 16.5, height: 1.6))
              else
                const _ContenidoBloqueado(),

              const SizedBox(height: 28),

              // Marcar leído solo tiene sentido si hay algo que leer.
              if (a.content != null)
                OutlinedButton.icon(
                  onPressed: () => _alternarLeido(a),
                  icon: Icon(
                      leido
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      size: 20),
                  label: Text(leido ? 'Read' : 'Mark as read'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        leido ? AztecTheme.coral : AztecTheme.tinta,
                    side: BorderSide(
                        color: leido ? AztecTheme.coral : AztecTheme.linea),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),

              if (a.nextContentId != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _ir(a.nextContentId!),
                  icon: const Icon(Icons.arrow_forward, size: 19),
                  label: const Text('Next in the chronology'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AztecTheme.coral,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _dato(String texto) => Text(
        texto,
        style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AztecTheme.tintaSuave),
      );

  Widget _centrado(String texto) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AztecTheme.tintaSuave)),
        ),
      );
}

/// Lo que se ve cuando el artículo existe pero el cuerpo no viaja.
///
/// El servidor NO manda `content` si la cuenta no tiene el desbloqueo, así que
/// aquí no hay nada que esconder con un widget: el texto no ha llegado. Eso es
/// lo correcto —un paywall que manda el contenido y lo tapa en el cliente no es
/// un paywall— y por eso este bloque no puede "revelar" nada.
class _ContenidoBloqueado extends StatelessWidget {
  const _ContenidoBloqueado();

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
            'One payment unlocks every article, every site and every audio '
            'tour. No subscription — it never expires.',
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
