# Shu

Shu is an audiobook player for Android, Linux and Windows. It doesn't come with any books or
sources: you add extensions, small JavaScript files that run inside the app and tell it where to
find books and how to play them.

- Browse and search across all your extensions
- A library that remembers where you stopped in every book
- Chapters, playback speed, a sleep timer, 15/30 second skips
- Background playback with lock screen controls on Android, media keys on Linux

macOS and iOS builds are set up but haven't been tested yet.

## Download

Get the latest version from the [releases page](../../releases/latest).

- **Android**: `shu-<version>-android-arm64-v8a.apk` works on almost every phone from the last
  few years. Older 32-bit phones need the `armeabi-v7a` one. Android will ask you to allow
  installing apps from your browser or file manager.
- **Linux**: unpack `shu-<version>-linux-x64.tar.gz` and run `shu/shu`. It needs libmpv
  (`libmpv2` on Debian/Ubuntu, `mpv-libs` on Fedora, `mpv` on Arch).
- **Windows**: unpack `shu-<version>-windows-x64.zip` and run `Shu\shu.exe`.

## Adding extensions

Open **Addons → Add addon** and paste a link. It can point to a single extension (a `.js`
file) or to a repository of extensions (an `index.json` file), in which case you pick which ones
to install.

For a repository hosted on GitHub, use the raw link: open `index.json` on GitHub, press **Raw**
and copy the address. It looks like
`https://raw.githubusercontent.com/<user>/<repo>/main/index.json`.

If an extension has settings, they open right after installing it. Settings stay on your device.
Installed extensions update themselves; the app checks once a day.

There are two kinds of extensions:

- **Catalogs** fill Home with books to explore (trending, new releases, genres) and describe
  them: narrator, length, rating, series.
- **Sources** find versions you can actually play. Press Play on a catalog book and the app asks
  your sources for versions and starts the best match.

Shu doesn't host, index or link to any content. What you can play depends entirely on the
extensions you choose to install.

## Writing extensions

See [docs/EXTENSIONS.md](docs/EXTENSIONS.md). Extensions are plain JavaScript and run on the
device, so there's no server to set up. Shu also supports addons that run on a server, see
[docs/PROTOCOL.md](docs/PROTOCOL.md).

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to
build Shu and run the tests.

## License

Shu is free software under the [GNU General Public License v3.0](LICENSE) or any later version.
