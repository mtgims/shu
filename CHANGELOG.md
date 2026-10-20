# Changelog

## 0.6.2 - 2026-10-20

### New
- An extension update that comes with a new warning no longer gets skipped without a word:
  Shu tells you, and the extension on the Addons page gets a "Review update" button that shows
  the warning before installing

### Fixed
- After the torrent engine failed to start once, torrents didn't play again until Shu was
  restarted
- An extension can only keep torrents in a folder you picked in its settings
- Extension ids may only have letters, digits, ".", "_" and "-"
- Downloads of extensions and repositories stop at 8 MB, and a repository on the web can only
  point to https links
- An app update download that stops sending fails after a minute instead of waiting forever,
  and doesn't leave half a file behind
- Errors in the background checks at startup are caught, and links are left out of the log
  (they can hold an addon's API key)

## 0.6.1 - 2026-10-20

### New
- The keyboard scrolls pages: ↑ ↓, Page Up, Page Down, Home and End
- The keyboard's media keys play, pause and skip chapters while Shu's window is in front.
  On Windows they don't yet work from other windows
- Ctrl+1 to Ctrl+4 open Home, Search, Library and Addons

### Changed
- An outline shows which control the keyboard is on. A click hides it again
- In a wide window the side rail stays on every page, so you can switch tabs from a book
- On a wide window the player shows its chapters on a card next to the controls, not at the
  far edge
- On a wide window a book's Play button sits next to the cover, and the book's title shows in
  the top bar once you scroll down
- Search lists only the addons that found something, and names the others in one line
- Extension settings no longer stretch across a wide window
- An extension can't go online while Shu reads it before installing, so nothing it does
  happens before you accept it
- An addon's Settings button only opens web pages
- Android no longer backs up Shu's data or copies it to a new phone, because it holds your
  server passwords. A new phone starts with an empty library

### Fixed
- Ctrl+F opened Search without putting the cursor in the search field
- Magnet links that give the torrent's hash in the short (base32) form play now
- Addons whose catalogs or books have numbers as ids show them instead of failing
- Closing the add-extension or sign-in window while it was still working could also close
  the page behind it. The window now stays open until it is done
- A catalog page in a large window loads more books by itself when the first ones don't fill
  it, and no longer stops at a page of books it already showed
- After a catalog page fails to load, scrolling no longer retries over and over; "Try again"
  does
- A number setting of an extension that is half typed ("-") is marked instead of saved as
  empty
- A removed book could still open from a card that was on screen
- Small errors when closing the bookmark note and extension settings

## 0.6.0 - 2026-10-15

### New
- Shu can play torrents itself, for extensions that ask for it: no account or other app
  needed. It ships with TorrServer, which runs only while a book needs it and only answers
  on this device
- Extensions can carry a warning you have to accept before installing them. It is also shown
  at the top of their settings
- Extension settings can ask for a folder

### Changed
- The downloads are larger (by about 25 MB) because they include TorrServer
- On Linux and Windows, a stream that goes quiet for a moment (a torrent still finding people,
  a slow server) no longer stops playback after 5 seconds; it gets a minute

## 0.5.2 - 2026-10-15

### Changed
- Signing in to a server by its domain name now only uses https. Before, when https failed, Shu
  tried plain http, and anyone who could block https could then read the password. For a server
  without https, type its address with http:// and its port

### Fixed
- A book or addon Shu can't read (saved by a newer version, or an extension whose file is gone)
  is now kept as it is instead of disappearing at the next save, and a damaged list no longer
  stops the app from starting: it is set aside and Shu starts with an empty one
- Opening a book with chapters inside one file while another book was playing left the chapter
  stuck on the first one until you paused and played again
- A stable extension release now counts as newer than its beta, so it gets installed
- Book descriptions from Audiobookshelf and Jellyfin show quotes, dashes and other special
  characters properly
- A web page served instead of a cover (like a Wi-Fi sign-in page) is no longer saved as that
  cover

## 0.5.1 - 2026-10-15

### Changed
- Book pages with many chapters open at once and stay smooth while a book plays: chapters are
  built as they scroll into view, and only the parts showing where you are follow playback
- Home no longer redraws every row each time progress is saved
- Covers are drawn in one pass, and a cover wanted at two sizes is fetched once
- Saving progress does less work: each book's chapter list is turned into text once, not on
  every save
- Seek bars and progress lines stop ticking while the app is in the background, and hidden tabs
  stop their animations
- Dragging the speed slider saves the speed once, when you let go
- Jellyfin searches ask for matching folders all at once

### Fixed
- The player no longer leaves a timer running each time it is opened or a seek is made (it
  added up over a long session, also with the screen off)
- Opening the player on a computer no longer stutters: the page moves as one picture while it
  opens, the flying cover doesn't reload on the way, and the chapter list beside the player
  comes in once it has opened

## 0.5.0 - 2026-10-15

### New
- Bookmarks: mark a place with the button under the player, give it a note, and find it under
  the chapters (marks also show on the seek bar)
- History: the places you jumped away from (picking a chapter, dragging far) are kept, so a
  slip of the finger is easy to undo
- Progress syncs with Audiobookshelf and Jellyfin: the server's apps carry on where Shu
  stopped, and Shu picks up where you got to elsewhere (with an Undo)
- Android Auto: your books in progress and finished ones, and the player, in the car
- The sleep timer fades out over its last seconds, has a +5 minutes button (also in the
  notification), and on phones a shake near the end adds 5 minutes
- The sleep timer offers the time you chose last first
- Skip silence and voice boost on Android (Now Playing → ⋮ → Playback settings)
- Library: show all, in progress or finished books, and mark a book finished or not
- Linux: an AppImage, a single file that runs on most distributions without installing libmpv

### Changed
- After a pause Shu steps back a few seconds (more after a long break) so you find the thread
  again; it can be turned off in Playback settings
- The player takes on the main colour of the book's cover, over a blurred copy of it, and
  has those colours ready before it opens
- Opening the player is smooth: it slides up from the player bar with the cover flying into
  place; on a phone, drag it down to close
- On a computer, pages fade forward instead of zooming
- Extensions do their work in the background, so the app no longer stutters while a book page,
  its versions or a search load
- Speed goes from 0.5× to 3× in steps of 0.05, with a slider and − / + buttons
- Chapters, bookmarks and history are tabs, beside the player in wide windows

### Fixed
- Closing the window on a computer now saves where you are in the book: it used to come back
  up to 15 seconds earlier
- A position you moved to while paused is saved right away

## 0.4.2 - 2026-10-14

### New
- Addons → ⋮ → About Shu shows the version and what's new in it

### Changed
- On a computer Shu now works like a desktop app instead of a stretched phone app
- A player bar along the bottom has every control (skip, seek, speed, sleep timer), also on
  book pages, so the full-screen player is rarely needed
- Keys: Space plays or pauses, ← and → skip back 15 s and forward 30 s, Esc or Alt+← go back,
  Ctrl+F searches; the mouse's back button goes back too
- Rows of books have arrows to page through them, and can be dragged with the mouse
- Menus open as small dialogs instead of sliding up from the bottom of the window
- Menus, dropdowns, choice dialogs and lists (Library, Search, chapters, versions) are
  rounded: the row under the pointer lights up as a rounded shape instead of a hard rectangle
- The full player lists the chapters beside it in wide windows
- Lists keep a readable width, notices are small, and right-clicking a book in the Library
  opens its menu
- The window can no longer be made too small to use

## 0.4.1 - 2026-10-14

### New
- Catalog books show the other books of their series, when the catalog knows them

### Changed
- Extensions installed from a plain http:// address (other than this device) no longer update
  from there: someone on the same network could have swapped in other code. They update from
  the https address the extension names instead, when it names one; otherwise install them again
  from an https:// address. Installing again keeps an extension's settings, API keys included
- An extension you already have says "Reinstall" in a repository, wherever it came from
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
