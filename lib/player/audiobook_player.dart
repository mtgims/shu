import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../addons/addon_store.dart';
import '../addons/client.dart';
import '../addons/models.dart';
import '../library/library_store.dart';
import 'player_settings.dart';
import 'position_ticks.dart';
import 'server_sync.dart';
import 'sleep.dart';

export 'sleep.dart' show SleepTimer;

enum PlayerPhase { idle, loading, downloading, ready, error }

class PlayerStatus {
  const PlayerStatus(this.phase, {this.message, this.progress});

  static const idle = PlayerStatus(PlayerPhase.idle);

  final PlayerPhase phase;
  final String? message;

  /// Download progress (0 to 1) while the source is still fetching the book.
  final double? progress;
}

/// Another version of the same catalog book, with its book when already loaded.
typedef Alternative = ({InstalledAddon addon, String bookId, Book? book});

/// The open book. [changed] tells listeners that something inside it moved, like the chapter.
class CurrentEntry extends ValueNotifier<LibraryEntry?> {
  CurrentEntry() : super(null);

  void changed() => notifyListeners();
}

/// Plays one book at a time, chapter by chapter. It is also the audio_service handler, so the
/// lock screen, notification and media keys drive the same object as the app's UI.
class AudiobookPlayer extends BaseAudioHandler with SeekHandler {
  AudiobookPlayer(this._library, this._addons, this.settings) {
    _player.playbackEventStream.listen((event) {
      _broadcast(event);
      _changes.add(null);
    }, onError: _onPlaybackError);
    // just_audio 0.10 reports playback errors here, not as errors of the event stream.
    _player.errorStream.listen((e) => _onPlaybackError(e, StackTrace.current));
    _player.playingStream.listen((playing) {
      _broadcast(_player.playbackEvent);
      _changes.add(null);
      _pausedAt = playing ? null : (_pausedAt ?? now());
      // Progress is saved while playing only: an idle app wakes up for nothing.
      _saveTimer?.cancel();
      _saveTimer = playing
          ? Timer.periodic(
              const Duration(seconds: 15),
              (_) => _saveProgress(notify: false, tick: true),
            )
          : null;
      _followChapters();
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
    _player.setSpeed(settings.speed);
    _applyEffects();
    settings.addListener(_applyEffects);
    // The notification shows "+5 min" while a timed sleep timer runs.
    sleepTimer.addListener(() => _broadcast(_player.playbackEvent));
  }

  static const skipBack = Duration(seconds: 15);
  static const skipForward = Duration(seconds: 30);
  static const _linkLifetime = Duration(hours: 3);
  static const _retryEvery = Duration(seconds: 30);
  static const _openTimeout = Duration(seconds: 30);
  static const _torrentOpenTimeout = Duration(seconds: 90);

  final LibraryStore _library;
  final AddonStore _addons;
  final PlayerSettings settings;

  /// Raises quiet recordings (Android), see [PlayerSettings.voiceBoost].
  final _boost = AndroidLoudnessEnhancer();
  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: PlayerSettings.hasAudioEffects
        ? AudioPipeline(androidAudioEffects: [_boost])
        : null,
  );

  final status = ValueNotifier<PlayerStatus>(PlayerStatus.idle);
  final current = CurrentEntry();
  late final sleepTimer = SleepControl(
    settings,
    onSleep: pause,
    onVolume: _player.setVolume,
    now: () => now(),
  );

  /// The clock, replaced in tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  final _sync = ServerSync();

  /// Told when a book jumped to where the user got to on its media server ([from]), with the
  /// place it left to go back to.
  void Function(String from, Mark before)? onServerMove;

  /// When playback stopped, for the step back on resuming ([PlayerSettings.autoRewind]).
  DateTime? _pausedAt;

  InstalledAddon? _addon;
  int _loadToken = 0;
  Timer? _retryTimer;
  Timer? _saveTimer;
  Timer? _chapterTimer;
  final Map<String, ({String url, DateTime until})> _links = {};

  /// The link the audio player has open, so chapters in the same file only seek.
  String? _loadedUrl;

  /// Completed with the error when the file being opened fails, see [_loadChapter].
  Completer<Object>? _openFailure;

  /// When playback last failed and was restarted on its own (a link may have expired).
  DateTime? _recoveredAt;

  /// Versions to fall back on while the open one hasn't played yet, see [openBook].
  List<Alternative> _alternatives = const [];
  Book? _look;
  String? _workKey;
  bool _started = false;

  /// Failed tries at loading the next chapter of a book that was playing, see [_loadChapter].
  int _retries = 0;
  static const _retryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  /// Shown while loading, e.g. that the version before didn't play; [_nextNote] carries it
  /// into the next [openBook].
  String? _loadingNote;
  String? _nextNote;

  /// Playback started, stopped, sought or moved on (for [PositionTicks]).
  final _changes = StreamController<void>.broadcast(sync: true);

  PositionTicks _ticks(Duration Function() every) => PositionTicks(
    position: () => _player.position,
    playing: () => _player.playing,
    changes: _changes.stream,
    every: every,
  );

  /// Smooth position updates, for the seek bar: 800 steps through the file, 5 to 60 a second.
  late final Stream<Duration> positionStream = _ticks(() {
    final step = (_player.duration ?? Duration.zero) ~/ 800;
    const fastest = Duration(milliseconds: 16);
    const slowest = Duration(milliseconds: 200);
    return step < fastest ? fastest : (step > slowest ? slowest : step);
  }).stream;

  /// One update a second: enough for small progress bars, and far fewer rebuilds.
  late final Stream<Duration> slowPositionStream = _ticks(
    () => const Duration(seconds: 1),
  ).stream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<double> get speedStream => _player.speedStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get playing => _player.playing;
  double get speed => _player.speed;

  /// Starts a book. Without a chapter it resumes where the user stopped (or from the start
  /// when the book was finished).
  ///
  /// For a version of a catalog book, [look] is that book and [alternatives] are other versions
  /// to try, in order, if this one fails before it ever plays.
  Future<void> openBook(
    InstalledAddon addon,
    Book book, {
    int? chapterIndex,
    String? sourceId,
    String? workKey,
    Book? look,
    List<Alternative> alternatives = const [],
  }) async {
    // Only a fallback (which sets the next note) keeps a note about the version before.
    _loadingNote = _nextNote;
    _nextNote = null;
    _alternatives = alternatives;
    _look = look;
    _workKey = workKey;
    _started = false;
    await _saveProgress();
    final before = _library.find(addon.id, book.id);
    final entry = _library.entryFor(addon.id, book, workKey: workKey);
    if (chapterIndex == null && before?.finished != true) {
      if (!await _catchUp(addon, entry, before?.updatedAt) && before != null) {
        entry.position = _rewound(entry.position, before.updatedAt);
      }
    }
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
    // The book before may still be playing: its position must not move this one.
    _chapterTimer?.cancel();
    current.value = entry;
    await _library.save(entry);
    await _loadChapter(play: true);
  }

  /// Puts the most recent unfinished book back in the player, paused, as the app starts. Its
  /// link is fetched a moment later, quietly, so pressing play starts at once.
  void restoreLastSession() {
    // Skips books whose addon was removed, so an older one that still plays comes back.
    final entry = _library.entries
        .where((e) => !e.finished && _addons.byId(e.addonId) != null)
        .firstOrNull;
    if (entry == null) return;
    final addon = _addons.byId(entry.addonId)!;
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

  /// Checks the chapter every second while a file of several chapters plays. Called when
  /// playing starts or stops and when a file opens: a book opened while another plays never
  /// changes `playing`.
  void _followChapters() {
    _chapterTimer?.cancel();
    _chapterTimer = _player.playing && _inFileChapters
        ? Timer.periodic(const Duration(seconds: 1), (_) => _syncChapter())
        : null;
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

  /// Plays chapter [index] from its start; the place left is kept in the history.
  Future<void> playChapter(int index) => _playChapter(index, remember: true);

  Future<void> _playChapter(int index, {required bool remember}) async {
    final entry = current.value;
    if (entry == null || index < 0 || index >= entry.book.chapters.length) {
      return;
    }
    await _saveProgress();
    if (remember) _remember(entry);
    _moveTo(entry, index);
    await _library.save(entry);
    current.changed();
    await _loadChapter(play: true);
  }

  /// Plays from [mark] (a bookmark, or a place in the history).
  Future<void> jumpTo(Mark mark) async {
    final entry = current.value;
    if (entry == null || !mark.fits(entry.book)) return;
    await _saveProgress();
    _remember(entry);
    entry.chapterIndex = mark.chapterIndex;
    entry.position = mark.position;
    await _library.save(entry);
    current.changed();
    // Within the open file this only seeks.
    await _loadChapter(play: true);
  }

  /// Marks a book finished, or not finished (it then starts over).
  Future<void> markFinished(LibraryEntry entry, bool finished) async {
    final open = current.value?.key == entry.key;
    if (open && finished) await pause();
    final restart = !finished && entry.finished;
    if (restart) _moveTo(entry, 0);
    entry.finished = finished;
    await _library.save(entry);
    _sync.report(_addons.byId(entry.addonId), entry);
    if (!open) return;
    current.changed();
    if (restart && status.value.phase == PlayerPhase.ready) {
      await _loadChapter(play: false);
    }
  }

  /// Bookmarks where the user is now.
  Future<Mark?> addBookmark() async {
    final entry = current.value;
    if (entry == null) return null;
    if (status.value.phase == PlayerPhase.ready) {
      entry.position = _player.position;
    }
    final mark = entry.here();
    entry.bookmarks.add(mark);
    await _library.save(entry);
    current.changed();
    return mark;
  }

  /// Replaces bookmark [old] with [mark], or deletes it when [mark] is null.
  Future<void> changeBookmark(Mark old, Mark? mark) async {
    final entry = current.value;
    if (entry == null) return;
    final i = entry.bookmarks.indexOf(old);
    if (i < 0) return;
    if (mark == null) {
      entry.bookmarks.removeAt(i);
    } else {
      entry.bookmarks[i] = mark;
    }
    await _library.save(entry);
    current.changed();
  }

  /// Keeps where the user is before a jump, so an accidental tap can be undone.
  void _remember(LibraryEntry entry) {
    if (status.value.phase == PlayerPhase.ready) {
      entry.position = _player.position;
    }
    entry.remember(entry.here());
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
    status.value = PlayerStatus(PlayerPhase.loading, message: _loadingNote);
    // Moving on to the next chapter, the player stays "playing": a pause would end the
    // foreground service on Android, and with the screen off the system then stops the app
    // before the next chapter's link arrives.
    if (!play) await _player.pause();

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
        // The audio backend reports a file it can't open as an error and never finishes
        // loading: that error ends the wait. A stalled server or audio device must not leave
        // the player loading forever either.
        final failed = _openFailure = Completer<Object>();
        // A torrent first has to find the people sharing it.
        final wait = _addons.host.torrents?.hashOf(url) != null
            ? _torrentOpenTimeout
            : _openTimeout;
        try {
          await Future.any<Object?>([
            _player.setUrl(url, initialPosition: entry.position),
            failed.future.then<Object?>((e) => throw e),
          ]).timeout(
            wait,
            onTimeout: () => throw AddonException(
              'The audio did not start within ${wait.inSeconds} seconds.',
            ),
          );
        } finally {
          _openFailure = null;
        }
        _loadedUrl = url;
        // Keeps the torrent engine up while its link plays, and ties the torrent to the book.
        _addons.host.torrents?.loaded(url, entry.key);
      }
      if (token != _loadToken) return;
      status.value = const PlayerStatus(PlayerPhase.ready);
      _followChapters();
      // This version plays: no more falling back.
      _started = true;
      _retries = 0;
      _alternatives = const [];
      _loadingNote = null;
      if (play) unawaited(_player.play());
      unawaited(_prefetch(addon, entry, _nextFile(entry)));
    } on Object catch (e) {
      if (token != _loadToken) return;
      if (!_started && _alternatives.isNotEmpty) {
        unawaited(_tryNextVersion(e));
        return;
      }
      // Moving on in a book that was playing: the connection may still be waking up (a phone
      // with the screen off). Try again a few times, still "playing" so the phone keeps the app
      // awake, each time with a fresh link.
      if (_started && play && _retries < _retryDelays.length) {
        final delay = _retryDelays[_retries++];
        _links.remove(_linkKey(addon, entry, entry.chapterIndex));
        _loadedUrl = null;
        status.value = PlayerStatus(
          PlayerPhase.loading,
          message: 'Connection problem, trying again in ${delay.inSeconds} s…',
        );
        _retryTimer = Timer(delay, () => _loadChapter(play: play));
        return;
      }
      _retries = 0;
      _loadingNote = null;
      unawaited(_player.pause());
      status.value = PlayerStatus(PlayerPhase.error, message: _describe(e));
    }
  }

  /// The version that was opened didn't start: quietly opens the next one. A version that never
  /// played leaves nothing behind in the library.
  Future<void> _tryNextVersion(Object failure) async {
    final failed = current.value;
    final next = _alternatives.first;
    final rest = _alternatives.skip(1).toList();
    _loadingNote =
        'That version didn'
        't play (${_describe(failure)}). Trying the next one…';
    status.value = PlayerStatus(PlayerPhase.loading, message: _loadingNote);
    if (failed != null &&
        failed.chapterIndex == 0 &&
        failed.position ==
            (failed.book.chapters.first.start ?? Duration.zero)) {
      await _library.remove(failed);
    }
    try {
      var book = next.book ?? await next.addon.client.book(next.bookId);
      final look = _look;
      if (look != null) book = book.withLookOf(look);
      _nextNote = _loadingNote;
      await openBook(
        next.addon,
        book,
        workKey: _workKey,
        look: look,
        alternatives: rest,
      );
    } on Object catch (e) {
      _alternatives = rest;
      if (rest.isNotEmpty) return _tryNextVersion(e);
      _loadingNote = null;
      unawaited(_player.pause());
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
      unawaited(_playChapter(next, remember: false));
    } else {
      entry.finished = true;
      entry.position = Duration.zero;
      unawaited(_player.pause());
      unawaited(_library.save(entry));
      _sync.report(_addon, entry);
      status.value = const PlayerStatus(PlayerPhase.idle, message: 'Finished');
    }
  }

  /// Saves where the user is, and tells the media server it plays from ([tick]: the regular
  /// save while playing, sent less often).
  Future<void> _saveProgress({bool notify = true, bool tick = false}) async {
    final entry = current.value;
    if (entry == null || status.value.phase != PlayerPhase.ready) return;
    entry.position = _player.position;
    await _library.save(entry, notify: notify);
    _sync.report(_addon, entry, tick: tick);
  }

  /// mpv messages that the desktop audio backend passes on as errors although playback goes on.
  static bool _harmless(Object error) =>
      error is PlayerException &&
      (error.message ?? '').contains('Failed to create file cache');

  void _onPlaybackError(Object error, StackTrace stack) {
    if (_harmless(error)) return;
    final opening = _openFailure;
    if (opening != null) {
      if (!opening.isCompleted) opening.complete(error);
      return;
    }
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

  static final _sleepPlus = MediaControl.custom(
    androidIcon: 'drawable/ic_sleep_add',
    label: 'Sleep timer +5 min',
    name: sleepPlusAction,
  );

  void _broadcast(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
          if (sleepTimer.value?.endsAt != null) _sleepPlus,
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
    final entry = current.value;
    if (status.value.phase == PlayerPhase.ready) {
      final back = _rewound(_player.position, _pausedAt);
      if (back != _player.position) await seek(back);
      unawaited(_player.play());
    } else if (entry != null) {
      // A book put back at start (or finished): away since it was last saved.
      if (status.value.phase == PlayerPhase.idle) {
        if (!await _catchUp(_addon, entry, entry.updatedAt)) {
          entry.position = _rewound(entry.position, entry.updatedAt);
        }
      }
      await _loadChapter(play: true);
    }
  }

  /// Moves [entry] to where the user got to on its media server, when they listened there after
  /// Shu last saved it ([since]). Whether it moved.
  Future<bool> _catchUp(
    InstalledAddon? addon,
    LibraryEntry entry,
    DateTime? since,
  ) async {
    final place = await _sync.newer(addon, entry, since);
    if (place == null) return false;
    final before = entry.here();
    entry.remember(before);
    entry.chapterIndex = place.chapterIndex;
    entry.position = place.position;
    onServerMove?.call(ServerSync.name(addon) ?? 'the server', before);
    return true;
  }

  /// [position] stepped back for a pause that began at [since], see [rewindAfter].
  Duration _rewound(Duration position, DateTime? since) {
    if (since == null || !settings.autoRewind) return position;
    final target = position - rewindAfter(now().difference(since));
    return target < Duration.zero ? Duration.zero : target;
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    await _saveProgress();
  }

  Future<void> togglePlay() => _player.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    final entry = current.value;
    if (entry != null &&
        status.value.phase == PlayerPhase.ready &&
        (position - _player.position).abs() > const Duration(minutes: 1)) {
      _remember(entry);
    }
    await _player.seek(position);
    // The desktop backend reports the old position for a moment after seeking: wait for the new
    // one, so what is saved or bookmarked next is right.
    bool there() =>
        (_player.position - position).abs() < const Duration(seconds: 1);
    if (!there()) {
      await _player.playbackEventStream
          .firstWhere((_) => there())
          .timeout(
            const Duration(seconds: 1),
            onTimeout: () => _player.playbackEvent,
          );
    }
    _syncChapter();
    // While paused nothing else saves it before the app may be closed.
    if (!_player.playing) await _saveProgress();
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
      await seek(start);
    } else {
      await playChapter(entry.chapterIndex - 1);
    }
  }

  @override
  /// Changes the speed; [save] keeps it for next time (a slider saves once it is let go).
  Future<void> setSpeed(double speed, {bool save = true}) async {
    await _player.setSpeed(speed);
    if (save) settings.speed = speed;
  }

  /// The Android effects as last applied, so other setting changes don't reach the player.
  ({bool silence, bool boost})? _effects;

  void _applyEffects() {
    if (!PlayerSettings.hasAudioEffects) return;
    final want = (silence: settings.skipSilence, boost: settings.voiceBoost);
    if (want == _effects) return;
    _effects = want;
    unawaited(_player.setSkipSilenceEnabled(want.silence));
    unawaited(_boost.setTargetGain(6)); // dB
    unawaited(_boost.setEnabled(want.boost));
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == sleepPlusAction) sleepTimer.extend();
  }

  static const sleepPlusAction = 'sleepPlus5';

  /// Stops playback and closes the book (progress is kept).
  @override
  Future<void> stop() async {
    await _saveProgress();
    _loadToken++;
    _retryTimer?.cancel();
    cancelSleepTimer();
    await _player.stop();
    _loadedUrl = null;
    _addons.host.torrents?.loaded(null, null);
    current.value = null;
    mediaItem.add(null);
    status.value = PlayerStatus.idle;
    await super.stop();
  }

  void setSleepTimer(Duration duration) => sleepTimer.setFor(duration);

  void setSleepAtChapterEnd() => sleepTimer.setEndOfChapter();

  void cancelSleepTimer() => sleepTimer.cancel();

  // The library for car screens and other media browsers (Android Auto).

  static const _continueId = 'continue';
  static const _finishedId = 'finished';

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async => switch (parentMediaId) {
    AudioService.browsableRootId => const [
      MediaItem(id: _continueId, title: 'Continue listening', playable: false),
      MediaItem(id: _finishedId, title: 'Finished', playable: false),
    ],
    // What the system offers to resume, e.g. when a car connects.
    AudioService.recentRootId => _browsable(finished: false).take(1).toList(),
    _continueId => _browsable(finished: false),
    _finishedId => _browsable(finished: true),
    _ => const [],
  };

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final entry = _library.entries.where((e) => e.key == mediaId).firstOrNull;
    return entry == null ? null : _browseItem(entry);
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final entry = _library.entries.where((e) => e.key == mediaId).firstOrNull;
    if (entry != null) await resume(entry);
  }

  List<MediaItem> _browsable({required bool finished}) => [
    for (final e in _library.entries)
      if (e.finished == finished && _addons.byId(e.addonId) != null)
        _browseItem(e),
  ].take(30).toList();

  static MediaItem _browseItem(LibraryEntry entry) => MediaItem(
    id: entry.key,
    title: entry.book.title,
    artist: entry.book.byline.isEmpty ? null : entry.book.byline,
    artUri: entry.book.cover == null ? null : Uri.tryParse(entry.book.cover!),
    playable: true,
    // How far along, as Android Auto shows it under the title.
    extras: {
      'android.media.extra.PLAYBACK_STATUS': entry.finished
          ? 2
          : entry.progress > 0
          ? 1
          : 0,
      'androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE': entry.progress,
    },
  );

  Future<void> dispose() async {
    unawaited(_changes.close());
    _saveTimer?.cancel();
    _chapterTimer?.cancel();
    sleepTimer.dispose();
    settings.removeListener(_applyEffects);
    await _saveProgress();
    await _player.dispose();
  }
}
