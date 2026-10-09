# Remote addon protocol (v1)

Most sources should be extensions (see EXTENSIONS.md), which run inside the app. A remote addon
is the alternative for sources that need a server: an HTTP service the app talks to.

The app installs an addon from its manifest URL; everything else is relative to the **base
URL**, which is the manifest URL without the trailing `/manifest.json`. Addons may keep user
settings in the base URL (an encoded config segment, for example), so the app treats it as
opaque and secret.

All responses are JSON (`application/json`) and must allow CORS (`Access-Control-Allow-Origin: *`).
Errors are any non-2xx status with `{ "error": "message" }`.

## `GET {base}/manifest.json`

```json
{
  "protocol": 1,
  "id": "org.example.library",
  "name": "Example Library",
  "version": "0.2.0",
  "description": "…",
  "logo": "https://…/logo.svg",
  "configureUrl": "https://…/configure",
  "catalogs": [
    { "id": "search", "name": "Search", "search": true },
    { "id": "latest", "name": "Latest audiobooks" }
  ]
}
```

- `catalogs[].search: true` means the catalog needs a `search` query and is used by the player's
  search screen. Other catalogs are browsable lists shown on the home screen.
- `configureUrl` (optional) is opened in a browser; it gives the user a new manifest URL to
  install.

## `GET {base}/catalog/{catalogId}.json?search={text}&skip={n}`

```json
{ "books": [BookSummary], "hasMore": true }
```

`skip` is the number of books the player already has; `hasMore` says whether to ask again.

**BookSummary**

| field | type | |
|---|---|---|
| `id` | string | unique within the addon; URL-encode it in paths |
| `title` | string | |
| `authors` | string[] | optional |
| `narrators` | string[] | optional |
| `cover` | URL | optional |
| `tags` | string[] | optional, short labels such as `M4B`, `128 kbps` |
| `details` | string | optional, one line such as `12 h 5 min · Unabridged · Example Library` |

## `GET {base}/book/{bookId}.json`

```json
{ "book": Book }
```

**Book** is a BookSummary plus:

| field | type | |
|---|---|---|
| `description` | string | optional, plain text with newlines |
| `year` | string | optional |
| `chapters` | Chapter[] | in listening order, at least one |

**Chapter**: `{ "id": string, "title": string, "size": bytes?, "duration": seconds?, "file": string?, "start": seconds? }`

Chapters inside one audio file (an M4B) share a `file` key and give their `start` in that file.
The app opens the file once and seeks between them; their sources return the same link. Leave
both out for a chapter that is a file of its own.

## `GET {base}/sources/{bookId}/{chapterId}.json`

```json
{
  "sources": [
    { "id": "main", "name": "Main server", "description": "…", "cached": true, "resolve": "https://…" }
  ],
  "message": "optional text to show when there are no sources"
}
```

Each source has either `url` (directly playable) or `resolve`. `cached` is `true`, `false`
or absent (unknown). The player remembers which source `id` the user picked for a book and uses
it for the following chapters.

## `GET {resolve}`

- `200 { "url": "https://…" }`: play this URL (it may redirect; it may expire after hours).
- `202 { "status": "downloading", "message": "Preparing the file: 42%", "progress": 0.42 }`: not ready;
  the player shows the message and may retry later.
- Errors as above.
