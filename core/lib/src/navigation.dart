import 'epub_exports.dart';
import 'package:xml/xml.dart';

void writeNavigation(EpubNavigation navigation, XmlBuilder bdr) {
  bdr.processing('xml', "version='1.0' encoding='utf-8'");
  bdr.element('ncx', nest: () {
    bdr
      ..attribute('xmlns', 'http://www.daisy.org/z3986/2005/ncx/')
      ..attribute('version', '2005-1')
      ..attribute('xml:lang', 'pt');
    writeHead(navigation.Head, bdr);
    writeDocTitle(navigation.DocTitle, bdr);
    writeDocAuthors(navigation.DocAuthors, bdr);
    writeNavMap(navigation.NavMap, bdr);
    writePageList(navigation.PageList, bdr);
  });
}

void writeHead(EpubNavigationHead head, XmlBuilder builder) {
  if (head == null || head.Metadata == null || head.Metadata.isEmpty) {
    return;
  }
  builder.element('head', nest: () {
    for (final e in head.Metadata) {
      builder.element('meta', nest: () {
        if (e.Content != null) {
          builder..attribute('content', e.Content!);
        }
        builder
          ..attribute('name', e.Name)
          ..maybeAttribute('scheme', e.Scheme);
      });
    }
  });
}

void writeDocTitle(EpubNavigationDocTitle title, XmlBuilder builder) {
  if (title == null || title.Titles == null || title.Titles.isEmpty) {
    return;
  }
  builder.element('docTitle', nest: () {
    for (final title in title.Titles) {
      builder.element('text', nest: title);
    }
  });
}

void writeDocAuthors(
    List<EpubNavigationDocAuthor> authors, XmlBuilder builder) {
  if (authors == null || authors.isEmpty) {
    return;
  }
  for (final authorGroup in authors) {
    builder.element('docAuthor', nest: () {
      for (final author in authorGroup.Authors) {
        builder.element('text', nest: author);
      }
    });
  }
}

extension on XmlBuilder {
  void maybeAttribute(String name, Object value) {
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
      ..maybeAttribute('id', point.Id)
      ..maybeAttribute('playOrder', point.PlayOrder)
      ..maybeAttribute('class', point.Class);
    for (final label in point.NavigationLabels ?? <EpubNavigationLabel>[]) {
      if (label == null || label.Text == null) {
        continue;
      }
      builder.element('navLabel', nest: () {
        builder.element('text', nest: label.Text);
      });
    }
    if (point.Content != null) {
      builder.element('content', nest: () {
        builder
          ..maybeAttribute('id', point.Content.Id)
          ..attribute('src', point.Content.Source);
      });
    }
    for (final child in point.ChildNavigationPoints) {
      writePoint(child, builder);
    }
  });
}

void writeNavMap(EpubNavigationMap navMap, XmlBuilder builder) {
  if (navMap == null || navMap.Points == null || navMap.Points.isEmpty) {
    return;
  }
  builder.element('navMap', nest: () {
    for (final p in navMap.Points) {
      writePoint(p, builder);
    }
  });
}

void writePageList(EpubNavigationPageList pageList, XmlBuilder builder) {
  if (pageList == null || pageList.Targets.isEmpty) {
    return;
  }
  throw UnimplementedError();
}

String navigationToXmlString(EpubNavigation nav) {
  final bdr = XmlBuilder();
  writeNavigation(nav, bdr);
  return bdr.buildDocument().toXmlString(pretty: true);
}
