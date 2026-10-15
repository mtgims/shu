import 'package:flutter/material.dart';

import '../player/audiobook_player.dart';
import '../player/player_settings.dart';
import '../widgets/adaptive.dart';
import 'marks.dart';

/// Speed, sleep timer and bookmark, under the player and in the wide player bar.
class PlayerExtras extends StatelessWidget {
  const PlayerExtras({super.key, required this.player});
  final AudiobookPlayer player;

  static const presets = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
  static const minSpeed = 0.5;
  static const maxSpeed = 3.0;

  /// 1.0 → "1×", 1.25 → "1.25×", 1.5 → "1.5×".
  static String speedLabel(double s) =>
      '${s.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}×';

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        StreamBuilder<double>(
          stream: player.speedStream,
          initialData: player.speed,
          builder: (context, snap) => TextButton.icon(
            onPressed: () => _pickSpeed(context),
            icon: const Icon(Icons.speed),
            label: Text(speedLabel(snap.data ?? 1)),
          ),
        ),
        ValueListenableBuilder<SleepTimer?>(
          valueListenable: player.sleepTimer,
          builder: (context, timer, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: () => _pickSleep(context),
                icon: Icon(
                  timer == null ? Icons.bedtime_outlined : Icons.bedtime,
                ),
                label: Text(
                  timer == null
                      ? 'Sleep timer'
                      : timer.endOfChapter
                      ? 'End of chapter'
                      : 'Until ${TimeOfDay.fromDateTime(timer.endsAt!).format(context)}',
                ),
              ),
              if (timer?.endsAt != null)
                IconButton(
                  tooltip: 'Add 5 minutes',
                  onPressed: player.sleepTimer.extend,
                  icon: const Icon(Icons.more_time),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Bookmark this place',
          onPressed: () => _bookmark(context),
          icon: const Icon(Icons.bookmark_add_outlined),
        ),
      ],
    );
  }

  Future<void> _bookmark(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final mark = await player.addBookmark();
    final entry = player.current.value;
    if (mark == null || entry == null || !context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Bookmarked at ${markTime(entry, mark)}'),
        action: SnackBarAction(
          label: 'Add note',
          onPressed: () => editBookmarkNote(context, player, mark),
        ),
      ),
    );
  }

  void _pickSpeed(BuildContext context) {
    // Steps of 0.05, so repeated taps never drift to 1.2499999.
    void set(double s) =>
        player.setSpeed((s.clamp(minSpeed, maxSpeed) * 20).round() / 20);
    showPanel<void>(
      context,
      builder: (context) => SafeArea(
        child: StreamBuilder<double>(
          stream: player.speedStream,
          initialData: player.speed,
          builder: (context, snap) {
            final speed = snap.data ?? 1;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Slower',
                        onPressed: speed > minSpeed
                            ? () => set(speed - 0.05)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 128,
                        child: Text(
                          speedLabel(speed),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Faster',
                        onPressed: speed < maxSpeed
                            ? () => set(speed + 0.05)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  Slider(
                    value: speed.clamp(minSpeed, maxSpeed),
                    min: minSpeed,
                    max: maxSpeed,
                    divisions: ((maxSpeed - minSpeed) * 20).round(),
                    label: speedLabel(speed),
                    onChanged: set,
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in presets)
                        ChoiceChip(
                          label: Text(speedLabel(s)),
                          selected: (s - speed).abs() < 0.01,
                          onSelected: (_) => set(s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _pickSleep(BuildContext context) {
    final settings = player.settings;
    void choose(int minutes) {
      settings.lastSleep = minutes;
      if (minutes == 0) {
        player.setSleepAtChapterEnd();
      } else {
        player.setSleepTimer(Duration(minutes: minutes));
      }
      Navigator.of(context).pop();
    }

    String label(int minutes) =>
        minutes == 0 ? 'End of chapter' : '$minutes minutes';
    final last = settings.lastSleep;
    showPanel<void>(
      context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (last != null)
              ListTile(
                leading: const Icon(Icons.replay),
                title: Text('Again: ${label(last)}'),
                onTap: () => choose(last),
              ),
            for (final minutes in [10, 15, 30, 45, 60, 0])
              if (minutes != last)
                ListTile(
                  title: Text(label(minutes)),
                  onTap: () => choose(minutes),
                ),
            if (player.sleepTimer.value != null)
              ListTile(
                title: const Text('Turn off'),
                onTap: () {
                  player.cancelSleepTimer();
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Switches for how playback sounds and behaves.
void showAudioSettings(BuildContext context, PlayerSettings settings) {
  showPanel<void>(
    context,
    builder: (context) => SafeArea(
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Step back after a pause'),
              subtitle: const Text('A few seconds, more after a long break'),
              value: settings.autoRewind,
              onChanged: (on) => settings.autoRewind = on,
            ),
            if (PlayerSettings.hasAudioEffects) ...[
              SwitchListTile(
                title: const Text('Skip silence'),
                subtitle: const Text('Shortens long pauses in the reading'),
                value: settings.skipSilence,
                onChanged: (on) => settings.skipSilence = on,
              ),
              SwitchListTile(
                title: const Text('Voice boost'),
                subtitle: const Text('Louder, for quiet recordings'),
                value: settings.voiceBoost,
                onChanged: (on) => settings.voiceBoost = on,
              ),
            ],
            SwitchListTile(
              title: const Text('Fade out at the end of the sleep timer'),
              value: settings.sleepFade,
              onChanged: (on) => settings.sleepFade = on,
            ),
            if (PlayerSettings.hasShake)
              SwitchListTile(
                title: const Text('Shake to add 5 minutes'),
                subtitle: const Text("In the sleep timer's last 2 minutes"),
                value: settings.shakeToExtend,
                onChanged: (on) => settings.shakeToExtend = on,
              ),
          ],
        ),
      ),
    ),
  );
}
