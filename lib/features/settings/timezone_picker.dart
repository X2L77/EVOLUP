import 'package:flutter/material.dart';

import '../../app/widgets/state_views.dart';
import '../../data/data_error.dart';
import '../data/metric_search.dart';

/// Lets the user choose an IANA time zone among those known to the server.
/// Returns the chosen zone, or `null` when cancelled.
Future<String?> showTimezonePicker(
  BuildContext context, {
  required String current,
  required String? deviceZone,
  required Future<List<String>> Function() load,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (context) =>
      _TimezonePicker(current: current, deviceZone: deviceZone, load: load),
);

class _TimezonePicker extends StatefulWidget {
  const _TimezonePicker({
    required this.current,
    required this.deviceZone,
    required this.load,
  });

  final String current;
  final String? deviceZone;
  final Future<List<String>> Function() load;

  @override
  State<_TimezonePicker> createState() => _TimezonePickerState();
}

class _TimezonePickerState extends State<_TimezonePicker> {
  late final Future<List<String>> _zones = widget.load();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.deviceZone;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Fuseau horaire',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (device != null && device != widget.current)
                ListTile(
                  key: const Key('timezone-device'),
                  leading: const Icon(Icons.smartphone_rounded),
                  title: Text('Utiliser celui de l’appareil : $device'),
                  onTap: () => Navigator.of(context).pop(device),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  key: const Key('timezone-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Rechercher (ex. Paris, Montreal)',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<String>>(
                  future: _zones,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(dataErrorMessage(snapshot.error!)),
                      );
                    }
                    final zones = snapshot.data;
                    if (zones == null) return const LoadingView();
                    final query = normalizeSearch(_search.text);
                    final shown = [
                      for (final zone in zones)
                        if (normalizeSearch(
                          zone.replaceAll('_', ' '),
                        ).contains(query))
                          zone,
                    ];
                    return ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(shown[index].replaceAll('_', ' ')),
                        trailing: shown[index] == widget.current
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.of(context).pop(shown[index]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
