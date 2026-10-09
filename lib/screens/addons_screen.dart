import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../addons/addon_store.dart';
import '../app.dart';
import '../sources/server.dart';
import '../widgets/cover_image.dart';
import 'connect_server.dart';
import 'extension_settings_screen.dart';

class AddonsScreen extends StatelessWidget {
  const AddonsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).addons;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Addons')),
      // Tabs stay alive side by side, so their buttons must not share a hero tag.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => showAddSource(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final addons = store.addons.where((a) => !a.isLocal).toList();
          if (addons.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nothing added yet. Tap Add to sign in to your Audiobookshelf or Jellyfin server, '
                  'or to paste the link to an extension.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [for (final addon in addons) _AddonCard(addon: addon)],
          );
        },
      ),
    );
  }
}

class _AddonCard extends StatelessWidget {
  const _AddonCard({required this.addon});
  final InstalledAddon addon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = addon.manifest;
    final server = addon.server;
    final catalogs = m.catalogs
        .map((c) => c.search ? '${c.name} (search)' : c.name)
        .join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: m.logo == null
                      ? Icon(
                          server != null ? Icons.dns_outlined : Icons.extension,
                          size: 40,
                        )
                      : Image(
                          image: ResizeImage(CoverImage(m.logo!), width: 120),
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.extension, size: 40),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: theme.textTheme.titleMedium),
                      Text(
                        server != null
                            ? 'Server · ${server.base.host}'
                            : addon.isExtension
                            ? 'v${m.version} · runs on this device'
                            : 'v${m.version} · ${Uri.tryParse(addon.base ?? '')?.host ?? ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (m.description != null) ...[
              const SizedBox(height: 10),
              Text(m.description!),
            ],
            if (catalogs.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Catalogs: $catalogs',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (server != null)
                  TextButton.icon(
                    onPressed: () =>
                        connectServer(context, server.kind, server: server),
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in again'),
                  )
                else if (addon.isExtension && m.settings.isNotEmpty)
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context)
                            .push(ExtensionSettingsScreen.route(addon)),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Settings'),
                  )
                else if (m.configureUrl != null)
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(m.configureUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Settings'),
                  ),
                TextButton.icon(
                  onPressed: () => _confirmRemove(context),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final store = AppScope.of(context).addons;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${addon.manifest.name}?'),
        content: const Text(
          'Its catalogs disappear. Books in your library stay, but can’t be played until you '
          'add it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await store.remove(addon);
  }
}

/// What can be added: a server to sign in to, or an extension by its link.
Future<void> showAddSource(BuildContext context) async {
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final kind in ServerKind.values)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text('${kind.label} server'),
              subtitle: Text(
                'Sign in to play the books on your ${kind.label} server',
              ),
              onTap: () => Navigator.pop(context, kind),
            ),
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('Extension or repository'),
            subtitle: const Text('Paste a link to install one'),
            onTap: () => Navigator.pop(context, 'extension'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case ServerKind kind:
      await connectServer(context, kind);
    case 'extension':
      await showDialog<void>(
        context: context,
        builder: (_) => const _AddDialog(),
      );
  }
}

class _AddDialog extends StatefulWidget {
  const _AddDialog();

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Most people just copied the URL from an addon's settings page.
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      final text = data?.text?.trim() ?? '';
      if (mounted &&
          _controller.text.isEmpty &&
          RegExp(r'^https?://\S+$').hasMatch(text)) {
        _controller.text = text;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The repository the pasted URL turned out to be, once loaded.
  Repository? _repo;

  Future<void> _run(
    Future<InstallResult> Function(AddonStore store) action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = AppScope.of(context).addons;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      switch (await action(store)) {
        case Repository() && final repo:
          setState(() => _repo = repo);
        case Installed(:final addon):
          navigator.pop();
          messenger.showSnackBar(
            SnackBar(content: Text('Installed ${addon.manifest.name}')),
          );
          // Extensions usually need an API key before they can play anything.
          if (addon.isExtension && addon.manifest.settings.isNotEmpty) {
            await navigator.push(ExtensionSettingsScreen.route(addon));
          }
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _install() => _run((store) => store.install(_controller.text));

  Widget _repoList(Repository repo) {
    final installed = AppScope.of(context).addons;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (repo.entries.isEmpty) const Text('This repository is empty.'),
        for (final e in repo.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.name),
            subtitle: Text([?e.version, ?e.description].join(' · ')),
            trailing: FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _run((store) => store.install(e.url)),
              child: Text(
                installed.addons.any((a) => a.updateUrl == e.url)
                    ? 'Reinstall'
                    : 'Install',
              ),
            ),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    if (repo != null) {
      return AlertDialog(
        title: Text(repo.name),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: _repoList(repo)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Add an extension'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _busy ? null : _install(),
          decoration: InputDecoration(
            labelText: 'Extension, repository or addon URL',
            hintText: 'https://…',
            helperText:
                'Extensions run on this device; addons run on a server.',
            helperMaxLines: 2,
            errorText: _error,
            errorMaxLines: 4,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _install,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Install'),
        ),
      ],
    );
  }
}
