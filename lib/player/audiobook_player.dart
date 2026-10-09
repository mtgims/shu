import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../addons/addon_store.dart';
import '../addons/client.dart';
import '../addons/models.dart';
import '../library/library_store.dart';

enum PlayerPhase { idle, loading, downloading, ready, error }

class PlayerStatus {
  const PlayerStatus(this.phase, {this.message, this.progress});

  static const idle = PlayerStatus(PlayerPhase.idle);

  final PlayerPhase phase;
  final String? message;

  /// Download progress (0 to 1) while the source is still fetching the book.
  final double? progress;
}

/// When the sleep timer stops playback: at a time, or when the chapter ends.
class SleepTimer {
  const SleepTimer.at(DateTime this.endsAt) : endOfChapter = false;
  const SleepTimer.endOfChapter() : endsAt = null, endOfChapter = true;

  final DateTime? endsAt;
  final bool endOfChapter;
}

/// The open book. [changed] tells listeners that something inside it moved, like the chapter.
class CurrentEntry extends ValueNotifier<LibraryEntry?> {
  CurrentEntry() : super(null);

  void changed() => notifyListeners();
}

/// Plays one book at a time, chapter by chapter. It is also the audio_service handler, so the
/// lock screen, notification and media keys drive the same object as the app's UI.
class AudiobookPlayer extends BaseAudioHandler with SeekHandler {
  AudiobookPlayer(this._library, this._addons, this._prefs) {
    _player.playbackEventStream.listen(_broadcast, onError: _onPlaybackError);
    _player.playingStream.listen((playing) {
      _broadcast(_player.playbackEvent);
      // Progress is saved while playing only: an idle app wakes up for nothing.
      _saveTimer?.cancel();
      _saveTimer = playing
          ? Timer.periodic(
              const Duration(seconds: 15),
              (_) => _saveProgress(notify: false),
            )
          : null;
      _chapterTimer?.cancel();
      _chapterTimer = playing && _inFileChapters
          ? Timer.periodic(const Duration(seconds: 1), (_) => _syncChapter())
          : null;
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onChapterEnd();
    });
    _player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (item != null && duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
    _player.setSpeed(_prefs.getDouble(_speedKey) ?? 1.0);
  }

  static const skipBack = Duration(seconds: 15);
  static const skipForward = Duration(seconds: 30);
  static const _speedKey = 'speed';
  static const _linkLifetime = Duration(hours: 3);
  static const _retryEvery = Duration(seconds: 30);
  static const _openTimeout = Duration(seconds: 30);

  final LibraryStore _library;
  final AddonStore _addons;
  final SharedPreferences _prefs;
  final AudioPlayer _player = AudioPlayer();

  final status = ValueNotifier<PlayerStatus>(PlayerStatus.idle);
  final current = CurrentEntry();
  final sleepTimer = ValueNotifier<SleepTimer?>(null);

  InstalledAddon? _addon;
  int _loadToken = 0;
  Timer? _retryTimer;
  Timer? _sleepTimer;
  Timer? _saveTimer;
  Timer? _chapterTimer;
  final Map<String, ({String url, DateTime until})> _links = {};

  /// The link the audio player has open, so chapters in the same file only seek.
  String? _loadedUrl;

  /// When playback last failed and was restarted on its own (a link may have expired).
  DateTime? _recoveredAt;

  /// Smooth position updates, for the seek bar.
  Stream<Duration> get positionStream => _player.positionStream;

  /// One update a second: enough for small progress bars, and far fewer rebuilds.
  late final Stream<Duration> slowPositionStream = _player.createPositionStream(
    steps: 1,
    minPeriod: const Duration(seconds: 1),
    maxPeriod: const Duration(seconds: 1),
  );
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<double> get speedStream => _player.speedStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get playing => _player.playing;
  double get speed => _player.speed;

  /// Starts a book. Without a chapter it resumes where the user stopped (or from the start
  /// when the book was finished).
  Future<void> openBook(
    InstalledAddon addon,
    Book book, {
    int? chapterIndex,
    String? sourceId,
    String? workKey,
  }) async {
    await _saveProgress();
    final entry = _library.entryFor(addon.id, book, workKey: workKey);
    if (chapterIndex != null && chapterIndex != entry.chapterIndex) {
      _moveTo(entry, chapterIndex);
    } else if (chapterIndex == null && entry.finished) {
      _moveTo(entry, 0);
    }
    entry.finished = false;
    if (sourceId != null && sourceId != entry.sourceId) {
      entry.sourceId = sourceId;
      _links.clear();
    }
    _addon = addon;
    current.value = entry;
    await _library.save(entry);
    await _loadChapter(play: true);
  }

  /// Puts the most recent unfinished book back in the player, paused, as the app starts. Its
  /// link is fetched a moment later, quietly, so pressing play starts at once.
  void restoreLastSession() {
    final entry = _library.entries.where((e) => !e.finished).firstOrNull;
    final addon = entry == null ? null : _addons.byId(entry.addonId);
    if (entry == null || addon == null) return;
    _addon = addon;
    current.value = entry;
    _announce(addon, entry);
    Timer(const Duration(seconds: 3), () async {
      if (current.value?.key != entry.key ||
          status.value.phase != PlayerPhase.idle) {
        return;
      }
      try {
        await _linkFor(addon, entry, entry.chapterIndex);
      } on Object {
        // Shown when the user presses play.
      }
    });
  }

  /// Tells the system (notification, lock screen, media keys) what is loaded.
  void _announce(
    InstalledAddon addon,
    LibraryEntry entry, {
    Duration? duration,
  }) {
    final chapter = entry.book.chapters[entry.chapterIndex];
    mediaItem.add(
      MediaItem(
        id: '${addon.id}|${entry.book.id}|${chapter.id}',
        title: chapter.title,
        album: entry.book.title,
        artist: entry.book.byline.isEmpty ? null : entry.book.byline,
        duration: duration,
        artUri: entry.book.cover == null
            ? null
            : Uri.tryParse(entry.book.cover!),
      ),
    );
  }

  /// Puts [entry] at the start of chapter [index].
  static void _moveTo(LibraryEntry entry, int index) {
    entry.chapterIndex = index;
    entry.position = entry.book.chapters[index].start ?? Duration.zero;
  }

  /// Whether the open chapter shares its audio file with other chapters (an M4B).
  bool get _inFileChapters {
    final entry = current.value;
    return entry != null &&
        entry.book.chapters[entry.chapterIndex].file != null;
  }

  /// Follows the position through chapters that share one file: the chapter shown, the lock
  /// screen and the library move along with playback.
  void _syncChapter() {
    final entry = current.value;
    final addon = _addon;
    if (entry == null ||
        addon == null ||
        status.value.phase != PlayerPhase.ready) {
      return;
    }
    final chapters = entry.book.chapters;
    final here = chapters[entry.chapterIndex];
    if (here.file == null) return;
    final position = _player.position;
    Duration startOf(int i) => chapters[i].start ?? Duration.zero;
    var index = entry.chapterIndex;
    while (index + 1 < chapters.length &&
        chapters[index + 1].sharesFileWith(here) &&
        startOf(index + 1) <= position) {
      index++;
    }
    while (index > 0 &&
        chapters[index - 1].sharesFileWith(here) &&
        startOf(index) > position) {
      index--;
    }
    if (index == entry.chapterIndex) return;
    final forward = index > entry.chapterIndex;
    entry.chapterIndex = index;
    entry.position = position;
    _announce(addon, entry, duration: _player.duration);
    current.changed();
    unawaited(_library.save(entry));
    if (forward && sleepTimer.value?.endOfChapter == true) {
      cancelSleepTimer();
      unawaited(pause());
    }
  }

  /// Saves where the user is, e.g. when the app goes to the background.
  Future<void> saveNow() => _saveProgress();

  /// Opens a library entry again (e.g. "continue listening").
  Future<void> resume(LibraryEntry entry) async {
    final addon = _addons.byId(entry.addonId);
    if (addon == null) {
      status.value = const PlayerStatus(
        PlayerPhase.error,
        message: 'The addon this book came from is no longer installed.',
      );
      return;
    }
    if (current.value?.key == entry.key &&
        status.value.phase == PlayerPhase.ready) {
      return play();
    }
    await openBook(addon, entry.book);
  }

  Future<void> playChapter(int index) async {
    final entry = current.value;
    if (entry == null || index < 0 || index >= entry.book.chapters.length) {
      return;
    }
    await _saveProgress();
    _moveTo(entry, index);
    await _library.save(entry);
    current.changed();
    await _loadChapter(play: true);
  }

  /// Tries the current chapter again, e.g. after a download finished.
  Future<void> retry() => _loadChapter(play: true);

  Future<void> _loadChapter({required bool play}) async {
    final entry = current.value;
    final addon = _addon;
    if (entry == null || addon == null) return;
    final token = ++_loadToken;
    _retryTimer?.cancel();
    _announce(addon, entry);
    status.value = const PlayerStatus(PlayerPhase.loading);
    await _player.pause();

    try {
      final url = await _linkFor(addon, entry, entry.chapterIndex);
      if (token != _loadToken) return;
      if (url == null) {
        _retryTimer = Timer(_retryEvery, () => _loadChapter(play: play));
        return;
      }
      if (url == _loadedUrl &&
          _player.processingState != ProcessingState.idle) {
        // Another chapter of the file that is open already.
        await _player.seek(entry.position);
        _announce(addon, entry, duration: _player.duration);
      } else {
        _loadedUrl = null;
        // A stalled server or audio device must not leave the player loading forever.
        await _player
            .setUrl(url, initialPosition: entry.position)
            .timeout(
              _openTimeout,
              onTimeout: () => throw AddonException(
                'The audio did not start within ${_openTimeout.inSeconds} seconds.',
              ),
            );
        _loadedUrl = url;
      }
      if (token != _loadToken) return;
      status.value = const PlayerStatus(PlayerPhase.ready);
      if (play) unawaited(_player.play());
      unawaited(_prefetch(addon, entry, _nextFile(entry)));
    } on Object catch (e) {
      if (token != _loadToken) return;
      status.value = PlayerStatus(PlayerPhase.error, message: _describe(e));
    }
  }

  /// The playable link of a chapter, or null while the source is still downloading the book.
  Future<String?> _linkFor(
    InstalledAddon addon,
    LibraryEntry entry,
    int index,
  ) async {
    final chapter = entry.book.chapters[index];
    final key = _linkKey(addon, entry, index);
    final cached = _links[key];
    if (cached != null && DateTime.now().isBefore(cached.until)) {
      return cached.url;
    }

    final list = await addon.client.sources(entry.book.id, chapter.id);
    if (list.sources.isEmpty) {
      throw AddonException(
        list.message ?? 'The addon has no source for this chapter.',
      );
    }
    final source = _pickSource(list.sources, entry.sourceId);
    if (entry.sourceId != source.id) {
      entry.sourceId = source.id;
      unawaited(_library.save(entry, notify: false));
    }

    switch (await addon.client.resolve(source)) {
      case Playable(:final url, :final validFor):
        final lifetime = validFor != null && validFor < _linkLifetime
            ? validFor
            : _linkLifetime;
        _links[key] = (url: url, until: DateTime.now().add(lifetime));
        return url;
      case Downloading(:final message, :final progress):
        if (current.value?.key == entry.key && index == entry.chapterIndex) {
          status.value = PlayerStatus(
            PlayerPhase.downloading,
            message:
                '$message\nTrying again every ${_retryEvery.inSeconds} seconds.',
            progress: progress,
          );
        }
        return null;
    }
  }

  /// Chapters in one file share their link.
  static String _linkKey(InstalledAddon addon, LibraryEntry entry, int index) {
    final chapter = entry.book.chapters[index];
    return '${addon.id}|${entry.book.id}|${chapter.file ?? chapter.id}';
  }

  static Source _pickSource(List<Source> sources, String? preferred) {
    for (final s in sources) {
      if (s.id == preferred) return s;
    }
    for (final s in sources) {
      if (s.cached == true) return s;
    }
    return sources.first;
  }

  /// Resolves the next chapter ahead of time so the switch is quick.
  Future<void> _prefetch(
    InstalledAddon addon,
    LibraryEntry entry,
    int index,
  ) async {
    if (index >= entry.book.chapters.length) return;
    try {
      await _linkFor(addon, entry, index);
    } on Object {
      // It is tried again, with errors shown, when the chapter starts.
    }
  }

  /// The first chapter after the open one that plays from another file.
  static int _nextFile(LibraryEntry entry) {
    final chapters = entry.book.chapters;
    final here = chapters[entry.chapterIndex];
    var i = entry.chapterIndex + 1;
    while (i < chapters.length && chapters[i].sharesFileWith(here)) {
      i++;
    }
    return i;
  }

  /// The open file ended.
  void _onChapterEnd() {
    final entry = current.value;
    if (entry == null) return;
    final next = _nextFile(entry);
    if (sleepTimer.value?.endOfChapter == true) {
      cancelSleepTimer();
      unawaited(_player.pause());
      if (next < entry.book.chapters.length) {
        _moveTo(entry, next);
        current.changed();
        unawaited(_library.save(entry).then((_) => _loadChapter(play: false)));
      }
      return;
    }
    if (next < entry.book.chapters.length) {
      unawaited(playChapter(next));
    } else {
      entry.finished = true;
      entry.position = Duration.zero;
      unawaited(_player.pause());
      unawaited(_library.save(entry));
      status.value = const PlayerStatus(PlayerPhase.idle, message: 'Finished');
    }
  }

  Future<void> _saveProgress({bool notify = true}) async {
    final entry = current.value;
    if (entry == null || status.value.phase != PlayerPhase.ready) return;
    entry.position = _player.position;
    await _library.save(entry, notify: notify);
  }

  void _onPlaybackError(Object error, StackTrace stack) {
    final entry = current.value;
    final last = _recoveredAt;
    // Links can expire while a long file plays (server logins last an hour). Once in a while,
    // get a fresh link and carry on where playback stopped instead of showing an error.
    if (entry != null &&
        status.value.phase == PlayerPhase.ready &&
        (last == null || DateTime.now().difference(last).inMinutes >= 5)) {
      _recoveredAt = DateTime.now();
      final addon = _addon;
      if (addon != null) {
        _links.remove(_linkKey(addon, entry, entry.chapterIndex));
      }
      entry.position = _player.position;
      _loadedUrl = null;
      unawaited(_loadChapter(play: _player.playing));
      return;
    }
    status.value = PlayerStatus(
      PlayerPhase.error,
      message: 'Playback failed: ${_describe(error)}',
    );
  }

  static String _describe(Object e) => switch (e) {
    AddonException(:final message) => message,
    PlayerException(:final message) =>
      message ?? 'The audio could not be played.',
    _ => e.toString(),
  };

  void _broadcast(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
  }

  // Controls, shared by the UI and the system media controls.

  @override
  Future<void> play() async {
    if (status.value.phase == PlayerPhase.ready) {
      unawaited(_player.play());
    } else if (current.value != null) {
      await _loadChapter(play: true);
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    await _saveProgress();
  }

  Future<void> togglePlay() => _player.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _syncChapter();
  }

  @override
  Future<void> fastForward() => _seekBy(skipForward);

  @override
  Future<void> rewind() => _seekBy(-skipBack);

  Future<void> _seekBy(Duration offset) async {
    final end = _player.duration;
    var target = _player.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (end != null && target > end) target = end;
    await seek(target);
  }

  @override
  Future<void> skipToNext() async {
    final entry = current.value;
    if (entry != null) await playChapter(entry.chapterIndex + 1);
  }

  /// Back to the start of the chapter, or to the previous chapter when already near the start.
  @override
  Future<void> skipToPrevious() async {
    final entry = current.value;
    if (entry == null) return;
    final start =
        entry.book.chapters[entry.chapterIndex].start ?? Duration.zero;
    if (_player.position - start > const Duration(seconds: 5) ||
        entry.chapterIndex == 0) {
      await _player.seek(start);
    } else {
      await playChapter(entry.chapterIndex - 1);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    await _prefs.setDouble(_speedKey, speed);
  }

  /// Stops playback and closes the book (progress is kept).
  @override
  Future<void> stop() async {
    await _saveProgress();
    _loadToken++;
    _retryTimer?.cancel();
    cancelSleepTimer();
    await _player.stop();
    _loadedUrl = null;
    current.value = null;
    mediaItem.add(null);
    status.value = PlayerStatus.idle;
    await super.stop();
  }

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    sleepTimer.value = SleepTimer.at(DateTime.now().add(duration));
    _sleepTimer = Timer(duration, () {
      sleepTimer.value = null;
      unawaited(pause());
    });
  }

  void setSleepAtChapterEnd() {
    _sleepTimer?.cancel();
    sleepTimer.value = const SleepTimer.endOfChapter();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    sleepTimer.value = null;
  }

  Future<void> dispose() async {
    _saveTimer?.cancel();
    _chapterTimer?.cancel();
    await _saveProgress();
    await _player.dispose();
  }
}
