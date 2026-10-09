import 'package:flutter/material.dart';

import '../app.dart';
import '../sources/server.dart';

/// Signs in to an Audiobookshelf or Jellyfin server and adds it. [server] fills the form to
/// sign in to a known server again.
Future<void> connectServer(
  BuildContext context,
  ServerKind kind, {
  ServerBackend? server,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ConnectDialog(kind: kind, server: server),
);

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({required this.kind, this.server});

  final ServerKind kind;
  final ServerBackend? server;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  late final _address = TextEditingController(
    text: widget.server?.base.toString(),
  );
  late final _user = TextEditingController(text: widget.server?.user);
  final _password = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_address.text.trim().isEmpty || _user.text.trim().isEmpty) {
      setState(() => _error = 'Fill in the address and your user name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = AppScope.of(context).addons;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final server = await ServerBackend.signIn(
        widget.kind,
        _address.text,
        _user.text.trim(),
        _password.text,
      );
      final addon = await store.addServer(server);
      navigator.pop();
      final libraries = addon.manifest.catalogs.where((c) => !c.search).length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            libraries == 0
                ? 'Signed in, but there are no audiobook libraries on this server.'
                : 'Signed in to ${widget.kind.label}',
          ),
        ),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return AlertDialog(
      title: Text(kind.label),
      content: SizedBox(
        width: 420,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _address,
                autofocus: widget.server == null,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Server address',
                  hintText: '192.168.1.10:${kind.defaultPort}',
                  helperText:
                      'As you open it in a browser, with https:// if it has it',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _user,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'User name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                autofocus: widget.server != null,
                obscureText: _hidden,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _busy ? null : _signIn(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  errorText: _error,
                  errorMaxLines: 4,
                  suffixIcon: IconButton(
                    tooltip: _hidden ? 'Show' : 'Hide',
                    icon: Icon(
                      _hidden ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign in'),
        ),
      ],
    );
  }
}
