library just_audio_media_kit;

import 'dart:async';

import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'src/set_property.dart';

/// An [AudioPlayerPlatform] which wraps `package:media_kit`'s [Player]
class MediaKitPlayer extends AudioPlayerPlatform {
  static const kErrorCode = 1;

  /// `package:media_kit`'s [Player]
  late final Player _player;

  /// The subscriptions that have to be disposed
  late final List<StreamSubscription> _streamSubscriptions;

  final _readyCompleter = Completer<void>();

  /// Completes when the player is ready
  Future<void> ready() => _readyCompleter.future;

  static final _logger = Logger('MediaKitPlayer');

  final _eventController = StreamController<PlaybackEventMessage>.broadcast();
  final _dataController = StreamController<PlayerDataMessage>.broadcast();

  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  Duration _bufferedPosition = Duration.zero;
  Duration _position = Duration.zero;
  Duration? _duration;

  /// Shu: the open file's size in bytes, noted when it opens: mpv forgets it once the stream fails.
  int? _fileSize;
  bool _playing = false;
  bool _mediaOpened = false;
  int? _errorCode;
  String? _errorMessage;
  Completer<Duration?>? _loadCompleter;

  /// The index that's currently playing
  int _currentIndex = 0;

  /// [LoadRequest.initialPosition] or [seek] request before [Player.play] was called and/or finished loading.
  Duration? _setPosition;

  Media? get _currentMedia {
    var medias = _player.state.playlist.medias;
    if (medias.isEmpty) return null;
    return medias[_player.state.playlist.index];
  }

  MediaKitPlayer(super.id) {
    _player = Player(
        configuration: PlayerConfiguration(
      pitch: JustAudioMediaKit.pitch,
      protocolWhitelist: JustAudioMediaKit.protocolWhitelist,
      title: JustAudioMediaKit.title,
      bufferSize: JustAudioMediaKit.bufferSize,
      logLevel: JustAudioMediaKit.mpvLogLevel,
      ready: () => _readyCompleter.complete(),
    ));

    if (JustAudioMediaKit.prefetchPlaylist) {
      setProperty(_player, 'prefetch-playlist', 'yes');
    }
    // Shu: media_kit gives up on a stream after 5 s without data; see networkTimeout.
    setProperty(
      _player,
      'network-timeout',
      '${JustAudioMediaKit.networkTimeout}',
    );
    // Shu: ffmpeg reconnects to a stream that went quiet about ten times, each after the
    // network timeout, so a dead link held playback for many minutes. One reconnect covers a
    // blip; after that the app gets an error and opens a fresh link from the same place.
    setProperty(_player, 'stream-lavf-o', 'reconnect_max_retries=1');
    // Shu: an MP3 without a seek table (common in audiobook rips) is otherwise searched frame
    // by frame from the start: a jump or a resume hours in read the whole file before it, the
    // player silent for minutes. fastseek jumps to the byte the bitrate points at instead.
    appendToList(_player, 'demuxer-lavf-o', 'fflags=+fastseek');

    _streamSubscriptions = [
      _player.stream.duration.listen((duration) {
        if (_currentMedia?.extras?['overrideDuration'] != null) return;

        if (_setPosition != null && duration.inSeconds > 0) {
          unawaited(_player.seek(_setPosition!));
          _setPosition = null;
        }
        _updateDuration(duration);
        _updatePlaybackEvent();
        if (duration > Duration.zero && _fileSize == null) {
          unawaited(getProperty(_player, 'file-size')
              .then((size) => _fileSize = int.tryParse(size ?? '')));
        }
      }),
      _player.stream.position.listen((position) {
        _position = position;
        final start = _currentMedia?.start;
        if (start != null) _position -= start;
        if (_position < Duration.zero) _position = Duration.zero;
        _updatePlaybackEvent();
      }),
      _player.stream.buffering.listen((isBuffering) {
        final start = _currentMedia?.start;
        if (!isBuffering && start != null && _bufferedPosition <= start) {
          // Not ready yet, will be triggered by _player.stream.buffer
          return;
        }
        if (_processingState == ProcessingStateMessage.loading) {
          if (!isBuffering && _mediaOpened) {
            _processingState = ProcessingStateMessage.ready;
            if (_loadCompleter?.isCompleted != true) {
              _loadCompleter?.complete(_duration);
            }
          }
        } else if (_processingState != ProcessingStateMessage.completed ||
            isBuffering) {
          _processingState = isBuffering
              ? ProcessingStateMessage.buffering
              : ProcessingStateMessage.ready;
          if (_duration == null) {
            _updateDuration(_player.state.duration);
          }
        }
        _errorCode = null;
        _errorMessage = null;
        _updatePlaybackEvent();
      }),
      _player.stream.buffer.listen((buffer) {
        _bufferedPosition = buffer;
        // Detect ready for clipping audio source
        final start = _currentMedia?.start;
        if (!_player.state.buffering &&
            _mediaOpened &&
            start != null &&
            _bufferedPosition > start) {
          _processingState = ProcessingStateMessage.ready;
          if (_loadCompleter?.isCompleted != true) {
            _loadCompleter?.complete(_duration);
          }
        }
        _updatePlaybackEvent();
      }),
      _player.stream.volume.listen((volume) {
        _dataController.add(PlayerDataMessage(volume: volume / 100.0));
      }),
      _player.stream.completed.listen((completed) async {
        // Shu: mpv reports a stream that stopped sending (its reads timed out) as an ordinary
        // end, and the app would move on past the part never heard. Reported as an error
        // instead, the position kept, so the app can open it again from there.
        if (completed && await _cutShort()) {
          _processingState = ProcessingStateMessage.idle;
          _errorCode = kErrorCode;
          _errorMessage = 'The stream stopped before the end of the file.';
          _updatePlaybackEvent();
          return;
        }
        _bufferedPosition = _position = Duration.zero;
        if (completed &&
            // is at the end of the [Playlist]
            _currentIndex == _player.state.playlist.medias.length - 1 &&
            // is not looping (technically this shouldn't be fired if the player is looping)
            _player.state.playlistMode == PlaylistMode.none) {
          _processingState = ProcessingStateMessage.completed;
        }
        _errorCode = null;
        _errorMessage = null;

        _updatePlaybackEvent();
      }),
      _player.stream.error.listen((error) {
        final errorUri = RegExp(r'Failed to open (.*)\.').firstMatch(error)?[1];
        if (errorUri == null || errorUri == _currentMedia?.uri) {
          _processingState = ProcessingStateMessage.idle;
          _errorCode = kErrorCode;
          // Shu: without the link, which can hold a login token; this text reaches the screen.
          _errorMessage = _withoutLinks(error);
          _updatePlaybackEvent();
        }
        _logger.severe('ERROR OCCURRED: $error');
      }),
      _player.stream.playlist.listen((playlist) {
        if (_currentIndex != playlist.index) {
          _bufferedPosition = _position = Duration.zero;
          _currentIndex = playlist.index;
          _fileSize = null;
        }
        _duration = _currentMedia?.extras?['overrideDuration'];
        _updatePlaybackEvent();
      }),
      _player.stream.playlistMode.listen((playlistMode) {
        _dataController.add(
            PlayerDataMessage(loopMode: _playlistModeToLoopMode(playlistMode)));
      }),
      _player.stream.pitch.listen((pitch) {
        _dataController.add(PlayerDataMessage(pitch: pitch));
      }),
      _player.stream.rate.listen((rate) {
        _dataController.add(PlayerDataMessage(speed: rate));
      }),
      _player.stream.log.listen((event) {
        // ignore: avoid_print
        // Shu: links left out, they can hold login tokens.
        print(
          "MPV: [${event.level}] ${event.prefix}: ${_withoutLinks(event.text)}",
        );
      }),
    ];
  }

  /// Shu: whether the file ended short of both its bytes and its length. Either alone isn't
  /// enough: an MP3's length can be an estimate (all bytes read, time short), and an M4A can
  /// keep its index after the audio (time complete, bytes left). Streams of unknown size
  /// only end when closed, so they count as complete.
  Future<bool> _cutShort() async {
    final size = _fileSize;
    final length = _duration;
    if (size == null || length == null) return false;
    final read = int.tryParse(await getProperty(_player, 'stream-pos') ?? '');
    return read != null &&
        size - read > 8 * 1024 &&
        length - _position > const Duration(seconds: 2);
  }

  void _updateDuration(Duration duration) {
    final start = _currentMedia?.start;
    final end = _currentMedia?.end;
    if (end != null) duration = end;
    if (start != null) duration -= start;
    _duration = duration;
  }

  PlaylistMode _loopModeToPlaylistMode(LoopModeMessage loopMode) {
    return switch (loopMode) {
      LoopModeMessage.off => PlaylistMode.none,
      LoopModeMessage.one => PlaylistMode.single,
      LoopModeMessage.all => PlaylistMode.loop,
    };
  }

  LoopModeMessage _playlistModeToLoopMode(PlaylistMode playlistMode) {
    return switch (playlistMode) {
      PlaylistMode.none => LoopModeMessage.off,
      PlaylistMode.single => LoopModeMessage.one,
      PlaylistMode.loop => LoopModeMessage.all,
    };
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      _dataController.stream;

  /// Updates the playback event
  void _updatePlaybackEvent() {
    _eventController.add(PlaybackEventMessage(
      processingState: _processingState,
      updateTime: DateTime.now(),
      updatePosition: _position,
      bufferedPosition: _bufferedPosition,
      duration: _duration,
      icyMetadata: null,
      currentIndex: _currentIndex,
      androidAudioSessionId: null,
      errorCode: _errorCode,
      errorMessage: _errorMessage,
    ));
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _logger.finest('load(${request.toMap()})');
    _mediaOpened = false;
    _loadCompleter = Completer();
    _currentIndex = request.initialIndex ?? 0;
    _bufferedPosition = Duration.zero;
    _position = Duration.zero;
    _duration = null;
    _fileSize = null;
    _processingState = ProcessingStateMessage.loading;
    _errorCode = null;
    _errorMessage = null;
    _updatePlaybackEvent();

    if (request.audioSourceMessage is ConcatenatingAudioSourceMessage) {
      final audioSource =
          request.audioSourceMessage as ConcatenatingAudioSourceMessage;
      final playable = Playlist(
          audioSource.children.map(_convertAudioSourceIntoMediaKit).toList(),
          index: _currentIndex);

      await _player.open(playable, play: _playing);
    } else {
      final playable =
          _convertAudioSourceIntoMediaKit(request.audioSourceMessage);
      _logger.finest('playable is ${playable.toString()}');
      await _player.open(playable, play: _playing);
    }
    _mediaOpened = true;

    if (request.initialPosition != null) {
      _setPosition = _position = request.initialPosition!;
    }

    _updatePlaybackEvent();
    final duration = await _loadCompleter?.future;
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _playing = true;
    if (_mediaOpened) {
      await _player.play();
    }
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _playing = false;
    if (_mediaOpened) {
      await _player.pause();
    }
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) {
    return _player
        .setVolume(request.volume * 100.0)
        .then((value) => SetVolumeResponse());
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) {
    return _player.setRate(request.speed).then((_) => SetSpeedResponse());
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) =>
      _player.setPitch(request.pitch).then((_) => SetPitchResponse());

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    await _player.setPlaylistMode(_loopModeToPlaylistMode(request.loopMode));
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
      SetShuffleModeRequest request) async {
    bool shuffling = request.shuffleMode != ShuffleModeMessage.none;
    await _player.setShuffle(shuffling);

    _dataController.add(PlayerDataMessage(
        shuffleMode:
            shuffling ? ShuffleModeMessage.all : ShuffleModeMessage.none));
    return SetShuffleModeResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    _logger.finest('seek(${request.toMap()})');
    if (request.index != null) {
      await _player.jump(request.index!);
      if (!_playing) await _player.pause();
    }

    final position = request.position;
    if (position != null) {
      _position = position;

      final start = _currentMedia?.start;
      var nativePosition = position;
      if (start != null) nativePosition += start;
      if (_player.state.duration.inSeconds > 0) {
        await _player.seek(nativePosition);
      } else {
        _setPosition = nativePosition;
      }
    } else {
      _position = Duration.zero;
    }

    // reset position on seek
    _updatePlaybackEvent();
    return SeekResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    // _logger.fine('concatenatingInsertAll(${request.toMap()})');
    for (final source in request.children) {
      await _player.add(_convertAudioSourceIntoMediaKit(source));

      final length = _player.state.playlist.medias.length;

      if (length == 0 || length == 1) continue;

      if (request.index < (length - 1) && request.index >= 0) {
        await _player.move(length, request.index);
      }
    }

    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    for (var i = request.startIndex; i < request.endIndex; i++) {
      await _player.remove(request.startIndex);
    }

    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) {
    return _player
        .move(
            request.currentIndex,
            // not sure why, but apparently there's an underlying difference between just_audio's move implementation
            // and media_kit, so let's fix it
            request.currentIndex > request.newIndex
                ? request.newIndex
                : request.newIndex + 1)
        .then((_) => ConcatenatingMoveResponse());
  }

  /// Release the resources used by this player.
  Future<void> release() async {
    _logger.info('releasing player resources');
    _mediaOpened = false;
    await _player.dispose();
    // cancel all stream subscriptions
    for (final StreamSubscription subscription in _streamSubscriptions) {
      unawaited(subscription.cancel());
    }
    _streamSubscriptions.clear();
  }

  /// Converts an [AudioSourceMessage] into a [Media] for playback
  Media _convertAudioSourceIntoMediaKit(AudioSourceMessage audioSource) {
    switch (audioSource) {
      case final UriAudioSourceMessage uriSource:
        return Media(uriSource.uri, httpHeaders: audioSource.headers);

      // removed because it doesn't seem to be actually working.
      // Related media-kit issue: https://github.com/media-kit/media-kit/issues/28
      // case final SilenceAudioSourceMessage silenceSource:
      //   // from https://github.com/bleonard252/just_audio_mpv/blob/main/lib/src/mpv_player.dart#L137
      //   return Media(
      //     'av://lavfi:anullsrc=d=${silenceSource.duration.inMilliseconds}ms',
      //     extras: {'overrideDuration': silenceSource.duration},
      //   );

      case final ClippingAudioSourceMessage clippingSource:
        return Media(clippingSource.child.uri,
            start: clippingSource.start, end: clippingSource.end);

      default:
        throw UnsupportedError(
            '${audioSource.runtimeType} is currently not supported');
    }
  }
}

/// Shu: [text] with every link replaced, as the app's own logs do.
String _withoutLinks(String text) => text.replaceAll(
      RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false),
      '<link>',
    );
