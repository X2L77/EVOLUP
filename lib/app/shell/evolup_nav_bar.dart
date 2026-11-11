import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/evolup_theme.dart';
import '../widgets/glass_card.dart';

/// One destination of [EvolupNavBar].
@immutable
class EvolupNavItem {
  const EvolupNavItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final Key key;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Floating translucent navigation bar, made of the same glass as the
/// sign-in card and detached from the screen edges and system bars.
///
/// Items share the width equally; long labels shrink to fit narrow
/// screens. The bar is hidden while the keyboard is open.
class EvolupNavBar extends StatelessWidget {
  const EvolupNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<EvolupNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _radius = 28.0;
  static const _maxWidth = 520.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.viewInsets.bottom > 0) return const SizedBox.shrink();
    final colors = EvolupColors.of(context);
    final side = media.size.width < 360 ? 8.0 : 14.0;
    final bottom = math.max(16.0, media.viewPadding.bottom + 8);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: EdgeInsets.fromLTRB(side, 0, side, bottom),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: GlassCard(
                radius: _radius,
                padding: const EdgeInsets.all(5),
                tint: colors.navBarTint,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _NavButton(
                          item: items[i],
                          selected: i == selectedIndex,
                          onTap: () => onSelected(i),
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
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final EvolupNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final color = selected ? colors.textPrimary : colors.textSecondary;
    final shape = BorderRadius.circular(22);
    return MergeSemantics(
      key: item.key,
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: shape,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? colors.navSelected
                    : colors.navSelected.withValues(alpha: 0),
                borderRadius: shape,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 23,
                    color: color,
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
