import 'dart:collection';
import 'dart:io';
import 'epub_exports.dart' as epub;
import 'package:core/src/html.dart';
import 'package:mime/mime.dart';
import 'package:mime/src/default_extension_map.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as dom_parser;
import 'package:http/http.dart';
import 'package:tuple/tuple.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import 'navigation.dart';

const String kNcxMime = 'application/x-dtbncx+xml';

extension ItE<T> on Iterable<T> {
  T get maybeSingle => isEmpty ? null : single;
}

extension StringE on String {
  String get nonEmpty => isEmpty ? null : this;
}

extension MapE<K, V> on LinkedHashMap<K, V> {
  V get(K key) => this[key];
}

// TODO. lots of heuristics
bool isPartOfTOC(dom.Element child) => true; //child.parent?.className == 'toc';

bool hasHrefSection(String href) => href.contains('#');

String withoutHrefSection(String href) {
  final i = href.indexOf('#');
  return i == -1 ? href : href.substring(0, i);
}

String startUppercased(String str) => str[0].toUpperCase() + str.substring(1);

String withoutSemicolon(String str) =>
    str[str.length - 1] == ':' ? str.substring(0, str.length - 1) : str;
const contentPath = 'OEBPS';
String withContentPath(String path) => p.join(contentPath, path);
String idFor(String href) => p.split(p.withoutExtension(href)).join('_');