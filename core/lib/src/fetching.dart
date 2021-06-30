import 'package:core/src/html.dart';
import 'package:http/http.dart';
import 'package:path/path.dart' as p;

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
  if (parent.origin != child.origin) {
    return false;
  }
  return p.isWithin(p.normalize(parent.path), p.normalize(child.path));
}

Uri _uriRelativeFrom(Uri path, Uri from) {
  if (path.origin != from.origin) {
    return null;
  }
  return from.replace(path: _uriRelativePathFrom(path, from));
}

String _uriRelativePathFrom(Uri path, Uri from) {
  if (path.origin != from.origin) {
    return null;
  }
  return p.relative(
    path.path,
    from: from.path.endsWith('/') ? from.path : '${from.path}/',
  );
}

Uri _uriDirname(Uri uri) => uri.replace(path: p.dirname(uri.path) + '/');

class Context {
  final Uri baseUri;
  final Uri indexUri;
  final List<Uri> allowedSources;
  final Uri notFoundFileUri;

  Context(
    this.baseUri,
    this.indexUri,
    this.allowedSources,
    this.notFoundFileUri,
  ) {
    assert(_uriIsWithin(baseUri, indexUri));
    assert(allowedSources.every((uri) => _uriIsWithin(baseUri, uri)));
    assert(_uriIsWithin(baseUri, notFoundFileUri));
  }
  String absolutePathFor(Uri uri) =>
      _uriIsWithin(baseUri, uri) ? _uriRelativePathFrom(uri, baseUri) : null;
  bool isAllowed(Uri uri) =>
      allowedSources.any((source) => _uriIsWithin(source, uri));
}

Future<String> _scrapeFileFetchingReferred(
  String parentData,
  Uri parentUri,
  Context context,
  Map<String, DocumentContents<String>> docs,
  Set<Uri> indexedDocumentUris,
  Uri targetCssUri,
  Client client,
  int remainingDepth,
) async {
  print('Recursively scraping $parentUri');
  final parent = scapeDocument(parentData);
  for (final referred in parent.referredDocuments) {
    final referredUri = parentUri.resolve(referred);
    if (!(referredUri.isScheme('http') || referredUri.isScheme('https'))) {
      continue;
    }
    if (docs.containsKey(context.absolutePathFor(referredUri))) {
      continue;
    }
    if (indexedDocumentUris.contains(referredUri)) {
      print('Skipping indexed $referredUri');
      parent.contents = parent.contents.replaceAll(
        '"$referred"',
        '"${_uriRelativePathFrom(referredUri, parentUri)}"',
      );
      continue;
    }
    if (!_uriIsWithin(baseUri, referredUri) || remainingDepth <= 0) {
      final relativeNotFoundFilePath =
          _uriRelativePathFrom(absoluteNotFoundFile, docBaseUri);
      final message = remainingDepth <= 0
          ? 'because the depth limit was reached'
          : 'because it is outside the base';
      print('Replacing $referredUri with 404 $message');
      // Replace with 404
      parent.contents = parent.contents.replaceAll(
        '"$referred"',
        '"$relativeNotFoundFilePath"',
      );
      continue;
    }
    print('Fetching $parentUri child: $referredUri');
    var referredData = await _fetchDocAndReplaceCss(
      referredUri,
      _uriRelativePathFrom(targetCssUri, referredBaseUri),
      client,
    );
    // Insert null at the target path, so that .contains returns true for self
    docs[absolutePath] = null;
    referredData = await _scrapeFileFetchingReferred(
      referredData,
      referredUri,
      baseUri,
      docs,
      indexedDocumentUris,
      targetCssUri,
      client,
      remainingDepth - 1,
    );
    docs[absolutePath] = DocumentContents(referredData, null, absolutePath);
  }
  return parent.contents;
}

String withTrailingSlash(String other) =>
    other.endsWith('/') ? other : '$other/';

const notFoundFileName = 'fileNotFound.htm';
DocumentContents<String> notFoundFile(String indexHref) => DocumentContents(
    html404.replaceAll('{{index}}', indexHref), null, notFoundFileName);
Future<BookContents> fetchBook(
  String indexUrl,
  String baseUrl,
  int depth, [
  Client client,
]) async {
  client ??= _client;
  assert(baseUrl.endsWith('/'));
  final indexUri = Uri.parse(indexUrl);
  final indexBaseUri = _uriDirname(indexUri);
  final baseUri = Uri.parse(baseUrl);
  if (p.basename(indexUri.path) != 'index.htm') {
    throw StateError('The index url must end with `index.htm`');
  }
  if (!_uriIsWithin(baseUri, indexUri)) {
    throw StateError(
        'The index `$indexUri` is not contained in the base $baseUri!');
  }
  if (depth < 1) {
    throw StateError('The depth is invalid. The minimum allowed depth is 1');
  }

  final idx = await getAndScapeIndex(indexUri, client);

  final cssUri = indexBaseUri.resolve(idx.cssLink);

  final cssData = await _fetchAndImportCss(cssUri, client);
  final targetCssPath = _uriIsWithin(baseUri, cssUri)
      ? _uriRelativePathFrom(cssUri, baseUri)
      : p.join('stylesheets', p.basename(cssUri.path));
  final absoluteTargetCssUri = baseUri.resolve(targetCssPath);
  final cssFile = DocumentContents(cssData, null, targetCssPath);

  final absoluteNotFoundFile =
      notFoundFile(_uriRelativePathFrom(indexUri, baseUri));

  final absoluteNotFound = baseUri.resolve(absoluteNotFoundFile.path);
  idx.contents = idx.contents.replaceAll(
    '"${idx.cssLink}"',
    '"${_uriRelativePathFrom(absoluteTargetCssUri, indexBaseUri)}"',
  );
  final targetCssUri = baseUri.resolve(targetCssPath);
  final docs = <String, DocumentContents<String>>{};
  final images = <String, DocumentContents<List<int>>>{};
  final relativeIndexPath = _uriRelativePathFrom(indexUri, baseUri);
  // Set the index to null so that it is the first one in the map.
  docs[relativeIndexPath] = null;

  final referredDocumentPaths =
      idx.referredDocuments.map(indexBaseUri.resolve).toSet();
  for (final doc in idx.referredDocuments) {
    final docUri = indexBaseUri.resolve(doc);
    if (!(docUri.isScheme('http') || docUri.isScheme('https'))) {
      continue;
    }
    final docBaseUri = _uriDirname(docUri);
    if (!_uriIsWithin(baseUri, docUri)) {
      final relativeNotFoundPath =
          _uriRelativePathFrom(absoluteNotFound, indexBaseUri);
      final message = 'because it is outside the base';
      print('Replacing $docUri with 404 $message');
      // Remove the chapter and replace the url with an 404
      idx.contents =
          idx.contents.replaceAll('"$doc"', '"$relativeNotFoundPath"');
      idx.documentChapterNameMap.remove(doc);
      continue;
    }
    final relativeCssPath = _uriRelativePathFrom(targetCssUri, docBaseUri);
    print('Fetching indexed doc $docUri');
    var docData = await _fetchDocAndReplaceCss(
      docUri,
      relativeCssPath,
      client,
    );
    final relativePath = _uriRelativePathFrom(docUri, baseUri);
    // Insert null at the target path, so that .contains returns true for self
    docs[relativePath] = null;
    docData = await _scrapeFileFetchingReferred(
      docData,
      docUri,
      baseUri,
      docs,
      referredDocumentPaths,
      targetCssUri,
      client,
      depth - 1,
    );
    docs[relativePath] = DocumentContents(docData, null, relativePath);
  }
  for (final img in idx.referredImages) {
    var imgUri = indexBaseUri.resolve(img);
    print('Fetching indexed image $imgUri');
    final imgData = await _fetchBytes(imgUri);

    if (!_uriIsWithin(baseUri, imgUri)) {
      imgUri = baseUri.resolve(p.join('images', imgUri.pathSegments.join('_')));
    }

    final relativeFromIndex = _uriRelativePathFrom(imgUri, indexBaseUri);
    idx.contents = idx.contents.replaceAll('"$img"', '"$relativeFromIndex"');
    images[relativeFromIndex] =
        DocumentContents(imgData, null, relativeFromIndex);
  }
  // Set the actual document contents. This cant be done earlier because the
  // contents string was modified.
  docs[relativeIndexPath] = DocumentContents(
    idx.contents,
    null,
    relativeIndexPath,
  );
  print('Book contents fetched!');
  return BookContents(
    docs..[absoluteNotFoundFile.path] = absoluteNotFoundFile,
    images,
    {cssFile.path: cssFile},
    idx,
    _uriRelativePathFrom(indexBaseUri, baseUri),
  );
}
