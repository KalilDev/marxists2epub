import 'dart:collection';
import 'dart:io';
import 'epub_exports.dart' as epub;
import 'package:core/src/html.dart';
import 'package:mime/mime.dart';
import 'package:mime/src/default_extension_map.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as dom_parser;
import 'package:http/http.dart';
import 'package:utils/utils.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import 'navigation.dart';
import 'utils.dart';

class BookContents {
  final Map<String, DocumentContents<String>> htmls;
  final Map<String, DocumentContents<List<int>>> images;
  final Map<String, DocumentContents<String>> css;
  final ScrapedDocument index;
  final String indexBasePath;
  final String indexPath;
  final Map<String, String> documentChapterNameMap;
  final String navFilePath;

  Iterable<DocumentContents<Object>> get allContents => htmls.values
      .cast<DocumentContents<Object>>()
      .followedBy(images.values)
      .followedBy(css.values);

  String chapterNameFor(String document) =>
      documentChapterNameMap[document] ??
      (p.basenameWithoutExtension(document) == 'index'
          ? 'Índice'
          : startUppercased(idFor(document)));

  BookContents(
    this.htmls,
    this.images,
    this.css,
    this.index,
    this.indexBasePath,
    this.documentChapterNameMap,
    this.indexPath,
    this.navFilePath,
  );
}

class DocumentContents<T> {
  final T contents;
  String? _mimeType;
  final String path;

  DocumentContents(
    this.contents,
    String? mimeType,
    this.path,
  ) : _mimeType = mimeType;
  String _computeMimeType() {
    if (contents is List<int>) {
      return lookupMimeType(path,
          headerBytes: (contents as List<int>)
              .take(defaultMagicNumbersMaxLength)
              .toList())!;
    }
    if (contents is String) {
      return p.extension(path) == '.htm'
          ? defaultExtensionMap['xhtml']!
          : lookupMimeType(path)!;
    }
    throw TypeError();
  }

  epub.EpubContentFile toEpubContentFile(String basePath) {
    final path = p.normalize(p.join(basePath, this.path));
    if (contents is List<int>) {
      return epub.EpubByteContentFile(
        path,
        contentType,
        mimeType,
        contents as List<int>,
      );
    }
    if (contents is String) {
      return epub.EpubTextContentFile(
        path,
        contentType,
        mimeType,
        contents as String,
      );
    }
    throw TypeError();
  }

  epub.EpubContentType get contentType {
    switch (mimeType) {
      case 'application/xhtml+xml':
        return epub.EpubContentType.XHTML_1_1;
      case 'text/css':
        return epub.EpubContentType.CSS;
      case 'application/x-dtbook+xml':
        return epub.EpubContentType.DTBOOK;
      case 'application/x-font-otf':
        return epub.EpubContentType.FONT_OPENTYPE;
      case 'application/x-font-ttf':
        return epub.EpubContentType.FONT_TRUETYPE;
      case 'image/gif':
        return epub.EpubContentType.IMAGE_GIF;
      case 'image/jpeg':
        return epub.EpubContentType.IMAGE_JPEG;
      case 'image/png':
        return epub.EpubContentType.IMAGE_PNG;
      case 'image/svg+xml':
        return epub.EpubContentType.IMAGE_SVG;
      case 'application/xml':
        return epub.EpubContentType.XML;
      case 'TODO':
        return epub.EpubContentType.DTBOOK_NCX; // TODO
      case 'TODO':
        return epub.EpubContentType.OEB1_CSS; // TODO
      case 'TODO':
        return epub.EpubContentType.OEB1_DOCUMENT; // TODO
      default:
        return mimeType.endsWith('+xml')
            ? epub.EpubContentType.XML
            : epub.EpubContentType.OTHER;
    }
  }

  String get id => idFor(path);

  String get mimeType =>
      ArgumentError.checkNotNull(_mimeType ??= _computeMimeType());
}

class ScrapedDocument {
  final Uri sourceUri;
  final dom.Document document;
  final String _contents;

  static final headerRegex = RegExp(r'h\d+');
  String? _title;
  String get title => _title ??= (document.body?.children
          .skip(1)
          .map((e) => e.text)
          .takeWhile(headerRegex.hasMatch)
          .join(' ')
          .trim()
          .nonEmpty ??
      document.getElementsByTagName('title').maybeSingle?.text ??
      'Unknown Title');

  String? _author;
  String get author => _author ??= document
          .getElementsByTagName('meta')
          .where((e) => e.attributes['name'] == 'author')
          .maybeSingle
          ?.attributes
          .get('content') ??
      document.body?.children.first.text ??
      'Unknown Author';

  static Iterable<MapEntry<String, String>> _parseInfo(dom.Element info) sync* {
    for (var i = 0; i < info.nodes.length; i++) {
      final node = info.nodes[i];
      if (node is! dom.Element) {
        continue;
      }
      final element = info.nodes[i] as dom.Element;
      if (element.localName != 'span' ||
          element.attributes['class'] != 'info') {
        continue;
      }
      final attribute = element.text;
      final valAcc = StringBuffer();
      loop:
      for (i++; i < info.nodes.length; i++) {
        final node = info.nodes[i];
        if (node is! dom.Element) {
          valAcc.write(node.text);
          continue;
        }
        switch (node.localName) {
          case 'br':
            valAcc.writeln();
            break;
          case 'span':
            if (node.attributes['class'] == 'info') {
              i--;
              break loop;
            }
            valAcc.write(node.innerHtml);
            break;
          default:
            valAcc.write(node.innerHtml);
            break;
        }
      }
      yield MapEntry(attribute, valAcc.toString());
    }
  }

  Map<String, String> _scrapeInfo() {
    final infos = document
        .getElementsByTagName('p')
        .where((e) => e.attributes['class'] == 'information');
    final result = infos.expand(_parseInfo);
    return Map.fromEntries(result);
  }

  Map<String, String>? _scrapedInfo;
  Map<String, String> get scrapedInfo => _scrapedInfo ??= _scrapeInfo();

  ScrapedDocument(
    this.sourceUri,
    this.document,
    this._contents,
  );
  String? _cssLink;

  /// Find the single css link. Throws if there aren't any or there are
  /// more than one
  // uses an bogus one
  String get cssLink => _cssLink ??= document
          .getElementsByTagName('link')
          .where((e) => e.attributes['rel'] == 'stylesheet')
          .where(hasHref)
          .map((e) => e.attributes['href'])
          .maybeSingle ??
      'style.css';

  Map<String, String>? _documentChapterNameMap;

  /// Scrape the anchors and find the chapters. Only valid for some index.htm
  /// documents
  Map<String, String> get documentChapterNameMap =>
      _documentChapterNameMap ??= Map.fromEntries(document
          .getElementsByTagName('a')
          .where(hasHref)
          .where((e) => !hasHrefSection(e.attributes['href']!))
          .where(isPartOfTOC)
          .map((e) => MapEntry(e.attributes['href']!, e.text)));
  Set<String>? _referredDocuments;

  /// Scrape the anchors.
  Set<String> get referredDocuments => _referredDocuments ??= document
      .getElementsByTagName('a')
      .where(hasHref)
      .map((e) => e.attributes['href']!)
      .map(withoutHrefSection)
      .toSet();

  Set<String>? _referredImages;

  /// Scrape the img elements
  Set<String> get referredImages => _referredImages ??= document
      .getElementsByTagName('img')
      .map((e) => e.attributes['src'])
      .where((e) => e != null)
      .cast<String>()
      .toSet();
}

ScrapedDocument scapeDocument(Uri sourceUri, String contents) {
  if (contents.contains('WAYBACK TOOLBAR INSERT')) {
    const jsStart = '<script src="//archive.org/includes/';
    const jsEnd = '<!-- End Wayback Rewrite JS Include -->';
    const toolbarStart = '<!-- BEGIN WAYBACK TOOLBAR INSERT -->';
    const toolbarEnd = '<!-- END WAYBACK TOOLBAR INSERT -->';
    contents = contents.substring(0, contents.indexOf(jsStart)) +
        contents.substring(
          contents.indexOf(jsEnd) + jsEnd.length,
          contents.indexOf(toolbarStart),
        ) +
        contents.substring(contents.indexOf(toolbarEnd) + toolbarEnd.length);
  }
  final index = dom_parser.parse(contents);
  return ScrapedDocument(
    sourceUri,
    index,
    contents,
  );
}
