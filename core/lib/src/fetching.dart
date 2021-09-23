import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/src/html.dart';
import 'package:html/dom.dart' as dom;
import 'package:core/src/utils.dart';
import 'package:http/http.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:meta/meta.dart';
import 'package:tuple/tuple.dart';
import 'event.dart';
import 'fetch_progress.dart';
import 'scraping.dart';
import 'package:synchronized/synchronized.dart';

final _client = Client();
Future<String> _fetchDocument(
  dynamic uri,
  Client client,
  Sink<FetchProgress> progress,
) =>
    client.get(_uriFromUriOrString(uri)).then((r) => r.body);
Future<Uint8List> _fetchImage(
  dynamic uri,
  Client client,
  Sink<FetchProgress> progress,
) =>
    client.get(_uriFromUriOrString(uri)).then((r) => r.bodyBytes);

Future<ScrapedDocument> getAndScapeIndex(
  dynamic index,
  Client client,
  Sink<FetchProgress> progress,
) =>
    _fetchDocument(index, client, progress)
        .then((doc) => scapeDocument(_uriFromUriOrString(index), doc));

final _quoteGroup = '\[\"\'\]\*';
final _urlFnStart = '(?:url\\($_quoteGroup|)';
final _urlFnEnd = '$_quoteGroup\\);';
final _importRegexTemplate =
    '@import ' '$_urlFnStart{{urlContent}}(?:$_urlFnEnd|;)';

RegExp importRegexFor(String url) =>
    RegExp(_importRegexTemplate.replaceAll('{{urlContent}}', url));
final capturingImportRegex =
    RegExp(_importRegexTemplate.replaceAll('{{urlContent}}', '(.*?)'));

Uri _uriFromUriOrString(dynamic uriOrString) =>
    uriOrString is Uri ? uriOrString : Uri.parse(uriOrString as String);

/// Fetch an css resource from [css], find @import statements inside it and
/// fetch the imported resources, resolving the statements.
Future<String> _fetchAndImportCss(dynamic css, Client client) async {
  final uri = _uriFromUriOrString(css);
  var contents = await client.get(uri).then((r) => r.body);
  for (final imported in capturingImportRegex.allMatches(contents).toSet()) {
    final importedUrl = imported.group(1);
    final joint = uri.resolve(importedUrl);
    final importedCss = await _fetchAndImportCss(joint, client);
    contents = contents.replaceAll(importRegexFor(importedUrl), importedCss);
  }
  return contents;
}

Future<List<int>> _fetchBytes(dynamic uri) =>
    _client.get(_uriFromUriOrString(uri)).then((r) => r.bodyBytes);

bool _uriIsWithin(Uri parent, Uri child) {
  if (parent.host != child.host) {
    return false;
  }
  return p.isWithin(p.normalize(parent.path), p.normalize(child.path));
}

Uri _uriRelativeFrom(Uri path, Uri from) {
  if (path.host != from.host) {
    return null;
  }
  return from.replace(path: _uriRelativePathFrom(path, from));
}

String _uriRelativePathFrom(Uri path, Uri from) {
  if (path.host != from.host) {
    return null;
  }
  return p.relative(
    path.path,
    from: from.path.endsWith('/') ? from.path : '${from.path}/',
  );
}

Uri _uriDirname(Uri uri) =>
    uri.path.endsWith('/') ? uri : uri.replace(path: p.dirname(uri.path) + '/');

class Context {
  final Uri baseUri;
  final ScrapedDocument index;
  Uri get indexUri => index.sourceUri;
  final Map<String, ScrapedDocument> docs;
  final Map<String, DocumentContents<List<int>>> images;
  final Client client;
  final Set<String> _normalizedIndexedKeys;
  final Set<Uri> _normalizedAllowedSources;
  final Uri _normalizedCssUri;
  final bool _stripCss;

  final DocumentContents<String> _cssFile;
  final Map<Uri, Lock> _uriLockMap = {};

  DocumentContents<String> __notFoundFile;
  DocumentContents<String> get _notFoundFile => __notFoundFile ??= notFoundFile(
      p.setExtension(_uriRelativePathFrom(indexUri, baseUri), '.xhtml'));

  Uri __normalizedNotFoundFileUri;
  Uri get _normalizedNotFoundFileUri => __normalizedNotFoundFileUri ??=
      normalizeUri(baseUri.resolve(_notFoundFile.path));

  final Uri _normalizedBaseUri;

  final Map<Uri, Uri> _replacements = {};
  final Map<Uri, Uri> _maybeReplacements = {};
  final Map<String, String> _chapters;

  static Uri normalizeUri(Uri uri) =>
      uriOutsideOfArchiveOrg(uri.replace(scheme: 'https').normalizePath());
  final Sink<BookEvent> _eventSink;

  void addEvent(BookEvent e) => _eventSink?.add(e);

  Context._(
    this.baseUri,
    this.index,
    this.docs,
    this.images,
    this.client,
    this._chapters,
    this._cssFile,
    this._normalizedIndexedKeys,
    this._normalizedAllowedSources,
    this._normalizedCssUri,
    this._normalizedBaseUri,
    this._eventSink,
    this._stripCss,
  ) {
    final normalizedIndexUri = normalizeUri(indexUri);
    assert(_uriIsWithin(_normalizedBaseUri, normalizedIndexUri));
    assert(_normalizedAllowedSources.every((uri) =>
        _uriIsWithin(_normalizedBaseUri, uri) || uri == _normalizedBaseUri));
    assert(_uriIsWithin(_normalizedBaseUri, _normalizedNotFoundFileUri));
  }
  factory Context(
    Uri baseUri,
    ScrapedDocument index,
    List<Uri> allowedSources,
    DocumentContents<String> css,
    Set<Uri> indexedUris,
    Map<String, String> chapters,
    Client client,
    Sink<BookEvent> eventSink,
    bool stripCss,
  ) {
    final normalizedBase = normalizeUri(baseUri);
    final cssUri = index.sourceUri.resolve(index.cssLink);
    final targetCssUri = baseUri.resolve(css.path);
    final context = Context._(
      baseUri,
      index,
      {},
      {},
      client,
      chapters,
      css,
      indexedUris
          .map(normalizeUri)
          .where((e) => _uriIsWithin(normalizedBase, e))
          .map((e) =>
              _pathKeyFor(e, isImage: false, normalizedBaseUri: normalizedBase))
          .toSet(),
      allowedSources.map(normalizeUri).toSet(),
      normalizeUri(targetCssUri),
      normalizeUri(baseUri),
      eventSink,
      stripCss,
    );
    context.addReplacement(
      cssUri,
      targetCssUri,
    );
    return context;
  }

  String pathKeyFor(Uri uri, {bool isImage = false}) => _pathKeyFor(
        uri,
        isImage: isImage,
        normalizedBaseUri: _normalizedBaseUri,
      );

  static String _pathKeyFor(Uri uri,
      {bool isImage = false, Uri normalizedBaseUri}) {
    uri = normalizeUri(uri);
    if (!_uriIsWithin(normalizedBaseUri, uri)) {
      uri = normalizedBaseUri.resolve(p.join(
        isImage ? 'images' : 'external',
        uri.pathSegments.join('_'),
      ));
    }
    return _uriRelativePathFrom(uri, normalizedBaseUri);
  }

  bool _isInAllowedSources(Uri normalizedUri) => _normalizedAllowedSources
      .any((source) => _uriIsWithin(source, normalizedUri));

  bool isDocumentAllowed(Uri uri) =>
      p.extension(uri.path) == '.htm' &&
      _isInAllowedSources(normalizeUri(uri)) &&
      (uri.isScheme('http') || uri.isScheme('https'));
  bool isImageAllowed(Uri uri) => p.extension(uri.path) != '.gif';

  String relativePathTo(Uri uri, {Uri from}) => _uriRelativePathFrom(
      normalizeUri(uri), _uriDirname(normalizeUri(from) ?? _normalizedBaseUri));

  bool containsDoc(Uri docUri) =>
      docs.containsKey(pathKeyFor(docUri)) || containsIndexed(docUri);
  bool containsImage(Uri imgUri) =>
      images.containsKey(pathKeyFor(imgUri, isImage: true));

  String cssPathRelativeFrom(Uri uri) =>
      relativePathTo(_normalizedCssUri, from: normalizeUri(uri));

  String notFoundPathRelativeFrom(Uri uri) =>
      relativePathTo(_normalizedNotFoundFileUri, from: normalizeUri(uri));

  void insertDoc(ScrapedDocument doc) {
    final key = pathKeyFor(doc.sourceUri);
    if (docs.containsKey(key)) {
      throw StateError(
          'Cannot insert at $key because there is an doc there already!');
    }
    docs[key] = doc;
    _maybeReplacements.remove(normalizeUri(doc.sourceUri));
  }

  void insertImage(
    List<int> contents, {
    @required Uri at,
  }) {
    final key = pathKeyFor(at, isImage: true);
    if (images[key] != null) {
      throw StateError(
        'Tried inserting an image at $key with '
        'contents but it already exists!',
      );
    }
    images[key] = DocumentContents(contents, null, key);
  }

  Uri getUriOrReplacement(Uri uri) {
    uri = normalizeUri(uri);
    return _replacements[uri] ?? _maybeReplacements[uri] ?? uri;
  }

  void maybeAddReplacement(Uri sourceUri, [Uri targetUri]) {
    sourceUri = normalizeUri(sourceUri);
    if (_replacements[sourceUri] != null) {
      return;
    }
    if (containsDoc(sourceUri) || containsImage(sourceUri)) {
      return;
    }
    final target = targetUri == null
        ? _normalizedNotFoundFileUri
        : normalizeUri(targetUri);
    final old = _maybeReplacements[sourceUri];
    if (old != null && old != target) {
      throw StateError('');
    }
    _maybeReplacements[sourceUri] = target;
  }

  void addReplacement(Uri sourceUri, [Uri targetUri]) {
    sourceUri = normalizeUri(sourceUri);
    final target = targetUri == null
        ? _normalizedNotFoundFileUri
        : normalizeUri(targetUri);
    final old = _replacements[sourceUri];
    if (old != null && old != target) {
      throw StateError('');
    }
    _replacements[sourceUri] = target;
  }

  bool containsIndexed(Uri uri) =>
      _normalizedIndexedKeys.contains(pathKeyFor(uri));
  void removeChapter(String name) => _chapters.remove(name);
  Map<String, DocumentContents<String>> buildDocs() {
    // Replace every doc with it as an .xhtml document
    for (final e in docs.entries.toList()) {
      final path = e.key;
      final doc = e.value;
      final ext = p.extension(path);
      if (ext != '.htm') {
        continue;
      }
      final newPath = p.setExtension(path, '.xhtml');
      if (docs.containsKey(newPath)) {
        continue;
      }
      docs.remove(path);
      docs[newPath] = doc;
      addReplacement(baseUri.resolve(path), baseUri.resolve(newPath));
    }

    for (final doc in docs.values) {
      final uri = doc.sourceUri;
      doc.document
          .getElementsByTagName('link')
          .where(hasStylesheetRel)
          .forEach((e) {
        e.attributes['href'] = cssPathRelativeFrom(uri);
      });
      doc.document.getElementsByTagName('a').where(hasHref).forEach((e) {
        final sections = hrefSections(e.attributes['href']);
        final href = sections.item1;
        var hrefUri = getUriOrReplacement(uri.resolve(href));
        hrefUri = baseUri.resolve(pathKeyFor(hrefUri));
        final targetPath = _uriRelativePathFrom(hrefUri, uri.resolve('.'));
        final target = [
          targetPath,
          if (hrefUri != _normalizedNotFoundFileUri) ...sections.item2
        ].join('#');
        e.attributes['href'] = target;
      });

      doc.document.getElementsByTagName('img').where(hasSrc).forEach((e) {
        final src = e.attributes['src'];
        var srcUri = getUriOrReplacement(uri.resolve(src));
        srcUri = baseUri.resolve(pathKeyFor(srcUri, isImage: true));
        if (srcUri == _normalizedNotFoundFileUri) {
          e.remove();
          return;
        }
        final targetPath = _uriRelativePathFrom(srcUri, uri.resolve('.'));
        e.attributes['src'] = targetPath;
      });
      if (_stripCss) {
        doc.document
            .getElementsByTagName('link')
            .where(hasStylesheetRel)
            .forEach((e) {
          e.remove();
        });
      }
      fixupHtml(doc.document);
    }

    return docs.map((key, doc) => MapEntry(key,
        DocumentContents(fixHtmlContent(doc.document.outerHtml), null, key)))
      ..[_notFoundFile.path] = _notFoundFile;
  }

  Map<String, String> buildChapters() {
    final chapters = Map<String, String>.from(_chapters);
    chapters.removeWhere((k, v) {
      final docUri = indexUri.resolve(k);
      return !isDocumentAllowed(docUri) || docs.containsKey(docUri);
    });
    return chapters.map((k, v) {
      var uri = getUriOrReplacement(indexUri.resolve(k));
      final path = pathKeyFor(uri);

      return MapEntry(path, v);
    });
  }

  String indexPath() => pathKeyFor(getUriOrReplacement(indexUri));
  static DocumentContents<String> buildNavFile(
      Map<String, String> chapters, String title, String cssPath) {
    final bdr = XmlBuilder();
    bdr.element('html', attributes: {
      'xmlns': 'http://www.w3.org/1999/xhtml',
      'xmlns:epub': 'http://www.idpf.org/2007/ops',
    }, nest: () {
      bdr.element('head', nest: () {
        bdr.element('title', nest: title);
        bdr.element('link', attributes: {'rel': 'stylesheet', 'href': cssPath});
      });
      bdr.element('body', nest: () {
        bdr.element('nav', attributes: {'epub:type': 'toc'}, nest: () {
          bdr.element('h1', nest: 'Índice');
          bdr.element('ol', nest: () {
            for (final chapter in chapters.entries) {
              final name = chapter.value;
              final path = chapter.key;
              bdr.element('li', nest: () {
                bdr.element('a', attributes: {'href': path}, nest: name);
              });
            }
          });
        });
      });
    });
    const name = 'navFile.xhtml';
    return DocumentContents(bdr.build().toXmlString(pretty: true), null, name);
  }

  BookContents buildContents(Uri indexBaseUri) {
    final docs = buildDocs();
    final chapters = buildChapters();
    final navFile = buildNavFile(
        chapters, index.title, cssPathRelativeFrom(baseUri.resolve('.')));
    return BookContents(
        docs,
        images,
        {
          if (!_stripCss) _cssFile.path: _cssFile,
          navFile.path: navFile,
        },
        index,
        _uriRelativePathFrom(indexBaseUri, baseUri),
        chapters,
        indexPath(),
        navFile.path);
  }

  Lock lockFor(Uri uri) =>
      _uriLockMap.putIfAbsent(normalizeUri(uri), () => Lock());
}

Future<void> _scrapeFileFetchingReferred(
  ScrapedDocument parent,
  Context context,
  int remainingDepth,
) async {
  final parentUri = parent.sourceUri;
  // idk what should happen? it shouldnt have been fetched?
  if (parent.document.getElementsByTagName('title').maybeSingle?.text?.trim() ==
      'Wayback Machine') {
    return;
  }
  for (final referred in remainingDepth <= 0 ? [] : parent.referredDocuments) {
    final referredUri = parentUri.resolve(referred);
    if (context.containsDoc(referredUri)) {
      final indexed = context.containsIndexed(referredUri);
      // If we arent at the index, skip the indexed and otherwise books
      if (!(parent == context.index && indexed)) {
        context.addEvent(Skipped(indexed, referredUri));
        continue;
      }
    }
    if (!context.isDocumentAllowed(referredUri) || remainingDepth <= 0) {
      final reason = remainingDepth <= 0
          ? 'because the depth limit was reached'
          : 'because it is not allowed';
      // Maybe replace with 404
      context.maybeAddReplacement(referredUri);
      context.addEvent(Ignored(reason, referredUri));
      // If we are at the first level, the doc was in the index, so it is an
      // chapter that may be removed.
      if (parent == context.index) {
        context.removeChapter(referred);
      }
      continue;
    }
    final fetchController = StreamController<FetchProgress>();
    context.addEvent(Fetch(
      fetchController.stream,
      referredUri,
      parent: parentUri,
    ));

    var referredDoc = await _fetchDocument(
      referredUri,
      context.client,
      fetchController.sink,
    ).then((data) => scapeDocument(referredUri, data));

    context.addEvent(FetchComplete(referredUri));
    await fetchController.close();

    context.insertDoc(referredDoc);
    await _scrapeFileFetchingReferred(
      referredDoc,
      context,
      remainingDepth - 1,
    );
  }

  for (final img in parent.referredImages) {
    var imgUri = parentUri.resolve(img);
    if (!context.isImageAllowed(imgUri)) {
      context.addReplacement(imgUri);
      continue;
    }
    if (context.containsImage(imgUri)) {
      continue;
    }
    final fetchController = StreamController<FetchProgress>();
    context.addEvent(Fetch(
      fetchController.stream,
      imgUri,
      parent: parentUri,
    ));

    var imgData = await _fetchImage(
      imgUri,
      context.client,
      fetchController.sink,
    );

    context.addEvent(FetchComplete(imgUri));
    context.insertImage(imgData, at: imgUri);
  }

  return;
}

Iterable<Tuple2<A, B>> _zip<A, B>(Iterable<A> a, Iterable<B> b) sync* {
  final ia = a.iterator, ib = b.iterator;
  while (ia.moveNext() && ib.moveNext()) {
    yield Tuple2(ia.current, ib.current);
  }
}

String withTrailingSlash(String other) =>
    other.endsWith('/') ? other : '$other/';
Uri shallowest(Iterable<Uri> uris) {
  List<String> shallowestFor(List<String> a, List<String> b) => _zip(a, b)
      .takeWhile((e) => e.item1 == e.item2)
      .map((e) => e.item1)
      .toList();
  final shallowestPath = uris.fold<List<String>>(
      null,
      (acc, e) =>
          acc == null ? e.pathSegments : shallowestFor(acc, e.pathSegments));
  return uris.last.replace(pathSegments: shallowestPath);
}

const notFoundFileName = 'fileNotFound.xhtml';
DocumentContents<String> notFoundFile(String indexHref) => DocumentContents(
    html404.replaceAll('{{index}}', indexHref), null, notFoundFileName);

abstract class _ImageOrDocumentRequest {}

class _Image extends _ImageOrDocumentRequest {
  final Uri imageUri;
  final Uri parentUri;

  _Image(this.imageUri, this.parentUri);
}

class _Document extends _ImageOrDocumentRequest {
  final Uri docUri;
  final Uri parentUri;
  final int remainingDepth;

  _Document(this.docUri, this.parentUri, this.remainingDepth);
}

Future<void> _fetchReferred(
  ScrapedDocument index,
  Context context,
  int depth,
  bool parallel,
  bool images,
) async {
  final reqQueue = Queue<_ImageOrDocumentRequest>();
  // Perform the search for referred documents and images in the [doc].
  //
  // It reads the context and makes changes which can be done atomically, so
  // this is thread safe.
  void visitScraped(ScrapedDocument doc, int remainingDepth,
      [bool isIndex = false]) {
    // idk what should happen? it shouldnt have been fetched?
    if (doc.document.getElementsByTagName('title').maybeSingle?.text?.trim() ==
        'Wayback Machine') {
      return;
    }
    for (final ref in doc.referredDocuments) {
      final refUri = doc.sourceUri.resolve(ref);
      if (!context.isDocumentAllowed(refUri) || remainingDepth <= 0) {
        final reason = remainingDepth <= 0
            ? 'because the depth limit was reached'
            : 'because it is not allowed';
        // Maybe replace with 404. This can be performed atomically, as it has
        // no permanent effect
        context.maybeAddReplacement(refUri);
        context.addEvent(Ignored(reason, refUri));
        // If we are at the first level, the doc was in the index, so it is an
        // chapter that may be removed.
        if (isIndex) {
          context.removeChapter(ref);
        }
        continue;
      }
      reqQueue.add(_Document(refUri, doc.sourceUri, remainingDepth - 1));
    }

    for (final img in doc.referredImages) {
      var imgUri = doc.sourceUri.resolve(img);
      if (!context.isImageAllowed(imgUri)) {
        context.addReplacement(imgUri);
        continue;
      }
      reqQueue.add(_Image(imgUri, doc.sourceUri));
    }
  }

  Future<void> processSingle(_ImageOrDocumentRequest req) async {
    if (req is _Image) {
      if (!images) {
        context.addEvent(Ignored('Images are not allowed', req.imageUri));
        context.addReplacement(req.imageUri);
        return;
      }
      final lock = context.lockFor(req.imageUri);
      await lock.synchronized(() async {
        if (context.containsImage(req.imageUri)) {
          return;
        }

        final fetchController = StreamController<FetchProgress>();
        context.addEvent(Fetch(
          fetchController.stream,
          req.imageUri,
          parent: req.parentUri,
        ));

        try {
          var imgData = await _fetchImage(
            req.imageUri,
            context.client,
            fetchController.sink,
          );

          context.addEvent(FetchComplete(req.imageUri));
          context.insertImage(imgData, at: req.imageUri);
        } on Exception catch (e) {
          context.addEvent(FetchFailed(req.imageUri, e));
          // If another doc mentions this image, it may succeed on the other
          // try, therefore it is an maybe replacement.
          context.maybeAddReplacement(req.imageUri);
        } finally {
          await fetchController.close();
        }
      });
    }
    if (req is _Document) {
      final lock = context.lockFor(req.docUri);
      await lock.synchronized(() async {
        if (context.containsDoc(req.docUri)) {
          final indexed = context.containsIndexed(req.docUri);
          // If we arent at the index, skip the indexed and otherwise books
          if (!(req.parentUri == index.sourceUri && indexed)) {
            context.addEvent(Skipped(indexed, req.docUri));
            return;
          }
        }

        final fetchController = StreamController<FetchProgress>();
        context.addEvent(Fetch(
          fetchController.stream,
          req.docUri,
          parent: req.parentUri,
        ));
        try {
          var referredDoc = await _fetchDocument(
            req.docUri,
            context.client,
            fetchController.sink,
          ).then((data) => scapeDocument(req.docUri, data));

          context.addEvent(FetchComplete(req.docUri));

          context.insertDoc(referredDoc);
          visitScraped(referredDoc, req.remainingDepth);
        } on Exception catch (e) {
          context.addEvent(FetchFailed(req.docUri, e));
          // If another doc mentions this doc, it may succeed on the next
          // try, therefore it is an maybe replacement.
          context.maybeAddReplacement(req.docUri);
        } finally {
          await fetchController.close();
        }
      });
    }
  }

  // Kickoff the queue with the index.
  visitScraped(index, depth + 1);
  while (reqQueue.isNotEmpty) {
    if (parallel) {
      final allReqs = reqQueue.toList();
      reqQueue.clear();
      await Future.wait(allReqs.map(processSingle));
    } else {
      final req = reqQueue.removeFirst();
      await processSingle(req);
    }
  }
}

Future<BookContents> fetchBook(
  String indexUrl,
  Iterable<String> baseUrls,
  int depth,
  Sink<BookEvent> eventSink, [
  Client client,
  bool parallel = false,
  bool images = true,
  bool stripCss = false,
]) async {
  client ??= _client;
  assert(baseUrls.every((url) => url.endsWith('/')));
  final indexUri = Uri.parse(indexUrl);
  final indexBaseUri = _uriDirname(indexUri);
  final baseUris = baseUrls.map((e) => Uri.parse(e)).toList();
  final rootUri = shallowest(baseUris);
  /*if (p.basename(indexUri.path) != 'index.htm') {
    throw StateError('The index url must end with `index.htm`');
  }*/
  if (!_uriIsWithin(rootUri, indexUri)) {
    throw StateError(
        'The index `$indexUri` is not contained in the base $rootUri!');
  }
  if (depth < 1) {
    throw StateError('The depth is invalid. The minimum allowed depth is 1');
  }

  final indexFetchController = StreamController<FetchProgress>();
  eventSink.add(Fetch(indexFetchController.stream, indexUri));

  final idx = await getAndScapeIndex(
    indexUri,
    client,
    indexFetchController.sink,
  );

  eventSink.add(FetchComplete(indexUri));
  await indexFetchController.close();
  eventSink.add(IndexFetched(idx));

  final cssUri = indexBaseUri.resolve(idx.cssLink);

  final cssData = await _fetchAndImportCss(cssUri, client);
  final targetCssPath = _uriIsWithin(rootUri, cssUri)
      ? _uriRelativePathFrom(cssUri, rootUri)
      : p.join('stylesheets', p.basename(cssUri.path));
  final cssFile = DocumentContents(cssData, null, targetCssPath);

  final referredDocumentUris =
      idx.referredDocuments.map(indexBaseUri.resolve).toSet();
  final context = Context(
    rootUri,
    idx,
    baseUris,
    cssFile,
    referredDocumentUris,
    idx.documentChapterNameMap,
    client,
    eventSink,
    stripCss,
  );
  // Set the index first so that it is the first one in the ordered map.
  context.insertDoc(idx);
  await _fetchReferred(idx, context, depth, parallel, images);
  //await _scrapeFileFetchingReferred(idx, context, depth + 1);
  // Build the book with the context
  context.addEvent(BookFetched());
  final book = context.buildContents(indexBaseUri);
  context.addEvent(BookContentsCreated());
  return book;
}
