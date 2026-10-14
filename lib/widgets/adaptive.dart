import 'dart:math';

import 'package:flutter/material.dart';

/// Windows at least this wide get the desktop layout: side rail, player bar, dialogs instead of
/// bottom sheets, arrows on card rows.
const wideLayout = 760.0;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideLayout;

/// Extra side space that keeps a list at a readable width in a wide window, while its scroll
/// bar stays at the window's edge.
double readableInset(BuildContext context, {double maxWidth = 960}) =>
    max(0, (MediaQuery.sizeOf(context).width - maxWidth) / 2);

/// A short list of choices: a bottom sheet on phones, a small dialog in wide windows (a sheet
/// sliding up from the bottom of a desktop window is far from the mouse and looks lost).
Future<T?> showPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = false,
}) {
  if (!isWide(context)) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: scrollControlled,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        // Rows light up as rounded shapes inside the dialog's rounded corners, not as squares
        // running into them.
        child: ListTileTheme(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: builder(context),
          ),
        ),
      ),
    ),
  );
}
