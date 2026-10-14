import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../version.dart';

/// One line of a changelog section: a heading ("New") or an entry.
typedef ChangelogLine = ({bool heading, String text});

/// The newest section of a changelog in the repository's format: its title ("0.4.2 -
/// 2026-10-14") and its lines, entries that wrap onto indented lines joined back into one.
({String title, List<ChangelogLine> lines})? latestRelease(String changelog) {
  final sections = changelog.split(RegExp(r'^## ', multiLine: true));
  if (sections.length < 2) return null;
  final raw = sections[1].trimRight().split('\n');
  final lines = <ChangelogLine>[];
  for (final line in raw.skip(1)) {
    if (line.startsWith('### ')) {
      lines.add((heading: true, text: line.substring(4).trim()));
    } else if (line.startsWith('- ')) {
      lines.add((heading: false, text: line.substring(2).trim()));
    } else if (line.startsWith('  ') &&
        lines.isNotEmpty &&
        !lines.last.heading) {
      final last = lines.removeLast();
      lines.add((heading: false, text: '${last.text} ${line.trim()}'));
    }
  }
  return (title: raw.first.trim(), lines: lines);
}

/// Shu's version, what's new in it (CHANGELOG.md, bundled with the app, so it matches the
/// installed version and needs no network) and the licenses of everything inside.
Future<void> showAbout(BuildContext context) async {
  final release = latestRelease(await rootBundle.loadString('CHANGELOG.md'));
  if (!context.mounted) return;
  final theme = Theme.of(context);
  showAboutDialog(
    context: context,
    applicationName: 'Shu',
    applicationVersion: 'Version $appVersion',
    applicationIcon: Icon(
      Icons.headphones,
      size: 40,
      color: theme.colorScheme.primary,
    ),
    children: [
      if (release != null)
        // A readable width: long entries would otherwise stretch the dialog across the window.
        SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                "What's new in ${release.title}",
                style: theme.textTheme.titleMedium,
              ),
              for (final line in release.lines)
                line.heading
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text(
                          line.text,
                          style: theme.textTheme.titleSmall,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  '),
                            Expanded(child: Text(line.text)),
                          ],
                        ),
                      ),
            ],
          ),
        ),
    ],
  );
}
