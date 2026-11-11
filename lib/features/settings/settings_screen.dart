import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/session/app_session.dart';
import '../../app/session/revision_reload.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/evolup_background.dart';
import '../../app/widgets/glass_card.dart';
import '../../app/widgets/state_views.dart';
import '../../data/data_error.dart';
import '../../data/metrics/metric_models.dart';
import '../../data/profile/user_profile.dart';
import '../../theme/evolup_theme.dart';
import '../metrics/metric_texts.dart';
import 'polomix_status_card.dart';
import 'timezone_picker.dart';

/// « Paramètres »: profile, preferences, privacy, connections (next
/// version), data management, Polomix status and sign-out. Every change is
/// saved to Supabase before it is shown.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with RevisionReload {
  Overview? _overview;
  bool _saving = false;
  bool _deleting = false;
  int _request = 0;

  @override
  Future<void> reload() async {
    // Only the latest reload may update the page: an older answer arriving
    // last would show older counts.
    final request = ++_request;
    try {
      final overview = await metrics.repository.loadOverview();
      if (mounted && request == _request) {
        setState(() => _overview = overview);
      }
    } on Object {
      // Counts are informative; the settings stay usable without them.
    }
  }

  Future<void> _save(ProfileChanges changes, {String? done}) async {
    setState(() => _saving = true);
    try {
      await SessionScope.read(context).profile.update(changes);
      if (mounted && done != null) showMessage(context, done);
    } on Object catch (error) {
      if (mounted) showMessage(context, dataErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editName(UserProfile profile) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(initial: profile.displayName ?? ''),
    );
    if (name == null || !mounted) return;
    final trimmed = name.trim();
    await _save(
      trimmed.isEmpty
          ? const ProfileChanges(clearDisplayName: true)
          : ProfileChanges(displayName: trimmed),
      done: 'Nom enregistré.',
    );
  }

  Future<void> _editTimezone(UserProfile profile) async {
    final session = SessionScope.read(context);
    final device = await session.deviceTimezone.current();
    if (!mounted) return;
    final zone = await showTimezonePicker(
      context,
      current: profile.timezone,
      deviceZone: device,
      load: session.metrics.repository.loadTimezones,
    );
    if (zone == null || zone == profile.timezone || !mounted) return;
    await _save(
      ProfileChanges(timezone: zone),
      done: 'Fuseau horaire enregistré.',
    );
  }

  Future<void> _deleteAll() async {
    final confirmed = await confirmAction(
      context,
      title: 'Supprimer toutes vos données de suivi ?',
      message:
          'Tous vos indicateurs suivis et toutes les journées enregistrées '
          'seront définitivement supprimés. Votre compte et vos préférences '
          'sont conservés.',
      confirmLabel: 'Tout supprimer',
      destructive: true,
    );
    if (!confirmed || !mounted || _deleting) return;
    setState(() => _deleting = true);
    try {
      // One atomic request: everything is deleted, or nothing.
      await metrics.deleteAllTracked();
      if (mounted) {
        showMessage(context, 'Vos données de suivi sont supprimées.');
      }
    } on Object catch (error) {
      if (mounted) showMessage(context, dataErrorMessage(error));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return ListenableBuilder(
      listenable: session.profile,
      builder: (context, _) => _build(context, session),
    );
  }

  Widget _build(BuildContext context, SignedInSession session) {
    final profile = session.profile.profile;
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final overview = _overview;
    final muted = textTheme.bodySmall?.copyWith(color: colors.textSecondary);
    return EvolupBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Paramètres')),
        body: PageBody(
          children: [
            const SectionHeader('Profil'),
            _Card(
              children: [
                ListTile(
                  leading: const Icon(Icons.alternate_email_rounded),
                  title: const Text('Adresse e-mail'),
                  subtitle: Text(session.email ?? '—'),
                ),
                ListTile(
                  key: const Key('settings-name'),
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Nom d’affichage'),
                  subtitle: Text(profile.displayName ?? 'Non renseigné'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _saving ? null : () => unawaited(_editName(profile)),
                ),
                ListTile(
                  key: const Key('settings-timezone'),
                  leading: const Icon(Icons.public_rounded),
                  title: const Text('Fuseau horaire'),
                  subtitle: Text(
                    '${profile.timezone} · utilisé pour « aujourd’hui » dans '
                    'vos statistiques',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _saving
                      ? null
                      : () => unawaited(_editTimezone(profile)),
                ),
              ],
            ),
            const SectionHeader('Préférences'),
            _Card(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Palette', style: textTheme.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final palette in AppPalette.values)
                      _PaletteChoice(
                        key: Key('palette-${palette.storageValue}'),
                        palette: palette,
                        mode: profile.appearance.mode,
                        selected: profile.appearance.palette == palette,
                        onTap: _saving
                            ? null
                            : () => unawaited(
                                _save(ProfileChanges(palette: palette)),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Mode d’affichage', style: textTheme.titleSmall),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AppThemeMode>(
                    key: const Key('settings-mode'),
                    showSelectedIcon: false,
                    segments: [
                      for (final mode in AppThemeMode.values)
                        ButtonSegment(
                          value: mode,
                          label: Text(mode.label),
                          icon: Icon(
                            mode == AppThemeMode.dark
                                ? Icons.dark_mode_outlined
                                : Icons.light_mode_outlined,
                          ),
                        ),
                    ],
                    selected: {profile.appearance.mode},
                    onSelectionChanged: _saving
                        ? null
                        : (selection) => unawaited(
                            _save(ProfileChanges(mode: selection.first)),
                          ),
                  ),
                ),
              ],
            ),
            const SectionHeader('Confidentialité'),
            _Card(
              children: [
                SwitchListTile(
                  key: const Key('settings-coach-access'),
                  value: profile.coachDataAccess,
                  onChanged: _saving
                      ? null
                      : (value) => unawaited(
                          _save(ProfileChanges(coachDataAccess: value)),
                        ),
                  title: const Text('Polomix peut consulter mes données'),
                  subtitle: Text(
                    'Pour chaque question, seuls les indicateurs concernés '
                    '(valeurs, dates, statistiques) sont transmis au service '
                    'Polomix, sans votre nom ni votre e-mail. Désactivé : '
                    'Polomix répond sans connaître vos valeurs.',
                    style: muted,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Text(
                    'Vos données sont privées : chaque compte n’accède qu’à '
                    'ses propres données, et Polomix ne peut jamais enregistrer, '
                    'modifier ou supprimer une valeur.',
                    style: muted,
                  ),
                ),
              ],
            ),
            const SectionHeader('Connexions'),
            _Card(
              children: [
                ListTile(
                  key: const Key('settings-connections'),
                  leading: const Icon(Icons.watch_outlined),
                  title: const Text('Montres, Health Connect, services tiers'),
                  subtitle: Text(
                    'Disponible dans une prochaine version. Aucune connexion '
                    'externe n’est active : vos données sont saisies '
                    'manuellement.',
                    style: muted,
                  ),
                ),
              ],
            ),
            const SectionHeader('Gestion des données'),
            _Card(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  overview == null
                      ? 'Chargement du résumé…'
                      : '${metricsLabel(metrics.tracked.length)} dans votre '
                            'espace · ${countLabel(overview.daysRecorded, 'journée renseignée', 'journées renseignées')} · '
                            '${countLabel(overview.entriesCount, 'saisie intégrée', 'saisies intégrées')}.',
                  key: const Key('settings-data-summary'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pour corriger ou supprimer une journée, ouvrez la fiche de '
                  'l’indicateur dans « Mes données ».',
                  style: muted,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('settings-delete-all'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side: BorderSide(
                      color: colors.error.withValues(alpha: 0.5),
                    ),
                  ),
                  onPressed: _deleting || metrics.tracked.isEmpty
                      ? null
                      : () => unawaited(_deleteAll()),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(
                    _deleting
                        ? 'Suppression…'
                        : 'Supprimer toutes mes données de suivi',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'La suppression du compte lui-même n’est pas encore '
                  'disponible dans l’application.',
                  style: muted,
                ),
              ],
            ),
            const SectionHeader('Polomix'),
            PolomixStatusCard(repository: session.coach),
            const SectionHeader('Compte'),
            OutlinedButton.icon(
              key: const Key('settings-sign-out'),
              onPressed: () async {
                try {
                  await session.signOut();
                } on Object {
                  if (context.mounted) {
                    showMessage(context, 'La déconnexion a échoué. Réessayez.');
                  }
                }
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Se déconnecter'),
            ),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nom d’affichage'),
    content: TextField(
      key: const Key('settings-name-field'),
      controller: _controller,
      autofocus: true,
      maxLength: 60,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        hintText: 'Facultatif',
        counterText: '',
      ),
      onSubmitted: (value) => Navigator.of(context).pop(value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const Key('settings-name-save'),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: padding ?? const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _PaletteChoice extends StatelessWidget {
  const _PaletteChoice({
    required this.palette,
    required this.mode,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final AppPalette palette;
  final AppThemeMode mode;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final preview = EvolupColors.resolve(
      AppAppearance(palette: palette, mode: mode),
    );
    final colors = EvolupColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Palette ${palette.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 116,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: preview.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.accent : colors.glassBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (final color in [
                    preview.haloPrimary,
                    preview.haloSecondary,
                    preview.accent,
                  ])
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                palette.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: preview.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
