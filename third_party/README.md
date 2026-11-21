# Third-party code

- `just_audio_media_kit/`: [just_audio_media_kit](https://pub.dev/packages/just_audio_media_kit)
  2.1.0 (public domain), with these changes, marked "Shu:":
  - `JustAudioMediaKit.networkTimeout`, how long mpv waits for data from a stream (media_kit
    fixes it at 5 s, too short for a torrent that is still finding people to download from).
  - A stream that stops sending partway is an error, not the end of the file: mpv reports it
    as an ordinary end, and the app moved on past the part never heard. It counts as cut short
    when both bytes and time are missing (the file size is noted when it opens).
  - ffmpeg reconnects to a quiet stream once, not about ten times (each after the network
    timeout), so a dead link reaches the app's recovery in a minute or two.
  - `fflags=+fastseek` for the demuxer: an MP3 without a seek table that carries a cover picture
    (most audiobook rips) was otherwise searched frame by frame from the start, so a jump or a
    resume hours in downloaded everything before it first.
  - Links are left out of mpv's log lines and error messages (they can hold login tokens).

  Drop the copy once the package does these.
- `audio_service_mpris/`: [audio_service_mpris](https://pub.dev/packages/audio_service_mpris)
  0.2.1 (MIT), changed so desktop media widgets show Shu properly: the name "Shu" and its
  desktop file, the playback speed (and 0.5× to 3×), a position that moves on between
  updates, a `Seeked` signal on jumps, relative seeks, a track id, and no cover link when
  there is no cover. The changes are marked "Shu:". Drop the copy if the package gets these.
