# Extensions (v1)

An extension is a single JavaScript file that runs **inside the app**, on the user's device. It
lists books and tells the app how to play their chapters. Nothing runs on a server, and settings
(API keys, preferences) never leave the device.

The app runs extensions in QuickJS (JavaScriptCore on Apple platforms): plain ES2020, no DOM,
no Node APIs, no `fetch`, `URL`, `URLSearchParams` or `Intl`, and no methods newer than ES2020
(`Array.prototype.at` is missing, for example; setting TypeScript's `lib` to `es2020` catches
these). Everything that touches the outside world goes through `host`.
Bundle your code into one file (e.g. with esbuild, `--format=iife --target=es2020`).

## Shape

The file assigns a global `extension`:

```js
extension = {
  manifest: {
    id: 'example.audiobooks',      // unique, stable: letters, digits, ".", "_", "-" (64 at most)
    name: 'Example',
    version: '1.2.0',              // semver; the app updates when this grows
    description: '…',
    icon: 'https://…/icon.png',    // optional
    catalogs: [
      { id: 'search', name: 'Search', search: true },
      { id: 'latest', name: 'Latest' },                 // a row on Home
      { id: 'genres', name: 'Browse by genre', genres: ['Fantasy', 'Romance'] },
    ],
    releases: false,               // true for sources, see below
    updateUrl: 'https://…/example.js', // optional: where copies installed over plain http update from
    notice: '…',                   // optional: a warning the user must accept to install it
    settings: [                    // optional, the app draws the form
      { key: 'apiKey', label: 'API key', type: 'password', help: 'From your account page' },
      { key: 'sources', label: 'Sources', type: 'multiselect', default: ['a', 'b'],
        options: [{ value: 'a', label: 'Site A' }, { value: 'b', label: 'Site B' }] },
    ],
  },
  async catalog(catalogId, { search, genre, skip }) { return { books: [BookSummary], hasMore: false }; },
  async book(bookId) { return Book; },
  async sources(bookId, chapterId) { return { sources: [Source], message: '…' }; },
  async releases(book) { return { books: [BookSummary] }; },   // sources only
  async series(bookId) { return { books: [BookSummary] }; },  // catalogs, optional
  async resolve(resolveData) { return { url } /* or */ /* { status: 'downloading', message, progress } */; },
};
```

`BookSummary`, `Book`, `Chapter` are as in `PROTOCOL.md`. A `Source` is
`{ id, name, description?, cached?, url? , resolve? }` where `resolve` is any JSON value; the app
passes it back to `extension.resolve()` when the user plays that source.

Setting types: `text`, `password`, `toggle`, `number`, `select`, `multiselect`, `folder` (a
folder the user picks on this device and the app can write to; empty means the default).
`host.torrent` saves only in a folder the user picked in one of these.

A `notice` is shown before installing, with **I understand** and **Cancel**, and again at the
top of the settings. Once accepted, updates install quietly while the text stays the same; an
update that changes it waits: the Addons page offers **Review update**, which shows the new text
and installs only once the user accepts it.

Every catalog without `search` is a row on Home, with **See all** opening it as a grid that
pages with `skip` while `hasMore` is true. A catalog with `genres` shows as a row of genre
chips instead; the chosen genre arrives as `genre`.

## Catalogs and sources

Extensions come in two kinds, and one extension can be both:

- A **catalog** lists books and describes them. Its books may have no chapters
  (`chapters: []`): the app then treats them as catalog books and asks the sources for versions.
  Book pages can also carry `durationMinutes`, `rating` (0 to 5), `genres` and `series`.
  When a book has `series`, the app asks `series(bookId)` for the other books of the series, in
  reading order, and shows them on the page once they arrive.
- A **source** finds playable versions. It sets `releases: true` in its manifest and implements
  `releases(book)`, which gets `{ title, authors, narrators, durationMinutes, year }` and returns
  matching books (with chapters) of its own, best first. The app shows them as the catalog book's
  versions and keeps the catalog's title, cover and credits on whatever version plays. Each
  version may say how sure the match is with `match`: `"good"` (clearly this book), `"fair"`
  (probably, with a doubt) or `"poor"` (probably not). Put the reasons first in its `tags`
  ("Same narrator", "Abridged"); the app shows them. On Play, the app starts a good version,
  preferring one whose sources report `cached: true`, and falls back to the next good one if it
  fails to start; when none is good, the user picks. Versions without `match` count as good.

## Host API

| call | returns |
|---|---|
| `await host.fetch(url, options?)` | `{ status, ok, headers, text }`; never throws on HTTP errors |
| `await host.select(html, selector)` | `[{ text, html, attrs }]`, parsed by the app (fast) |
| `await host.select(html, selector, fields)` | one object per match with just the named strings: `{ title: 'h2 a', link: 'h2 a@href', paras: ['p'] }` (`@attr` reads an attribute, `[…]` returns all matches, an empty selector means the match itself). Prefer this: one parse, one round trip |
| `host.settings` | the user's settings object (defaults filled in) |
| `await host.cache.get(key)` / `await host.cache.set(key, value, seconds)` | in-memory JSON cache that outlives the engine (cleared on app restart) |
| `await host.sleep(ms)` | |
| `host.log(...)` | debug output |
| `await host.torrent.files(magnet, options?)` | `[{ index, path, size }]`, once peers have sent the torrent's description (up to 45 s) |
| `await host.torrent.stream(magnet, index, options?)` | a link on this device that plays that file while it downloads; it stops working when the app restarts its engine, so don't keep it |

`host.torrent` (Shu 0.6.0 and later; check it exists) plays torrents in the app itself, through
TorrServer running on this device. Its `options` say how to keep what is downloaded, and the
latest call's apply: `folder` (a path the user picked in one of the extension's `folder`
settings, or empty for the app's own; any other path is ignored), `deleteWhenFinished` (when
the user finishes the book or removes it from the library), `keepDays` (null keeps them),
`storageLimit` (bytes, 0 for none), `downloadLimit` and `uploadLimit` (bytes a second, 0 for
none) and `shareAfter` (keep sharing while the app is open). An extension using it should carry
a `notice`: the device connects directly to the people sharing the torrent.

`fetch` options: `method`, `headers`, `query` (object), `timeout` (ms, default 15000), and one
body: `body` (string), `json` (value), `form` (object; arrays repeat the key), or `multipart`
(object of strings).

## Lifecycle and manners

- The engine starts on first use and is shut down after a couple of idle minutes; keep state in
  `host.cache`, not in globals.
- Calls time out after 60 s.
- Be light: fetch only what the call needs, cache what you re-use, and prefer APIs to pages.

## Publishing

Host the `.js` file anywhere the app can download it (a raw GitHub link works). To offer several
extensions, or to give users one link that never changes, publish an `index.json` next to them:

```json
{
  "name": "My extensions",
  "extensions": [
    { "id": "example.audiobooks", "name": "Example", "version": "1.2.0",
      "description": "…", "url": "example/dist/example.js" }
  ]
}
```

`url` is relative to the index. The app remembers where each extension came from and checks it
once a day; raise `manifest.version` and users get the new file on their next check. An index
on the web may only link to https addresses (relative ones resolve against it). Files over 8 MB
are refused.
