import 'dart:collection';
import 'dart:developer';
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

const String kNcxMime = 'application/x-dtbncx+xml';

extension ItE<T> on Iterable<T> {
  T? get maybeSingle => length != 1 ? null : single;
}

extension StringE on String {
  String? get nonEmpty => isEmpty ? null : this;
}

extension MapE<K, V> on LinkedHashMap<K, V> {
  V? get(K key) => this[key];
}

// TODO. lots of heuristics
bool isPartOfTOC(dom.Element child) => true; //child.parent?.className == 'toc';

bool hasHrefSection(String href) => href.contains('#');

String withoutHrefSection(String href) {
  final i = href.indexOf('#');
  return i == -1 ? href : href.substring(0, i);
}

Tuple2<String, List<String>> hrefSections(String href) {
  final refs = href.split('#');
  return Tuple2(refs[0], refs.skip(1).toList());
}

String startUppercased(String str) => str[0].toUpperCase() + str.substring(1);

String withoutSemicolon(String str) =>
    str[str.length - 1] == ':' ? str.substring(0, str.length - 1) : str;
const contentPath = 'OEBPS';
String withContentPath(String path) => p.join(contentPath, path);
String idFor(String href) => p.split(p.withoutExtension(href)).join('_');
bool hasStylesheetRel(dom.Element e) => e.attributes['rel'] == 'stylesheet';
bool hasHref(dom.Element e) => e.attributes.containsKey('href');
bool hasSrc(dom.Element e) => e.attributes.containsKey('src');
Iterable<dom.Element> allElements(dom.Document doc) sync* {
  yield* doc.children;
  yield* doc.children.expand(allChildren);
}

Iterable<dom.Element> allChildren(dom.Element parent) sync* {
  yield* parent.children;
  yield* parent.children.expand(allChildren);
}

final _numbersRegex = RegExp('[0-9]+');
Uri _removeArchiveFrom(Uri uri) {
  final components = uri.pathSegments;
  final dateComponent = components[1];
  if (components[0] != 'web' || !_numbersRegex.hasMatch(dateComponent)) {
    throw StateError('Invalid web archive uri: $uri');
  }
  final targetUrl = uri.path.substring(
    uri.path.indexOf(dateComponent) + dateComponent.length + 1,
  );
  return Uri.parse(targetUrl);
}

Uri uriOutsideOfArchiveOrg(Uri uri) =>
    uri.host == 'web.archive.org' ? _removeArchiveFrom(uri) : uri;

void fixupHtml(dom.Document doc) {
  const disallowedAttributes = {
    'table': {'width'},
    'td': {'width'},
    'img': {'align', 'hspace', 'vspace'},
  };
  const attributeReplacements = {
    'img': {'border': '0'},
  };
  if (doc.nodes.first is dom.DocumentType) {
    doc.nodes.first.remove();
  }
  if (doc.nodes.first is! dom.Comment) {
    doc.nodes.insert(0, dom.Comment(r'?xml version="1.0" encoding="UTF-8"?'));
  } else {
    (doc.nodes.first as dom.Comment).data =
        r'?xml version="1.0" encoding="UTF-8"?';
  }
  doc.nodes.insert(0, dom.DocumentType("html", null, null));

  final html = doc.children.first;
  if (html.localName != 'html') {
    throw StateError('Invalid Document');
  }
  html.getElementsByTagName('meta').forEach((meta) {
    final attrs = meta.attributes;
    if (!attrs.containsKey("http-equiv")) {
      return;
    }
    if (attrs['http-equiv']?.toLowerCase() != 'content-type') {
      return;
    }
    attrs['content'] = 'text/html; charset=utf-8';
  });
  html.attributes['xmlns'] = 'http://www.w3.org/1999/xhtml';

  allElements(doc).forEach((e) {
    final attrs = e.attributes;
    final eDisallowedAttrs = disallowedAttributes[e.localName];
    final eAttrReplacements = attributeReplacements[e.localName];
    if (eDisallowedAttrs != null) {
      attrs.removeWhere(
        (attr, _) => eDisallowedAttrs.contains(attr),
      );
    }
    if (eAttrReplacements != null) {
      attrs.keys
          .where(eAttrReplacements.containsKey)
          .forEach((attr) => e.attributes[attr] = eAttrReplacements[attr]!);
    }
  });
}

final _entityRegex = RegExp(r'(&[a-z]+?;)');
String fixHtmlContent(String text) {
  const entityReplacements = {'nbsp': r'&#160;'};
  return text.splitMapJoin(_entityRegex,
      onMatch: (m) => entityReplacements[m.group(1)] ?? '');
}
