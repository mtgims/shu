# Third-party code

- `just_audio_media_kit/`: [just_audio_media_kit](https://pub.dev/packages/just_audio_media_kit)
  2.1.0 (public domain), with one addition: `JustAudioMediaKit.networkTimeout`, how long mpv
  waits for data from a stream (media_kit fixes it at 5 s, too short for a torrent that is
  still finding people to download from). Drop the copy once the package offers this.
- `audio_service_mpris/`: [audio_service_mpris](https://pub.dev/packages/audio_service_mpris)
  0.2.1 (MIT), changed so desktop media widgets show Shu properly: the name "Shu" and its
  desktop file, the playback speed (and 0.5× to 3×), a position that moves on between
  updates, a `Seeked` signal on jumps, relative seeks, a track id, and no cover link when
  there is no cover. The changes are marked "Shu:". Drop the copy if the package gets these.
