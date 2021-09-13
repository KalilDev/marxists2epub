import 'dart:developer';

import 'package:core/src/html.dart';
import 'package:core/src/utils.dart';
import 'package:http/http.dart';
import 'package:path/path.dart' as p;
import 'package:meta/meta.dart';
import 'package:tuple/tuple.dart';
import 'scraping.dart';

final _client = Client();
Future<String> _fetchDocument(dynamic uri, Client client) =>
    client.get(_uriFromUriOrString(uri)).then((r) => r.body);

Future<ScrapedDocument> getAndScapeIndex(dynamic index, Client client) =>
    _fetchDocument(index, client).then(scapeDocument);

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

final _cssStylesheetStatementRegex = RegExp(
    r'<link\s+rel="stylesheet"\s+type="text\/css"\s+href="(.*)"\s*(:?\/|)>');
Future<String> _fetchDocAndReplaceCss(
        dynamic uri, String targetCssPath, Client client) =>
    _fetchDocument(uri, client) //
        .then(
      (contents) => contents.replaceAll(
        _cssStylesheetStatementRegex,
        '<link rel="stylesheet" type="text/css" href="$targetCssPath">',
      ),
    );

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
  final Uri indexUri;
  final Map<String, DocumentContents<String>> docs;
  final Map<String, DocumentContents<List<int>>> images;
  final Client client;
  final Set<String> _normalizedIndexedKeys;
  final Set<Uri> _normalizedAllowedSources;
  final Uri _normalizedCssUri;
  final Uri _normalizedNotFoundFileUri;
  final Uri _normalizedBaseUri;

  static Uri normalizeUri(Uri uri) =>
      uriOutsideOfArchiveOrg(uri.replace(scheme: 'https').normalizePath());

  Context._(
    this.baseUri,
    this.indexUri,
    this.docs,
    this.images,
    this.client,
    this._normalizedIndexedKeys,
    this._normalizedAllowedSources,
    this._normalizedCssUri,
    this._normalizedNotFoundFileUri,
    this._normalizedBaseUri,
  ) {
    final normalizedIndexUri = normalizeUri(indexUri);
    assert(_uriIsWithin(_normalizedBaseUri, normalizedIndexUri));
    assert(_normalizedAllowedSources.every((uri) =>
        _uriIsWithin(_normalizedBaseUri, uri) || uri == _normalizedBaseUri));
    assert(_uriIsWithin(_normalizedBaseUri, _normalizedNotFoundFileUri));
  }
  factory Context(
    Uri baseUri,
    Uri indexUri,
    List<Uri> allowedSources,
    Uri notFoundFileUri,
    Uri cssUri,
    Set<Uri> indexedUris,
    Map<String, DocumentContents<String>> docs,
    Map<String, DocumentContents<List<int>>> images,
    Client client,
  ) {
    final normalizedBase = normalizeUri(baseUri);
    return Context._(
      baseUri,
      indexUri,
      docs,
      images,
      client,
      indexedUris
          .map(normalizeUri)
          .where((e) => _uriIsWithin(normalizedBase, e))
          .map((e) =>
              _pathKeyFor(e, isImage: false, normalizedBaseUri: normalizedBase))
          .toSet(),
      allowedSources.map(normalizeUri).toSet(),
      normalizeUri(cssUri),
      normalizeUri(notFoundFileUri),
      normalizeUri(baseUri),
    );
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
      p.extension(uri.path) == '.htm' && _isInAllowedSources(normalizeUri(uri));
  bool isImageAllowed(Uri uri) => p.extension(uri.path) != '.gif';

  String relativePathTo(Uri uri, {Uri from}) => _uriRelativePathFrom(
      normalizeUri(uri), _uriDirname(normalizeUri(from) ?? _normalizedBaseUri));

  bool containsDoc(Uri docUri) =>
      docs.containsKey(pathKeyFor(docUri)) || containsIndexed(docUri);

  String cssPathRelativeFrom(Uri uri) =>
      relativePathTo(_normalizedCssUri, from: normalizeUri(uri));

  String notFoundPathRelativeFrom(Uri uri) =>
      relativePathTo(_normalizedNotFoundFileUri, from: normalizeUri(uri));

  void insertDocPlaceholderAt(Uri docUri) {
    final key = pathKeyFor(docUri);
    if (docs.containsKey(key)) {
      throw StateError(
          'Cannot insert an placeholder at $key because there is an doc there already!');
    }
    docs[key] = null;
  }

  String insertImage(
    List<int> contents, {
    @required Uri at,
  }) {
    final key = pathKeyFor(at);
    if (images[key] != null) {
      throw StateError(
        'Tried inserting an image at $key with '
        'contents but it already exists!',
      );
    }
    images[key] = DocumentContents(contents, null, key);
    return key;
  }

  void replaceDocPlaceholderWith(
    String contents, {
    @required Uri at,
  }) {
    final key = pathKeyFor(at);
    if (!docs.containsKey(key)) {
      throw StateError('Cannot replace an inexistent placeholder at $key!');
    }
    if (docs[key] != null) {
      throw StateError(
          'Tried replacing an placeholder at $key with contents but there are'
          ' contents already there!');
    }
    docs[key] = DocumentContents(contents, null, key);
  }

  bool containsIndexed(Uri uri) =>
      _normalizedIndexedKeys.contains(pathKeyFor(uri));
}

Future<String> _scrapeFileFetchingReferred(
  String parentData,
  Uri parentUri,
  Context context,
  int remainingDepth,
) async {
  print('Recursively scraping $parentUri');
  final parent = scapeDocument(parentData);
  if (parent.document.getElementsByTagName('title').maybeSingle?.text?.trim() ==
      'Wayback Machine') {
    return parentData;
  }
  for (final referred in parent.referredDocuments) {
    final referredUri = parentUri.resolve(referred);
    debugger(
        when: referredUri ==
            Uri.parse(
                'https://web.archive.org/web/20210227093737/https://www.marxists.org/glossary/c.htm'));
    if (!(referredUri.isScheme('http') || referredUri.isScheme('https'))) {
      continue;
    }
    if (context.containsDoc(referredUri)) {
      final verb = context.containsIndexed(referredUri) ? 'indexed' : 'visited';
      print('Skipping $verb $referredUri');
      parent.contents = parent.contents.replaceAll(
        '"$referred"',
        '"${_uriRelativePathFrom(referredUri, parentUri)}"',
      );
      continue;
    }
    if (!context.isDocumentAllowed(referredUri) || remainingDepth <= 0) {
      final relativeNotFoundFilePath =
          context.notFoundPathRelativeFrom(referredUri);
      final message = remainingDepth <= 0
          ? 'because the depth limit was reached'
          : 'because it is not allowed';
      print('Replacing $referredUri with 404 $message');
      // Replace with 404
      parent.contents = parent.contents.replaceAll(
        '"$referred',
        '"$relativeNotFoundFilePath',
      );
      continue;
    }
    print('Fetching $parentUri child: $referredUri');
    var referredData = await _fetchDocAndReplaceCss(
      referredUri,
      context.cssPathRelativeFrom(referredUri),
      context.client,
    );
    // Insert null at the target path, so that .contains returns true for self
    context.insertDocPlaceholderAt(referredUri);
    referredData = await _scrapeFileFetchingReferred(
      referredData,
      referredUri,
      context,
      remainingDepth - 1,
    );
    context.replaceDocPlaceholderWith(referredData, at: referredUri);
  }
  return parent.contents;
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

const notFoundFileName = 'fileNotFound.htm';
DocumentContents<String> notFoundFile(String indexHref) => DocumentContents(
    html404.replaceAll('{{index}}', indexHref), null, notFoundFileName);
Future<BookContents> fetchBook(
  String indexUrl,
  Iterable<String> baseUrls,
  int depth, [
  Client client,
]) async {
  client ??= _client;
  assert(baseUrls.every((url) => url.endsWith('/')));
  final indexUri = Uri.parse(indexUrl);
  final indexBaseUri = _uriDirname(indexUri);
  final baseUris = baseUrls.map((e) => Uri.parse(e)).toList();
  final rootUri = shallowest(baseUris);
  if (p.basename(indexUri.path) != 'index.htm') {
    throw StateError('The index url must end with `index.htm`');
  }
  if (!_uriIsWithin(rootUri, indexUri)) {
    throw StateError(
        'The index `$indexUri` is not contained in the base $rootUri!');
  }
  if (depth < 1) {
    throw StateError('The depth is invalid. The minimum allowed depth is 1');
  }

  final idx = await getAndScapeIndex(indexUri, client);

  final cssUri = indexBaseUri.resolve(idx.cssLink);

  final cssData = await _fetchAndImportCss(cssUri, client);
  final targetCssPath = _uriIsWithin(rootUri, cssUri)
      ? _uriRelativePathFrom(cssUri, rootUri)
      : p.join('stylesheets', p.basename(cssUri.path));
  final targetCssUri = rootUri.resolve(targetCssPath);
  final cssFile = DocumentContents(cssData, null, targetCssPath);

  final absoluteNotFoundFile =
      notFoundFile(_uriRelativePathFrom(indexUri, rootUri));

  final notFoundUri = rootUri.resolve(absoluteNotFoundFile.path);
  idx.contents = idx.contents.replaceAll(
    '"${idx.cssLink}"',
    '"${_uriRelativePathFrom(targetCssUri, indexBaseUri)}"',
  );
  final docs = <String, DocumentContents<String>>{};
  final images = <String, DocumentContents<List<int>>>{};
  final referredDocumentUris =
      idx.referredDocuments.map(indexBaseUri.resolve).toSet();
  final context = Context(
    rootUri,
    indexUri,
    baseUris,
    notFoundUri,
    targetCssUri,
    referredDocumentUris,
    docs,
    images,
    client,
  );

  // Set the index placeholder first so that it is the first one in the map.
  context.insertDocPlaceholderAt(indexUri);

  for (final doc in idx.referredDocuments) {
    final docUri = indexBaseUri.resolve(doc);
    if (!(docUri.isScheme('http') || docUri.isScheme('https'))) {
      continue;
    }
    if (!context.isDocumentAllowed(docUri)) {
      final relativeNotFoundPath = context.notFoundPathRelativeFrom(docUri);
      final message = 'because it is outside the base';
      print('Replacing $docUri with 404 $message');
      // Remove the chapter and replace the url with an 404
      idx.contents = idx.contents.replaceAll('"$doc', '"$relativeNotFoundPath');
      idx.documentChapterNameMap.remove(doc);
      continue;
    }
    final relativeCssPath = context.cssPathRelativeFrom(docUri);
    print('Fetching indexed doc $docUri');
    var docData = await _fetchDocAndReplaceCss(
      docUri,
      relativeCssPath,
      client,
    );
    context.insertDocPlaceholderAt(docUri);
    docData = await _scrapeFileFetchingReferred(
      docData,
      docUri,
      context,
      depth - 1,
    );
    context.replaceDocPlaceholderWith(docData, at: docUri);
  }
  for (final img in idx.referredImages) {
    var imgUri = indexBaseUri.resolve(img);
    if (!context.isImageAllowed(imgUri)) {
      continue;
    }
    print('Fetching indexed image $imgUri');
    final imgData = await _fetchBytes(imgUri);
    final targetLocation = context.insertImage(imgData, at: imgUri);
    idx.contents = idx.contents.replaceAll('"$img"', '"$targetLocation"');
  }
  // Set the actual document contents. This cant be done earlier because the
  // contents string was modified.
  context.replaceDocPlaceholderWith(idx.contents, at: indexUri);
  print('Book contents fetched!');
  return BookContents(
    docs..[absoluteNotFoundFile.path] = absoluteNotFoundFile,
    images,
    {cssFile.path: cssFile},
    idx,
    _uriRelativePathFrom(indexBaseUri, rootUri),
  );
}
