import 'package:flutter/material.dart';

class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({this.color, super.key});

  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}
