import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../addons/models.dart';
import '../app.dart';
import '../widgets/adaptive.dart';

/// The settings form an extension declares in its manifest. Changes save on their own.
class ExtensionSettingsScreen extends StatefulWidget {
  const ExtensionSettingsScreen({super.key, required this.addon});

  final InstalledAddon addon;

  static Route<void> route(InstalledAddon addon) =>
      MaterialPageRoute(builder: (_) => ExtensionSettingsScreen(addon: addon));

  @override
  State<ExtensionSettingsScreen> createState() =>
      _ExtensionSettingsScreenState();
}

class _ExtensionSettingsScreenState extends State<ExtensionSettingsScreen> {
  late Map<String, Object?> _values;
  final _hidden = <String>{};
  Timer? _saveTimer;
  bool _loaded = false;

  // Kept from the start: the last save runs in dispose(), when context can no longer be used.
  late AddonStore _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _store = AppScope.of(context).addons;
    _values = Map.of(_store.settingsOf(widget.addon.manifest));
    _hidden.addAll(
      widget.addon.manifest.settings
          .where((f) => f.type == 'password')
          .map((f) => f.key),
    );
  }

  void _set(String key, Object? value, {bool debounce = false}) {
    setState(() => _values[key] = value);
    _saveTimer?.cancel();
    if (debounce) {
      _saveTimer = Timer(const Duration(milliseconds: 500), _save);
    } else {
      _save();
    }
  }

  void _save() => _store.saveSettings(widget.addon, _values);

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _save();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.addon.manifest.settings;
    // A form, so narrower than the lists: fields this wide are hard to read across.
    final side = 16 + readableInset(context, maxWidth: 720);
    return Scaffold(
      appBar: AppBar(title: Text(widget.addon.manifest.name)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(side, 8, side, 32),
        children: [
          Text(
            'Saved on this device only.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (widget.addon.manifest.notice case final notice?)
            Card.filled(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded),
                    const SizedBox(width: 12),
                    Expanded(child: Text(notice)),
                  ],
                ),
              ),
            ),
          for (final f in fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _field(f),
            ),
        ],
      ),
    );
  }

  /// Asks for a folder and keeps it only when the app can write there.
  Future<void> _pickFolder(SettingField f) async {
    final messenger = ScaffoldMessenger.of(context);
    final folder = await FilePicker.getDirectoryPath(dialogTitle: f.label);
    if (folder == null) return;
    try {
      final probe = File('$folder/.shu-write-test');
      await probe.writeAsString('');
      await probe.delete();
    } on FileSystemException {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Shu can\'t save files there. Choose another folder.'),
        ),
      );
      return;
    }
    _set(f.key, folder);
  }

  Widget _field(SettingField f) {
    final theme = Theme.of(context);
    final value = _values[f.key];
    final help = f.help == null
        ? null
        : Text(f.help!, style: theme.textTheme.bodySmall);
    switch (f.type) {
      case 'toggle':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          subtitle: help,
          value: value == true,
          onChanged: (v) => _set(f.key, v),
        );
      case 'select':
        return DropdownMenu<String>(
          expandedInsets: EdgeInsets.zero,
          label: Text(f.label),
          helperText: f.help,
          initialSelection: value?.toString(),
          onSelected: (v) => _set(f.key, v),
          dropdownMenuEntries: [
            for (final o in f.options)
              DropdownMenuEntry(value: o.value, label: o.label),
          ],
        );
      case 'folder':
        final path = value is String && value.isNotEmpty ? value : null;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(path ?? 'Default (inside the app)'), ?help],
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              if (path != null)
                TextButton(
                  onPressed: () => _set(f.key, ''),
                  child: const Text('Reset'),
                ),
              FilledButton.tonal(
                onPressed: () => _pickFolder(f),
                child: const Text('Choose'),
              ),
            ],
          ),
        );
      case 'multiselect':
        final selected = value is List
            ? value.map((v) => '$v').toSet()
            : <String>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label, style: theme.textTheme.titleSmall),
            ?help,
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in f.options)
                  FilterChip(
                    label: Text(o.label),
                    selected: selected.contains(o.value),
                    onSelected: (on) => _set(f.key, [
                      for (final opt in f.options)
                        if (opt.value == o.value
                            ? on
                            : selected.contains(opt.value))
                          opt.value,
                    ]),
                  ),
              ],
            ),
          ],
        );
      default: // text, password, number
        final number = f.type == 'number';
        final hidden = _hidden.contains(f.key);
        return TextFormField(
          initialValue: value?.toString() ?? '',
          obscureText: hidden,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            labelText: f.label,
            helperText: f.help,
            helperMaxLines: 3,
            suffixIcon: f.type == 'password'
                ? IconButton(
                    tooltip: hidden ? 'Show' : 'Hide',
                    icon: Icon(
                      hidden ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(
                      () => hidden ? _hidden.remove(f.key) : _hidden.add(f.key),
                    ),
                  )
                : null,
          ),
          // A half-typed number ("-") is marked and not saved: the last good one stays.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (text) =>
              number &&
                  text!.trim().isNotEmpty &&
                  num.tryParse(text.trim()) == null
              ? 'Not a number'
              : null,
          onChanged: (text) {
            final v = number ? num.tryParse(text.trim()) : text.trim();
            if (number && v == null && text.trim().isNotEmpty) return;
            _set(f.key, v, debounce: true);
          },
        );
    }
  }
}
