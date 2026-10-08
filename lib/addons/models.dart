/// Data types shared by remote addons (docs/PROTOCOL.md) and extensions (docs/EXTENSIONS.md).
library;

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

class CatalogInfo {
  const CatalogInfo({
    required this.id,
    required this.name,
    required this.search,
    this.genres = const [],
  });

  final String id;
  final String name;

  /// Search catalogs need a query; the others are browsable lists.
  final bool search;

  /// A catalog browsed by genre: these are the genres to pick from.
  final List<String> genres;

  factory CatalogInfo.fromJson(Map<String, dynamic> json) => CatalogInfo(
    id: json['id'] as String,
    name: _string(json['name']) ?? json['id'] as String,
    search: json['search'] == true,
    genres: _strings(json['genres']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'search': search,
    if (genres.isNotEmpty) 'genres': genres,
  };
}

/// One field of an extension's settings form.
class SettingField {
  const SettingField({
    required this.key,
    required this.label,
    required this.type,
    this.help,
    this.options = const [],
    this.defaultValue,
  });

  final String key;
  final String label;

  /// text, password, toggle, number, select or multiselect.
  final String type;
  final String? help;
  final List<({String value, String label})> options;
  final Object? defaultValue;

  factory SettingField.fromJson(Map<String, dynamic> json) => SettingField(
    key: json['key'] as String,
    label: _string(json['label']) ?? json['key'] as String,
    type: _string(json['type']) ?? 'text',
    help: _string(json['help']),
    options: (json['options'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (o) => (
            value: o['value'].toString(),
            label: (o['label'] ?? o['value']).toString(),
          ),
        )
        .toList(),
    defaultValue: json['default'],
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'type': type,
    'help': help,
    'options': [
      for (final o in options) {'value': o.value, 'label': o.label},
    ],
    'default': defaultValue,
  };
}

class Manifest {
  const Manifest({
    required this.id,
    required this.name,
    required this.version,
    required this.catalogs,
    this.description,
    this.logo,
    this.configureUrl,
    this.settings = const [],
    this.releases = false,
  });

  final String id;
  final String name;
  final String version;
  final String? description;
  final String? logo;
  final String? configureUrl;
  final List<CatalogInfo> catalogs;

  /// A source: it can find playable versions of books from catalog extensions.
  final bool releases;

  /// Extension settings; remote addons configure themselves on their own page instead.
  final List<SettingField> settings;

  /// Default values of every setting, as the extension sees them before the user changes any.
  Map<String, Object?> get defaultSettings => {
    for (final f in settings) f.key: f.defaultValue,
  };

  /// An extension's manifest (no protocol field; `icon` instead of `logo`).
  factory Manifest.fromExtensionJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    if (id == null) throw const FormatException('The extension has no id.');
    return Manifest(
      id: id,
      name: _string(json['name']) ?? id,
      version: _string(json['version']) ?? '0',
      description: _string(json['description']),
      logo: _string(json['icon']) ?? _string(json['logo']),
      catalogs: (json['catalogs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CatalogInfo.fromJson)
          .toList(),
      settings: (json['settings'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SettingField.fromJson)
          .toList(),
      releases: json['releases'] == true,
    );
  }

  factory Manifest.fromJson(Map<String, dynamic> json) {
    if (json['settings'] is List && json['protocol'] == null) {
      return Manifest.fromExtensionJson(json);
    }
    if (json['protocol'] != 1) {
      throw const FormatException(
        'This is not an audiobook addon (protocol 1).',
      );
    }
    final id = _string(json['id']);
    if (id == null) {
      throw const FormatException('The addon manifest has no id.');
    }
    return Manifest(
      id: id,
      name: _string(json['name']) ?? id,
      version: _string(json['version']) ?? '?',
      description: _string(json['description']),
      logo: _string(json['logo']),
      configureUrl: _string(json['configureUrl']),
      catalogs: (json['catalogs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CatalogInfo.fromJson)
          .toList(),
      // Saved extension manifests come back through here too.
      settings: (json['settings'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SettingField.fromJson)
          .toList(),
      releases: json['releases'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'protocol': 1,
    'id': id,
    'name': name,
    'version': version,
    'description': description,
    'logo': logo,
    'configureUrl': configureUrl,
    'catalogs': catalogs.map((c) => c.toJson()).toList(),
    if (releases) 'releases': true,
    if (settings.isNotEmpty)
      'settings': settings.map((s) => s.toJson()).toList(),
  };
}

class BookSummary {
  const BookSummary({
    required this.id,
    required this.title,
    this.authors = const [],
    this.narrators = const [],
    this.cover,
    this.tags = const [],
    this.details,
  });

  final String id;
  final String title;
  final List<String> authors;
  final List<String> narrators;
  final String? cover;
  final List<String> tags;
  final String? details;

  String get byline => authors.join(', ');

  factory BookSummary.fromJson(Map<String, dynamic> json) => BookSummary(
    id: json['id'] as String,
    title: _string(json['title']) ?? 'Untitled',
    authors: _strings(json['authors']),
    narrators: _strings(json['narrators']),
    cover: _string(json['cover']),
    tags: _strings(json['tags']),
    details: _string(json['details']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'authors': authors,
    'narrators': narrators,
    'cover': cover,
    'tags': tags,
    'details': details,
  };
}

class Chapter {
  const Chapter({
    required this.id,
    required this.title,
    this.size,
    this.duration,
  });

  final String id;
  final String title;
  final int? size;

  /// Seconds, when the addon knows it.
  final int? duration;

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    id: json['id'].toString(),
    title: _string(json['title']) ?? 'Chapter',
    size: _int(json['size']),
    duration: _int(json['duration']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'size': size,
    'duration': duration,
  };
}

/// A book page. Books from catalog extensions have no chapters: they are "works", and the
/// versions that can be played come from source extensions (see [Manifest.releases]).
class Book extends BookSummary {
  const Book({
    required super.id,
    required super.title,
    super.authors,
    super.narrators,
    super.cover,
    super.tags,
    super.details,
    this.description,
    this.year,
    this.durationMinutes,
    this.rating,
    this.genres = const [],
    this.series,
    required this.chapters,
  });

  final String? description;
  final String? year;
  final int? durationMinutes;
  final double? rating;
  final List<String> genres;
  final String? series;
  final List<Chapter> chapters;

  bool get isWork => chapters.isEmpty;

  factory Book.fromJson(Map<String, dynamic> json) {
    final summary = BookSummary.fromJson(json);
    final rating = json['rating'];
    return Book(
      id: summary.id,
      title: summary.title,
      authors: summary.authors,
      narrators: summary.narrators,
      cover: summary.cover,
      tags: summary.tags,
      details: summary.details,
      description: _string(json['description']),
      year: _string(json['year']),
      durationMinutes: _int(json['durationMinutes']),
      rating: rating is num ? rating.toDouble() : null,
      genres: _strings(json['genres']),
      series: _string(json['series']),
      chapters: (json['chapters'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Chapter.fromJson)
          .toList(),
    );
  }

  /// This version (from a source extension) dressed as the catalog book it is a version of: the
  /// catalog's title, cover and credits, this version's chapters and details.
  Book withLookOf(Book work) => Book(
    id: id,
    title: work.title,
    authors: work.authors.isNotEmpty ? work.authors : authors,
    narrators: work.narrators.isNotEmpty ? work.narrators : narrators,
    cover: work.cover ?? cover,
    tags: tags,
    details: details,
    description: work.description ?? description,
    year: work.year ?? year,
    durationMinutes: work.durationMinutes,
    rating: work.rating,
    genres: work.genres,
    series: work.series,
    chapters: chapters,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'description': description,
    'year': year,
    'durationMinutes': durationMinutes,
    'rating': rating,
    if (genres.isNotEmpty) 'genres': genres,
    'series': series,
    'chapters': chapters.map((c) => c.toJson()).toList(),
  };
}

class Source {
  const Source({
    required this.id,
    required this.name,
    this.description,
    this.cached,
    this.url,
    this.resolve,
  });

  final String id;
  final String name;
  final String? description;

  /// True or false when the addon knows, null when it doesn't.
  final bool? cached;
  final String? url;

  /// What to resolve the source with: a URL for remote addons, any JSON for extensions.
  final Object? resolve;

  factory Source.fromJson(Map<String, dynamic> json) => Source(
    id: json['id'].toString(),
    name: _string(json['name']) ?? json['id'].toString(),
    description: _string(json['description']),
    cached: json['cached'] is bool ? json['cached'] as bool : null,
    url: _string(json['url']),
    resolve: json['resolve'],
  );
}

class SourceList {
  const SourceList(this.sources, this.message);

  final List<Source> sources;

  /// Why there are no sources, when the addon says.
  final String? message;

  factory SourceList.fromJson(Map<String, dynamic> json) => SourceList(
    (json['sources'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Source.fromJson)
        .where((s) => s.url != null || s.resolve != null)
        .toList(),
    _string(json['message']),
  );
}

typedef CatalogPage = ({List<BookSummary> books, bool hasMore});

CatalogPage catalogPageFromJson(Map<String, dynamic> json) => (
  books: (json['books'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(BookSummary.fromJson)
      .toList(),
  hasMore: json['hasMore'] == true,
);

/// Outcome of resolving a source: a playable URL, or "still downloading".
sealed class Resolved {
  const Resolved();
}

class Playable extends Resolved {
  const Playable(this.url);
  final String url;
}

class Downloading extends Resolved {
  const Downloading(this.message, this.progress);
  final String message;
  final double? progress;
}

/// `{url}` or `{status: 'downloading', message, progress}`; null when it is neither.
Resolved? resolvedFromJson(Map<String, dynamic> json) {
  final url = _string(json['url']);
  if (url != null) return Playable(url);
  if (json['status'] == 'downloading') {
    final progress = json['progress'];
    return Downloading(
      _string(json['message']) ?? 'Downloading…',
      progress is num ? progress.toDouble() : null,
    );
  }
  return null;
}
