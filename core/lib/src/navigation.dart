import 'epub_exports.dart';
import 'package:xml/xml.dart';

void writeNavigation(EpubNavigation navigation, XmlBuilder bdr) {
  bdr.processing('xml', "version='1.0' encoding='utf-8'");
  bdr.element('ncx', nest: () {
    bdr
      ..attribute('xmlns', 'http://www.daisy.org/z3986/2005/ncx/')
      ..attribute('version', '2005-1')
      ..attribute('xml:lang', 'pt');
    writeHead(navigation.head, bdr);
    writeDocTitle(navigation.docTitle, bdr);
    writeDocAuthors(navigation.docAuthors, bdr);
    writeNavMap(navigation.navMap, bdr);
    if (navigation.pageList != null) {
      writePageList(navigation.pageList!, bdr);
    }
  });
}

void writeHead(EpubNavigationHead head, XmlBuilder builder) {
  if (head.metadata.isEmpty) {
    return;
  }
  builder.element('head', nest: () {
    for (final e in head.metadata) {
      builder.element('meta', nest: () {
        builder.attribute('content', e.content);
        builder
          ..attribute('name', e.name)
          ..maybeAttribute('scheme', e.schema);
      });
    }
  });
}

void writeDocTitle(EpubNavigationDocTitle title, XmlBuilder builder) {
  if (title.titles.isEmpty) {
    return;
  }
  builder.element('docTitle', nest: () {
    for (final title in title.titles) {
      builder.element('text', nest: title);
    }
  });
}

void writeDocAuthors(
    List<EpubNavigationDocAuthor> authors, XmlBuilder builder) {
  if (authors.isEmpty) {
    return;
  }
  for (final authorGroup in authors) {
    builder.element('docAuthor', nest: () {
      for (final author in authorGroup.authors) {
        builder.element('text', nest: author);
      }
    });
  }
}

extension on XmlBuilder {
  void maybeAttribute(String name, Object? value) {
    if (value != null) {
      attribute(name, value);
    }
  }
}

void writePoint(EpubNavigationPoint point, XmlBuilder builder) {
  if (point == null) {
    return;
  }
  builder.element('navPoint', nest: () {
    builder
      ..maybeAttribute('id', point.id)
      ..maybeAttribute('playOrder', point.playOrder)
      ..maybeAttribute('class', point.klass);
    for (final label in point.navigationLabels) {
      builder.element('navLabel', nest: () {
        builder.element('text', nest: label.text);
      });
    }
    if (point.content != null) {
      builder.element('content', nest: () {
        builder
          ..maybeAttribute('id', point.content.id)
          ..attribute('src', point.content.source);
      });
    }
    for (final child in point.childNavigationPoints) {
      writePoint(child, builder);
    }
  });
}

void writeNavMap(EpubNavigationMap navMap, XmlBuilder builder) {
  if (navMap == null || navMap.points == null || navMap.points.isEmpty) {
    return;
  }
  builder.element('navMap', nest: () {
    for (final p in navMap.points) {
      writePoint(p, builder);
    }
  });
}

void writePageList(EpubNavigationPageList pageList, XmlBuilder builder) {
  if (pageList == null || pageList.targets.isEmpty) {
    return;
  }
  throw UnimplementedError();
}

String navigationToXmlString(EpubNavigation nav) {
  final bdr = XmlBuilder();
  writeNavigation(nav, bdr);
  return bdr.buildDocument().toXmlString(pretty: true);
}
