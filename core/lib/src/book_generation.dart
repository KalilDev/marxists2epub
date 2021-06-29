import 'epub_exports.dart' as epub;
import 'package:tuple/tuple.dart';
import 'package:uuid/uuid.dart';

import 'navigation.dart';
import 'scraping.dart';
import 'utils.dart';
import 'package:path/path.dart' as p;

List<epub.EpubChapter> _chaptersFor(BookContents contents) {
  final chapters = _kIndexIter
      .followedBy(contents.index.documentChapterNameMap.keys)
      .map((e) => Tuple2(p.normalize(p.join(contents.indexBasePath, e)),
          contents.index.chapterNameFor(e)));
  return chapters
      .map((chapter) => epub.EpubChapter()
        ..Anchor = null
        ..SubChapters = [] // todo
        ..Title = chapter.item2
        ..ContentFileName = withContentPath(chapter.item1)
        ..HtmlContent = contents.htmls[chapter.item1].contents)
      .toList();
}

epub.EpubBook bookFrom(
  BookContents contents,
) {
  final uid = _uuid.v4();
  final navigation = _navigationFor(contents, uid);
  final navigationFile = epub.EpubTextContentFile()
    ..Content = navigationToXmlString(navigation)
    ..ContentType = epub.EpubContentType.DTBOOK_NCX
    ..ContentMimeType = kNcxMime
    ..FileName = 'toc.ncx';
  return epub.EpubBook()
    ..Author = contents.index.author
    ..AuthorList = [contents.index.author]
    ..Title = contents.index.title
    ..Chapters = _chaptersFor(contents)
    ..Content = _contentFor(
      contents,
      navigationFile,
    )
    ..Schema = (epub.EpubSchema()
      ..ContentDirectoryPath = contentPath
      ..Package = (epub.EpubPackage()
        ..Guide = _guideFor(contents)
        ..Version = epub.EpubVersion.Epub3
        ..Manifest = _manifestFor(contents, 'toc.ncx')
        ..Spine = _spineFor(contents)
        ..Metadata = _metadataFor(contents.index, uid))
      ..Navigation = navigation);
}

final _uuid = Uuid();
epub.EpubNavigation _navigationFor(BookContents contents, String uid) {
  final nav = epub.EpubNavigation();
  final navMap = epub.EpubNavigationMap()..Points = [];
  var i = 1;
  for (final doc
      in _kIndexIter.followedBy(contents.index.documentChapterNameMap.keys)) {
    final point = epub.EpubNavigationPoint()
      ..PlayOrder = (i++).toString()
      ..Id = _uuid.v4()
      ..ChildNavigationPoints = []
      ..Content = (epub.EpubNavigationContent()
        ..Source = p.normalize(p.join(contents.indexBasePath, doc)))
      ..NavigationLabels = [
        epub.EpubNavigationLabel()..Text = contents.index.chapterNameFor(doc)
      ];
    navMap.Points.add(point);
  }
  nav
    ..DocAuthors = [
      epub.EpubNavigationDocAuthor()..Authors = [contents.index.author]
    ]
    ..DocTitle =
        (epub.EpubNavigationDocTitle()..Titles = [contents.index.title])
    ..Head = (epub.EpubNavigationHead()
      ..Metadata = [
        epub.EpubNavigationHeadMeta()
          ..Content = uid
          ..Name = 'dtb:uid',
        epub.EpubNavigationHeadMeta()
          ..Content = '0'
          ..Name = 'dtb:totalPageCount',
        epub.EpubNavigationHeadMeta()
          ..Content = '0'
          ..Name = 'dtb:maxPageNumber',
        epub.EpubNavigationHeadMeta()
          ..Content = '1'
          ..Name = 'dtb:depth',
      ])
    ..NavLists = []
    ..PageList = (epub.EpubNavigationPageList()..Targets = [])
    ..NavMap = navMap;
  return nav;
}

epub.EpubMetadata _metadataFor(ScrapedIndex index, String uid) {
  final meta = epub.EpubMetadata();
  const contributorRoles = {
    'Transcription\HTML Markup': 'trc',
    'Translator': 'trl',
    'Edited/Translated': 'clb',
    'Transcription/Markup': 'trc',
    // TODO
  };
  const creatorKeys = [
    'Edited/Translated',
    // TODO
  ];
  const datesKeys = [
    'Delivered',
    'Written',
    'First Published',
    // TODO
  ];
  const copyrightsKeys = [
    'Copyright',
    // TODO
  ];
  const sourcesKeys = [
    'Source',
    'Online Version',
    // TODO
  ];
  return meta
    ..Contributors = contributorRoles.keys
        .where(index.scrapedInfo.containsKey)
        .map((e) => epub.EpubMetadataContributor()
          ..Contributor = index.scrapedInfo[e]
          ..Role = contributorRoles[e])
        .toList()
    ..Coverages = []
    ..Creators = [
      epub.EpubMetadataCreator()
        ..Creator = index.author
        ..Role = 'aut',
      ...creatorKeys
          .where(index.scrapedInfo.containsKey)
          .map((e) => epub.EpubMetadataCreator()
            ..Creator = index.scrapedInfo[e]
            ..Role = e)
    ]
    ..Dates = datesKeys
        .where(index.scrapedInfo.containsKey)
        .map((e) => epub.EpubMetadataDate()
          ..Date = index.scrapedInfo[e]
          ..Event = e)
        .toList()
    ..Formats = []
    ..Identifiers = [
      epub.EpubMetadataIdentifier()
        ..Id = 'uuid_id'
        ..Scheme = 'uuid'
        ..Identifier = uid
    ]
    ..Languages = ['en']
    ..MetaItems = []
    ..Publishers = ['Marxists.org']
    ..Relations = []
    ..Rights = copyrightsKeys
        .where(index.scrapedInfo.containsKey)
        .map((e) => index.scrapedInfo[e])
        .toList()
    ..Sources = sourcesKeys
        .where(index.scrapedInfo.containsKey)
        .map((e) => index.scrapedInfo[e])
        .toList()
    ..Subjects = ['Sociology']
    ..Titles = [index.title]
    ..Types = [];
}

epub.EpubContent _contentFor(
  BookContents contents,
  epub.EpubContentFile navigationFile,
) {
  final content = epub.EpubContent();
  content
    ..Html = contents.htmls.map((k, v) => MapEntry(
          k,
          v.toEpubContentFile(contents.indexBasePath)
              as epub.EpubTextContentFile,
        ))
    ..Css = contents.css.map((k, v) => MapEntry(
          k,
          v.toEpubContentFile(contents.indexBasePath)
              as epub.EpubTextContentFile,
        ))
    ..Images = contents.images.map((k, v) => MapEntry(
          k,
          v.toEpubContentFile(contents.indexBasePath)
              as epub.EpubByteContentFile,
        ))
    ..Fonts = {};
  content.AllFiles = {
    ...content.Html,
    ...content.Css,
    ...content.Fonts,
    ...content.Images,
    navigationFile.FileName: navigationFile
  };
  return content;
}

epub.EpubManifest _manifestFor(
  BookContents contents,
  String tocPath,
) {
  final manifest = epub.EpubManifest();
  manifest.Items.addAll(contents.allContents.map((e) => epub.EpubManifestItem()
    ..Id = e.id
    ..Href = e.path
    ..MediaType = e.mimeType));
  manifest.Items.add(epub.EpubManifestItem()
    ..Id = idFor(tocPath)
    ..Href = tocPath
    ..MediaType = kNcxMime);
  return manifest;
}

const _kIndexIter = ['index.htm'];
epub.EpubSpine _spineFor(
  BookContents contents,
) {
  final spine = epub.EpubSpine()..Items = [];
  final ids = contents.htmls.values.map((e) => e.id);
  final chapterIds = _kIndexIter
      .followedBy(
          contents.index.documentChapterNameMap.entries.map((e) => e.key))
      .map((e) => p.normalize(p.join(contents.indexBasePath, e)))
      .map(idFor)
      .toSet();
  spine.Items.addAll(ids.map(
    (e) => epub.EpubSpineItemRef()
      ..IdRef = e
      // The write logic is flipped on package:epub, the condition
      // needs to be negated for the correct behavior.
      ..IsLinear = !chapterIds.contains(e), // FIXXXX
  ));
  spine.TableOfContents = 'toc';
  return spine;
}

epub.EpubGuide _guideFor(
  BookContents contents,
) {
  final guide = epub.EpubGuide()..Items = [];
  const docNamesAndTypes = [
    Tuple2('index.htm', 'index'),
    Tuple2('preface.htm', 'preface'),
    Tuple2('intro.htm', 'text'),
    Tuple2('author.htm', 'other.author'),
  ];
  final localDocNamesAndTypes = docNamesAndTypes.map(
      (e) => e.withItem1(p.normalize(p.join(contents.indexBasePath, e.item1))));

  for (final localDt in localDocNamesAndTypes
      .where((e) => contents.htmls.containsKey(e.item1))) {
    guide.Items.add(
      epub.EpubGuideReference()
        ..Href = localDt.item1
        ..Type = localDt.item2
        ..Title = contents.index.chapterNameFor(localDt.item1),
    );
  }

  return guide;
}
