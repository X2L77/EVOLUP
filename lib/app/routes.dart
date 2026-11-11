import 'package:flutter/material.dart';

/// Page opened above the sections: short fade and slide.
///
/// [emphasized] is the transition from a Polomix action to its form: the
/// page grows slightly from the conversation while fading in. Both are
/// skipped when the device asks for reduced motion, and never delay the
/// keyboard (the form focuses its field once the transition is over).
Route<T> evolupRoute<T>(WidgetBuilder builder, {bool emphasized = false}) =>
    PageRouteBuilder<T>(
      transitionDuration: Duration(milliseconds: emphasized ? 360 : 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (context, animation, _, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        if (emphasized) {
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            ),
          );
        }
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
