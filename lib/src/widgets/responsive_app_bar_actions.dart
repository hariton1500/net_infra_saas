import 'package:flutter/material.dart';

class ResponsiveAppBarActions extends StatelessWidget {
  const ResponsiveAppBarActions({
    super.key,
    required this.actions,
    required this.compactActions,
    this.breakpoint = 520,
  });

  final List<Widget> actions;
  final List<Widget> compactActions;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final visibleActions = width < breakpoint ? compactActions : actions;

    return Row(mainAxisSize: MainAxisSize.min, children: visibleActions);
  }
}
