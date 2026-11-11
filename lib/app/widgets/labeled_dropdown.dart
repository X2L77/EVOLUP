import 'package:flutter/material.dart';

/// A dropdown shown like the app's text fields, whose [value] is controlled
/// by the parent.
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        borderRadius: BorderRadius.circular(16),
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}
