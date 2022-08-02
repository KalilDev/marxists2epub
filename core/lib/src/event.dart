import 'fetch_progress.dart';
import 'scraping.dart';

abstract class BookEvent {}

class Fetch implements BookEvent {
  final Stream<FetchProgress> progress;
  final Uri uri;
  final Uri? parent;

  Fetch(this.progress, this.uri, {this.parent});
}

class FetchFailed implements BookEvent {
  final Uri uri;
  final Exception exception;

  FetchFailed(this.uri, this.exception);
}

class FetchComplete implements BookEvent {
  final Uri uri;

  FetchComplete(this.uri);
}

class Skipped implements BookEvent {
  final bool indexed;
  final Uri uri;

  Skipped(this.indexed, this.uri);
}

class Ignored implements BookEvent {
  final String reason;
  final Uri uri;
  final Uri? parent;

  Ignored(this.reason, this.uri, {this.parent});
}

class BookFetched implements BookEvent {
  BookFetched();
}

class BookContentsCreated implements BookEvent {
  BookContentsCreated();
}

class EpubCreated implements BookEvent {
  EpubCreated();
}

class IndexFetched implements BookEvent {
  final ScrapedDocument index;
  IndexFetched(this.index);
}
