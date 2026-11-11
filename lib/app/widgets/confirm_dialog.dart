import 'package:flutter/material.dart';

import '../../theme/evolup_theme.dart';

/// Asks before an action; `true` only when the user confirms.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = EvolupColors.of(context);
      return AlertDialog(
        key: const Key('confirm-dialog'),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('confirm-accept'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: destructive ? colors.error : null,
              foregroundColor: destructive ? colors.background : null,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
