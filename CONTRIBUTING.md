# Contributing

Bug reports and pull requests are welcome. For anything bigger than a fix, open an issue first so
we can talk it over.

## Building

You need Flutter 3.47 or newer. On Linux, also the libmpv development files (`libmpv-dev` on
Debian/Ubuntu).

```sh
flutter run -d linux                            # run it
flutter build linux --release                   # build/linux/x64/release/bundle/
flutter build apk --release --split-per-abi     # build/app/outputs/flutter-apk/
flutter build windows --release                 # on Windows, with Visual Studio
```

## Tests

```sh
flutter analyze
flutter test
```

The integration tests run the real app, so they need a device or a desktop session. Run them
one file at a time:

```sh
flutter test integration_test/extension_engine_test.dart -d linux   # the JS extension engine
flutter test integration_test/playback_test.dart -d linux           # plays a few seconds of silence
flutter test integration_test/local_books_test.dart -d linux        # books from files, chapters in one file
flutter test integration_test/tour_test.dart -d linux               # clicks through the whole app
```

The tour installs two example extensions from a repository served on your machine, so it works
offline.

## Pull requests

- Run `dart format`, `flutter analyze` and `flutter test` before sending one (CI runs them too).
- Bump the version in `pubspec.yaml` and add a line to [CHANGELOG.md](CHANGELOG.md).
