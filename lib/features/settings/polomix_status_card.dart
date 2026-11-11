import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/widgets/button_spinner.dart';
import '../../app/widgets/glass_card.dart';
import '../../coach/coach_error.dart';
import '../../coach/coach_repository.dart';
import '../../theme/evolup_theme.dart';
import '../coach/coach_messages.dart';

/// Real state of Polomix: whether the server holds its key (no call to
/// Polomix), and on demand a compatibility test that sends one short real
/// message and reports each check. Nothing is assumed: an unchecked point
/// is shown as « non vérifié ».
class PolomixStatusCard extends StatefulWidget {
  const PolomixStatusCard({required this.repository, super.key});

  /// `null` when Supabase is not configured.
  final CoachRepository? repository;

  @override
  State<PolomixStatusCard> createState() => _PolomixStatusCardState();
}

class _PolomixStatusCardState extends State<PolomixStatusCard> {
  CoachStatus? _status;
  CoachFailure? _statusFailure;
  CoachProbe? _probe;
  CoachFailure? _probeFailure;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
  }

  Future<void> _loadStatus() async {
    final repository = widget.repository;
    if (repository == null) return;
    try {
      final status = await repository.status();
      if (mounted) setState(() => _status = status);
    } on Object catch (error) {
      if (mounted) setState(() => _statusFailure = classifyCoachError(error));
    }
  }

  Future<void> _runProbe() async {
    setState(() {
      _probing = true;
      _probeFailure = null;
    });
    try {
      final probe = await widget.repository!.probe();
      if (mounted) setState(() => _probe = probe);
    } on Object catch (error) {
      if (mounted) setState(() => _probeFailure = classifyCoachError(error));
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final repository = widget.repository;
    final status = _status;
    final String state;
    if (repository == null) {
      state = 'Indisponible : la connexion au serveur n’est pas configurée.';
    } else if (_statusFailure != null) {
      state = 'État inconnu : ${coachFailureMessage(_statusFailure!)}';
    } else if (status == null) {
      state = 'Vérification…';
    } else {
      state = status.configured
          ? 'Configuré sur le serveur (modèle ${status.model ?? 'inconnu'}).'
          : 'Non configuré : la clé Polomix n’est pas installée sur le '
                'serveur.';
    }
    final probe = _probe;
    return GlassCard(
      key: const Key('polomix-status'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(state, key: const Key('polomix-state')),
          const SizedBox(height: 6),
          Text(
            'L’application reste utilisable sans Polomix : vos saisies et '
            'vos statistiques ne dépendent pas de lui.',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          if (probe != null) ...[
            const SizedBox(height: 12),
            _Check('Clé installée sur le serveur', probe.secret),
            _Check('Service Polomix joignable', probe.reachable),
            _Check('Clé acceptée par Polomix', probe.authorized),
            _Check('Réponse conforme au contrat documenté', probe.contract),
            const SizedBox(height: 6),
            Text(
              [
                probe.ok
                    ? 'Test réussi'
                    : 'Test échoué'
                          '${probe.failure == null ? '' : ' : ${coachFailureMessage(probe.failure!)}'}',
                if (probe.latencyMs != null) '${probe.latencyMs} ms',
                'le ${_time(probe.checkedAt)}',
              ].join(' · '),
              key: const Key('polomix-probe-result'),
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          if (_probeFailure != null) ...[
            const SizedBox(height: 10),
            Text(
              'Test impossible : ${coachFailureMessage(_probeFailure!)}',
              style: TextStyle(color: colors.error),
            ),
          ],
          if (repository != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('polomix-probe'),
              onPressed: _probing ? null : _runProbe,
              icon: _probing
                  ? ButtonSpinner(color: colors.textPrimary)
                  : const Icon(Icons.network_check_rounded),
              label: const Text('Tester la compatibilité'),
            ),
            const SizedBox(height: 4),
            Text(
              'Le test envoie un court message réel à Polomix (compte dans '
              'votre limite de messages).',
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  static String _time(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.day)}/${two(time.month)}/${time.year} à '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

class _Check extends StatelessWidget {
  const _Check(this.label, this.value);

  final String label;
  final bool? value;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final (icon, color, text) = switch (value) {
      true => (Icons.check_circle_rounded, colors.success, 'oui'),
      false => (Icons.cancel_rounded, colors.error, 'non'),
      null => (Icons.help_outline_rounded, colors.textSecondary, 'non vérifié'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text('$label : $text')),
        ],
      ),
    );
  }
}
