# Changelog

## 0.4.1 - 2026-10-14

### New
- Catalog books show the other books of their series, when the catalog knows them

### Changed
- Extensions installed from a plain http:// address (other than this device) no longer update
  on their own: someone on the same network could have swapped in other code. Install them
  again from an https:// address to get updates
- Signing in to a server by its domain name (like books.example.org) tries https first, so the
  password isn't sent in the clear when the server has https
- Searching Audiobookshelf asks all its libraries at once

### Fixed
- When the connection dropped, error messages could show an addon's or extension's full web
  address, API keys included
- Progress bars move while you listen, not only from one chapter to the next (a book in one
  file showed 0% until it was finished)
- A cover cut off while downloading could stay broken; it's now fetched again
- One unreadable book in "On this device" no longer makes the books after it disappear
- At start, the player shows the last book that can still play, also when the most recent
  one came from an addon you removed

## 0.4.0 - 2026-10-14

### New
- Shu tells you when a new version is out, and on Android downloads and installs it (also under
  Addons → Check for updates)
- Play on a book with several versions starts one that is ready right away when it can
- If the version that starts doesn't play, the next good one is tried on its own
- When no version clearly matches the book, Play asks which one to play

### Changed
- Versions that clearly match the book are listed first

### Fixed
- With the screen off on Android, the next chapter sometimes didn't start; when the connection
  isn't back yet, Shu now tries again a few times before giving up
- Home couldn't always be scrolled back to the top
- Playback errors went unnoticed: a stream link that expires in the middle of a book now picks
  up again, and a file that can't be opened shows an error at once instead of after 30 seconds

## 0.3.1 - 2026-10-09

### Changed
- Clearer wording on the welcome screen and in the extension docs

## 0.3.0 - 2026-10-09

### New
- Play your own audiobooks: Library → Add audiobooks. On Android the files are copied into the
  app; on Linux and Windows you can add a whole folder and the files stay where they are
- Titles, authors, covers and chapters are read from the files' tags; fix them with Edit details
- Sign in to your Audiobookshelf or Jellyfin server (Addons → Add) to browse, search and stream
  its audiobook libraries
- M4B books show and skip between the chapters inside the file
- A welcome screen with the ways to get started

### Changed
- The Add button on Addons now asks what to add: a server or an extension
- Home rows with the same name say which server they come from
- Downloads on the releases page have the same names every version, so the buttons on the
  project page always get the newest one

### Fixed
- The player didn't always show the new chapter's title when a chapter ended
- When a stream link expires in the middle of a book, playback picks up again where it stopped
  instead of showing an error

## 0.2.2 - 2026-10-09

### New
- Shu has its own icon: 书 (shū, "book"), with its dot drawn as sound waves. On Android it
  follows themed icons, and the playback notification uses it too

## 0.2.1 - 2026-10-08

### Changed
- Shu is now open source, under the GPL-3.0
- The app is now called Shu

## 0.2.0 - 2026-10-08

### New
- Home is now built by catalog extensions: rows like "Trending now" and "New releases", and a
  row per genre
- "See all" on every row opens the whole list, loading more as you scroll
- Browse by genre
- Book pages show the narrator, length, rating, series and genres when the extension has them
- Books from a catalog list the versions your source extensions found. Play starts the best one,
  or picks up where you left off with the one you listened to before

### Changed
- Covers that aren't square (most book covers) are shown whole instead of cropped
- Search lists results from catalogs first
- The version you play keeps the catalog's title, cover and narrator in your library

### Fixed
- Extension settings were gone after restarting the app
- Extensions didn't load in a Linux build made from a clean checkout

## 0.1.0 - 2026-10-08

First release.

- Install extensions from a link to the `.js` file or to a repository `index.json`
- Search across all installed extensions
- Library that remembers where you stopped in every book
- Chapters, playback speed, sleep timer, 15/30 second skips
- Background playback with lock screen controls on Android, media keys on Linux
- Covers and the last known home screen are cached, so the app opens fast and works with a
  poor connection
