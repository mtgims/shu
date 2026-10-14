import 'package:flutter/material.dart';

/// The ⋮ button and its menu, styled by the theme's menu styles like every menu in the app.
class MoreMenu extends StatelessWidget {
  const MoreMenu({super.key, required this.items});

  /// [MenuItemButton]s.
  final List<Widget> items;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: items,
    builder: (context, menu, _) => IconButton(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert),
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );
}

/// A menu item that removes something, in the error color.
Widget removeItem(BuildContext context, String label, VoidCallback onPressed) =>
    MenuItemButton(
      style: MenuItemButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
