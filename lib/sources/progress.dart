import '../addons/models.dart';

/// A place in a book: the chapter, and the position in that chapter's audio file.
typedef BookPlace = ({int chapterIndex, Duration position});

/// Where a server says the user is in a book.
typedef RemoteProgress = ({BookPlace place, bool finished, DateTime updatedAt});

/// Time from the start of the whole book to [place].
///
/// shortcut: chapter lengths are whole seconds, so a book of many files can be off by a few
/// seconds; keep exact file lengths in [Chapter] if that ever shows.
Duration bookTime(Book book, BookPlace place) {
  final here = book.chapters[place.chapterIndex];
  var seconds = 0;
  for (final c in book.chapters.take(place.chapterIndex)) {
    if (!c.sharesFileWith(here)) seconds += c.duration ?? 0;
  }
  return Duration(seconds: seconds) + place.position;
}

/// The place [time] from the start of [book]: the inverse of [bookTime].
BookPlace placeAt(Book book, Duration time) {
  final chapters = book.chapters;
  var fileStart = Duration.zero;
  var i = 0;
  while (i < chapters.length) {
    // Chapters i to j - 1 play from one file.
    var j = i + 1;
    while (j < chapters.length && chapters[j].sharesFileWith(chapters[i])) {
      j++;
    }
    final length = Duration(
      seconds: chapters
          .sublist(i, j)
          .fold(0, (sum, c) => sum + (c.duration ?? 0)),
    );
    if (time < fileStart + length || j == chapters.length) {
      var inFile = time - fileStart;
      if (inFile.isNegative) inFile = Duration.zero;
      var chapter = i;
      for (var k = i; k < j; k++) {
        if ((chapters[k].start ?? Duration.zero) <= inFile) chapter = k;
      }
      return (chapterIndex: chapter, position: inFile);
    }
    fileStart += length;
    i = j;
  }
  return (chapterIndex: 0, position: Duration.zero);
}

/// The whole book's length, as far as its chapters tell.
Duration bookLength(Book book) => Duration(
  seconds: book.chapters.fold(0, (sum, c) => sum + (c.duration ?? 0)),
);
