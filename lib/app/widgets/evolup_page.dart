import 'package:flutter/material.dart';

import 'evolup_background.dart';

/// Frame of a signed-in EVOLUP page: the background, a transparent
/// [Scaffold] over it and the app bar (style from the theme).
///
/// The body decides its own layout: [PageBody] for the scrolling pages,
/// which also keeps the content clear of the floating navigation bar (the
/// shell's Scaffold reports its height as bottom padding), so no page needs
/// a fixed spacer for it.
class EvolupPage extends StatelessWidget {
  const EvolupPage({
    required this.body,
    this.title,
    this.leading,
    this.actions,
    super.key,
  });

  final Widget body;
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => EvolupBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: title, leading: leading, actions: actions),
      body: body,
    ),
  );
}
