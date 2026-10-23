import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme_preferences_screen.dart';
import '../../data/athlete_profile.dart';
import '../../data/preferences_store.dart';
import '../../theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.initialProfile,
    required this.themeController,
    required this.onSave,
    required this.onSignOut,
    super.key,
  });

  final AthleteProfile initialProfile;
  final ThemeController themeController;
  final Future<void> Function(AthleteProfile) onSave;
  final Future<void> Function() onSignOut;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _sportsOptions = [
    'Musculation',
    'Course à pied',
    'Vélo',
    'Natation',
    'Sports collectifs',
    'Arts martiaux',
    'Street workout',
    'Autre',
  ];
  static const _goals = [
    'Force',
    'Développement musculaire',
    'Endurance',
    'Street workout / calisthenics',
    'Condition physique générale',
    'Reprise progressive',
  ];
  static const _locationOptions = [
    'Domicile',
    'Salle de sport',
    'Street workout',
  ];
  static const _equipmentOptions = [
    'Aucun',
    'Haltères',
    'Barre et poids',
    'Élastiques',
    'Kettlebell',
    'Banc',
    'Machines',
    'Barre de traction',
    'Autre',
  ];
  static const _dayOptions = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];
  static const _levels = ['Débutant', 'Intermédiaire', 'Avancé'];
  static const _wearables = [
    'Aucune',
    'Apple Health',
    'Health Connect',
    'Garmin',
    'Fitbit',
    'Autre',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _age;
  late final TextEditingController _customGoal;
  late final TextEditingController _limitations;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late Set<String> _sports;
  late Set<String> _secondaryGoals;
  late Set<String> _locations;
  late Set<String> _equipment;
  late Set<String> _days;
  int? _frequency;
  int? _duration;
  String? _level;
  String? _primaryGoal;
  String? _wearable;
  int _step = 0;
  bool _saving = false;
  String? _error;

  AthleteProfile get _initial => widget.initialProfile;

  @override
  void initState() {
    super.initState();
    _age = TextEditingController(text: _initial.age?.toString() ?? '');
    _customGoal = TextEditingController(text: _initial.customGoal ?? '');
    _limitations = TextEditingController(text: _initial.limitations ?? '');
    _height = TextEditingController(
      text: _initial.heightCm?.toStringAsFixed(0) ?? '',
    );
    _weight = TextEditingController(
      text: _initial.weightKg?.toStringAsFixed(1) ?? '',
    );
    _sports = _initial.sports.toSet();
    _secondaryGoals = _initial.secondaryGoals.toSet();
    _locations = _initial.trainingLocations.toSet();
    _equipment = _initial.equipment.toSet();
    _days = _initial.availableDays.toSet();
    _frequency = _initial.weeklyFrequency;
    _duration = _initial.sessionDurationMinutes;
    _level = _initial.level;
    _primaryGoal = _initial.primaryGoal;
    _wearable = _initial.wearableSource ?? 'Aucune';
    _step = _initial.onboardingStep.clamp(0, 2).toInt();
  }

  @override
  void dispose() {
    _age.dispose();
    _customGoal.dispose();
    _limitations.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  AthleteProfile _collectProfile({required int step, required bool complete}) {
    return AthleteProfile(
      age: int.tryParse(_age.text),
      sports: _sports.toList(),
      weeklyFrequency: _frequency,
      level: _level,
      primaryGoal: _primaryGoal,
      secondaryGoals: _secondaryGoals.toList(),
      customGoal: _customGoal.text.trim().isEmpty
          ? null
          : _customGoal.text.trim(),
      trainingLocations: _locations.toList(),
      equipment: _equipment.toList(),
      availableDays: _days.toList(),
      sessionDurationMinutes: _duration,
      limitations: _limitations.text.trim().isEmpty
          ? null
          : _limitations.text.trim(),
      heightCm: double.tryParse(_height.text.replaceAll(',', '.')),
      weightKg: double.tryParse(_weight.text.replaceAll(',', '.')),
      wearableSource: _wearable == 'Aucune' ? null : _wearable,
      palette: widget.themeController.value.palette,
      isDark: widget.themeController.value.isDark,
      onboardingStep: step,
      onboardingCompleted: complete,
    );
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    final fieldsAreValid = _formKey.currentState!.validate();
    if (_step == 0 && _sports.isEmpty) {
      setState(() => _error = 'Choisissez au moins un sport pratiqué.');
      return;
    }
    if (!fieldsAreValid) return;
    if (_step == 1 && _primaryGoal == null) {
      setState(() => _error = 'Choisissez votre objectif principal.');
      return;
    }
    if (_step == 2 && _locations.isEmpty) {
      setState(
        () => _error = 'Choisissez au moins un lieu d’entraînement disponible.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final nextStep = (_step + 1).clamp(0, 2).toInt();
    try {
      await widget.onSave(
        _collectProfile(step: nextStep, complete: _step == 2),
      );
      if (!mounted) return;
      if (_step < 2) setState(() => _step++);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Enregistrement impossible. Vérifiez votre connexion et '
              'les autorisations Supabase, puis réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _previous() async {
    if (_step == 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_collectProfile(step: _step - 1, complete: false));
      if (mounted) setState(() => _step--);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Le brouillon n’a pas pu être enregistré. Vérifiez votre '
              'connexion puis réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.onSignOut();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'La déconnexion a échoué. Réessayez.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Votre profil sportif'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: _saving ? null : _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Étape ${_step + 1} sur 3',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: (_step + 1) / 3),
                    const SizedBox(height: 24),
                    Text(
                      _step == 0
                          ? 'Parlons de vous'
                          : _step == 1
                          ? 'Ce que vous souhaitez atteindre'
                          : 'Vos conditions d’entraînement',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _step == 0
                          ? 'Quelques repères pour adapter votre expérience.'
                          : _step == 1
                          ? 'Votre objectif pourra évoluer avec vous.'
                          : 'Les champs marqués comme facultatifs peuvent être '
                                'laissés vides.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: _step == 0
                              ? _buildAboutStep()
                              : _step == 1
                              ? _buildGoalsStep()
                              : _buildConditionsStep(),
                        ),
                      ),
                    ),
                    if (_step == 0) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: ThemePreferencesScreen(
                            preferences: widget.themeController.value,
                            onChanged: (value) =>
                                unawaited(_updateLocalTheme(value)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        if (_step > 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : _previous,
                              child: const Text('Précédent'),
                            ),
                          ),
                        if (_step > 0) const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            key: const Key('onboarding-next'),
                            onPressed: _saving ? null : _next,
                            child: _saving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_step == 2 ? 'Terminer' : 'Continuer'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Vos réponses sont enregistrées à chaque étape. '
                      'Vous pourrez modifier votre profil plus tard.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        key: const Key('profile-age'),
        controller: _age,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Âge', suffixText: 'ans'),
        validator: (value) {
          final age = int.tryParse(value ?? '');
          return age != null && age >= 13 && age <= 120
              ? null
              : 'Indiquez un âge compris entre 13 et 120 ans.';
        },
      ),
      const SizedBox(height: 20),
      const _FieldTitle('Quels sports pratiquez-vous actuellement ?'),
      _MultiChoiceChips(
        options: _sportsOptions,
        selected: _sports,
        onChanged: (value) => setState(() => _sports = value),
      ),
      const SizedBox(height: 20),
      DropdownButtonFormField<int>(
        key: const Key('profile-frequency'),
        initialValue: _frequency,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Séances par semaine actuellement',
        ),
        items: List.generate(
          8,
          (index) => DropdownMenuItem(
            value: index,
            child: Text(index == 0 ? '0 — Reprise' : '$index'),
          ),
        ),
        onChanged: (value) => setState(() => _frequency = value),
        validator: (value) =>
            value == null ? 'Choisissez une fréquence.' : null,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: const Key('profile-level'),
        initialValue: _level,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Niveau déclaré'),
        items: _levels
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: (value) => setState(() => _level = value),
        validator: (value) => value == null ? 'Choisissez un niveau.' : null,
      ),
    ],
  );

  Widget _buildGoalsStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _FieldTitle('Votre objectif principal'),
      RadioGroup<String>(
        groupValue: _primaryGoal,
        onChanged: (value) => setState(() {
          _primaryGoal = value;
          if (value != null) _secondaryGoals.remove(value);
        }),
        child: Column(
          children: _goals
              .map(
                (goal) => RadioListTile<String>(
                  key: ValueKey('primary-goal-$goal'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(goal),
                  value: goal,
                ),
              )
              .toList(),
        ),
      ),
      const SizedBox(height: 12),
      const _FieldTitle('Autres objectifs (facultatif)'),
      _MultiChoiceChips(
        options: _goals.where((goal) => goal != _primaryGoal).toList(),
        selected: _secondaryGoals,
        onChanged: (value) => setState(() => _secondaryGoals = value),
      ),
      const SizedBox(height: 18),
      TextFormField(
        key: const Key('profile-custom-goal'),
        controller: _customGoal,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Un objectif personnel ? (facultatif)',
          alignLabelWithHint: true,
        ),
      ),
    ],
  );

  Widget _buildConditionsStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _FieldTitle('Où pouvez-vous vous entraîner ?'),
      _MultiChoiceChips(
        options: _locationOptions,
        selected: _locations,
        onChanged: (value) => setState(() => _locations = value),
      ),
      const SizedBox(height: 18),
      const _FieldTitle('Matériel disponible (facultatif)'),
      _MultiChoiceChips(
        options: _equipmentOptions,
        selected: _equipment,
        onChanged: (value) => setState(() => _equipment = value),
      ),
      const SizedBox(height: 18),
      const _FieldTitle('Jours disponibles (facultatif)'),
      _MultiChoiceChips(
        options: _dayOptions,
        selected: _days,
        onChanged: (value) => setState(() => _days = value),
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<int>(
        key: const Key('profile-duration'),
        initialValue: _duration,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Durée approximative par séance (facultatif)',
        ),
        items: const [30, 45, 60, 75, 90]
            .map(
              (value) =>
                  DropdownMenuItem(value: value, child: Text('$value minutes')),
            )
            .toList(),
        onChanged: (value) => setState(() => _duration = value),
      ),
      const SizedBox(height: 18),
      TextFormField(
        key: const Key('profile-limitations'),
        controller: _limitations,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Contraintes ou limitations (facultatif)',
          helperText: 'Ne partagez que ce que vous souhaitez déclarer.',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 18),
      const _FieldTitle('Mesures facultatives'),
      Text(
        'La taille et le poids sont facultatifs et servent uniquement à '
        'personnaliser de futures informations. Ils ne sont pas nécessaires '
        'pour créer votre profil.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              key: const Key('profile-height'),
              controller: _height,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Taille',
                suffixText: 'cm',
              ),
              validator: (value) => _optionalNumberError(
                value,
                minimum: 80,
                maximum: 250,
                label: 'Taille',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              key: const Key('profile-weight'),
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Poids',
                suffixText: 'kg',
              ),
              validator: (value) => _optionalNumberError(
                value,
                minimum: 25,
                maximum: 350,
                label: 'Poids',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        key: const Key('profile-wearable'),
        initialValue: _wearable,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Montre ou source de données (facultatif)',
        ),
        items: _wearables
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: (value) => setState(() => _wearable = value),
      ),
      const SizedBox(height: 8),
      Text(
        'Aucune montre n’est connectée pour le moment ; ce choix indique '
        'simplement votre équipement.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Future<void> _updateLocalTheme(ThemePreferences value) async {
    try {
      await widget.themeController.update(value);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Le thème n’a pas pu être enregistré sur cet appareil.',
        );
      }
    }
  }
}

class _FieldTitle extends StatelessWidget {
  const _FieldTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _MultiChoiceChips extends StatelessWidget {
  const _MultiChoiceChips({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: options
        .map(
          (option) => FilterChip(
            label: Text(option),
            selected: selected.contains(option),
            onSelected: (checked) {
              final next = Set<String>.from(selected);
              checked ? next.add(option) : next.remove(option);
              onChanged(next);
            },
          ),
        )
        .toList(),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: color)),
    );
  }
}

String? _optionalNumberError(
  String? value, {
  required double minimum,
  required double maximum,
  required String label,
}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final number = double.tryParse(text.replaceAll(',', '.'));
  if (number == null || number < minimum || number > maximum) {
    return '$label : valeur comprise entre $minimum et $maximum.';
  }
  return null;
}
