import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../app.dart';
import '../downloads/download_store.dart';
import '../library/library_store.dart';
import 'more_menu.dart';

/// Download, its progress with Cancel, or "downloaded" with a menu to remove it. [bookKey] is
/// null while the book isn't in the library (a catalog book not started yet).
class DownloadButton extends StatelessWidget {
  const DownloadButton({
    super.key,
    required this.bookKey,
    required this.onDownload,
  });

  final String? bookKey;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final downloads = AppScope.of(context).downloads;
    return ListenableBuilder(
      listenable: Listenable.merge([downloads, downloads.moved]),
      builder: (context, _) {
        final key = bookKey;
        final progress = key == null ? null : downloads.progressOf(key);
        if (key != null && progress != null && progress.active) {
          return Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.square(
                dimension: 40,
                child: CircularProgressIndicator(
                  value: progress.fraction,
                  strokeWidth: 3,
                ),
              ),
              IconButton(
                tooltip: switch (progress.state) {
                  DownloadState.waitingForWifi =>
                    'Waiting for Wi-Fi. Cancel download',
                  DownloadState.waiting =>
                    '${progress.message}. Cancel download',
                  _ => 'Cancel download',
                },
                icon: const Icon(Icons.close),
                onPressed: () => downloads.remove(key),
              ),
            ],
          );
        }
        if (key != null && progress?.state == DownloadState.done) {
          return MenuAnchor(
            menuChildren: [
              removeItem(
                context,
                'Remove download',
                () => downloads.remove(key),
                icon: Icons.delete_outline,
              ),
            ],
            builder: (context, menu, _) => IconButton.filledTonal(
              tooltip: 'Downloaded',
              icon: const Icon(Icons.download_done),
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            ),
          );
        }
        final failed = progress?.state == DownloadState.failed;
        return IconButton.filledTonal(
          tooltip: failed
              ? 'Download failed: ${progress!.message}. Try again'
              : 'Download',
          icon: Icon(failed ? Icons.error_outline : Icons.download),
          onPressed: onDownload,
        );
      },
    );
  }
}

/// One line on how [bookKey]'s download is going ("42 % · 45 of 120 MB · 2.1 MB/s"), or what it
/// waits for or why it failed; nothing when it isn't downloading.
class DownloadStatus extends StatelessWidget {
  const DownloadStatus({super.key, required this.bookKey, this.style});

  final String? bookKey;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final downloads = AppScope.of(context).downloads;
    return ListenableBuilder(
      listenable: Listenable.merge([downloads, downloads.moved]),
      builder: (context, _) {
        final key = bookKey;
        final progress = key == null ? null : downloads.progressOf(key);
        final text = switch (progress) {
          null => null,
          DownloadProgress(state: DownloadState.done) => null,
          DownloadProgress(state: DownloadState.queued) =>
            'Download waiting for the one before it',
          DownloadProgress(state: DownloadState.waitingForWifi) =>
            'Download waiting for Wi-Fi',
          DownloadProgress(state: DownloadState.failed, :final message) =>
            'Download failed: $message',
          DownloadProgress(state: DownloadState.waiting, :final message) =>
            message,
          DownloadProgress(:final fraction, :final detail) => [
            if (fraction != null) '${(fraction * 100).floor()} %',
            detail ?? 'Starting download',
          ].join(' · '),
        };
        if (text == null) return const SizedBox.shrink();
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              style ??
              Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        );
      },
    );
  }
}

/// Download, Cancel download or Remove download for a book in the library, as a menu item;
/// null for books already on this device.
Widget? downloadItem(
  BuildContext context,
  InstalledAddon? addon,
  LibraryEntry entry,
) {
  final downloads = AppScope.of(context).downloads;
  final progress = downloads.progressOf(entry.key);
  if (progress != null && progress.state != DownloadState.failed) {
    return removeItem(
      context,
      progress.active ? 'Cancel download' : 'Remove download',
      () => downloads.remove(entry.key),
      icon: progress.active ? Icons.close : Icons.delete_outline,
    );
  }
  if (addon == null || addon.isLocal) return null;
  return MenuItemButton(
    leadingIcon: const Icon(Icons.download),
    onPressed: () => downloads.add(addon, entry.book),
    child: const Text('Download'),
  );
}
