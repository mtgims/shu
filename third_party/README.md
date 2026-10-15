# Third-party code

- `just_audio_media_kit/`: [just_audio_media_kit](https://pub.dev/packages/just_audio_media_kit)
  2.1.0 (public domain), with one addition: `JustAudioMediaKit.networkTimeout`, how long mpv
  waits for data from a stream (media_kit fixes it at 5 s, too short for a torrent that is
  still finding people to download from). Drop the copy once the package offers this.
