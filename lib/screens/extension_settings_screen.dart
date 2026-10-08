import 'dart:async';

import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../addons/models.dart';
import '../app.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _values = Map.of(
      AppScope.of(context).addons.settingsOf(widget.addon.manifest),
    );
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

  void _save() =>
      AppScope.of(context).addons.saveSettings(widget.addon, _values);

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
    return Scaffold(
      appBar: AppBar(title: Text(widget.addon.manifest.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Saved on this device only.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final f in fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _field(f),
            ),
        ],
      ),
    );
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
          onChanged: (text) {
            final v = number ? num.tryParse(text.trim()) : text.trim();
            _set(f.key, v, debounce: true);
          },
        );
    }
  }
}
