import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Numeric answer (age, height, weight). Accepts a comma or a dot as decimal
/// separator when [decimal] is true.
class NumberAnswer extends StatefulWidget {
  const NumberAnswer({
    required this.value,
    required this.unit,
    required this.label,
    required this.onChanged,
    required this.onSubmitted,
    this.decimal = false,
    super.key,
  });

  final num? value;
  final String unit;
  final String label;
  final bool decimal;
  final ValueChanged<num?> onChanged;
  final VoidCallback onSubmitted;

  @override
  State<NumberAnswer> createState() => _NumberAnswerState();
}

class _NumberAnswerState extends State<NumberAnswer> {
  late final _controller = TextEditingController(text: _format(widget.value));
  late final _allowed = widget.decimal
      ? RegExp(r'^\d{0,3}([.,]\d?)?$')
      : RegExp(r'^\d{0,3}$');

  static String _format(num? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString().replaceAll('.', ',');
  }

  num? _parse(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return widget.decimal
        ? double.tryParse(normalized)
        : int.tryParse(normalized);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('answer-number'),
    controller: _controller,
    autofocus: true,
    keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
    textInputAction: TextInputAction.done,
    inputFormatters: [
      // Rejects the keystroke (keeps the previous text) when invalid.
      TextInputFormatter.withFunction(
        (previous, next) => _allowed.hasMatch(next.text) ? next : previous,
      ),
    ],
    style: Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    decoration: InputDecoration(
      labelText: widget.label,
      suffixText: widget.unit,
    ),
    onChanged: (text) => widget.onChanged(_parse(text)),
    onSubmitted: (_) => widget.onSubmitted(),
  );
}
