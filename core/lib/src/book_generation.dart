import 'epub_exports.dart' as epub;
import 'package:utils/utils.dart';
import 'package:uuid/uuid.dart';

import 'navigation.dart';
import 'scraping.dart';
import 'utils.dart';
import 'package:path/path.dart' as p;

List<epub.EpubChapter> _chaptersFor(BookContents contents) {
  final chapters = [contents.indexPath]
      .followedBy(contents.documentChapterNameMap.keys)
      .toSet()
      .map((e) => Tuple2(p.normalize(p.join(contents.indexBasePath, e)),
          contents.chapterNameFor(e)));
  return chapters
      .map((chapter) => epub.EpubChapter()
        ..Anchor = null
        ..SubChapters = [] // todo
        ..Title = chapter.e0
        ..ContentFileName = withContentPath(chapter.e0)
        ..HtmlContent = contents.htmls[chapter.e0]!.contents)
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
  final navMap = epub.EpubNavigationMap();
  var i = 1;
  for (final doc in [contents.indexPath]
      .followedBy(contents.documentChapterNameMap.keys)
      .toSet()) {
    final point = epub.EpubNavigationPoint()
      ..PlayOrder = (i++).toString()
      ..Id = 'navPoint-${_uuid.v4()}'
      ..Content = (epub.EpubNavigationContent()
        ..Source = p.normalize(p.join(contents.indexBasePath, doc)))
      ..NavigationLabels.addAll(
          [epub.EpubNavigationLabel()..Text = contents.chapterNameFor(doc)]);
    navMap.Points.add(point);
  }
  nav
    ..DocAuthors.addAll([
      epub.EpubNavigationDocAuthor()..Authors.addAll([contents.index.author])
    ])
    ..DocTitle =
        (epub.EpubNavigationDocTitle()..Titles.addAll([contents.index.title]))
    ..Head = (epub.EpubNavigationHead()
      ..Metadata.addAll([
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
          ..Content =
              '2' // should be 1, but idk what else to try to fix the pagination with.
          ..Name = 'dtb:depth',
      ]))
    ..NavLists.addAll([])
    ..PageList = (epub.EpubNavigationPageList()..Targets.addAll([]))
    ..NavMap = navMap;
  return nav;
}

epub.EpubMetadata _metadataFor(ScrapedDocument index, String uid) {
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
    ..Contributors.addAll(contributorRoles.keys
        .where(index.scrapedInfo.containsKey)
        .map((e) => epub.EpubMetadataContributor()
          ..Contributor = index.scrapedInfo[e]!
          ..Role = contributorRoles[e]!))
    ..Creators.addAll([
      epub.EpubMetadataCreator()..Creator = index.author,
      ...creatorKeys
          .where(index.scrapedInfo.containsKey)
          .map((e) => epub.EpubMetadataCreator()
            ..Creator = index.scrapedInfo[e]!
            ..Role = e)
    ])
    ..Dates.addAll(datesKeys
        .where(index.scrapedInfo.containsKey)
        .map((e) => epub.EpubMetadataDate()
          ..Date = index.scrapedInfo[e]!
          ..Event = e))
    ..Identifiers.addAll([
      epub.EpubMetadataIdentifier()
        ..Id = 'uuid_id'
        ..Identifier = uid
    ])
    ..Languages.addAll(['en'])
    ..Publishers.addAll(['Marxists.org'])
    ..Rights.addAll(copyrightsKeys
        .where(index.scrapedInfo.containsKey)
        .map((e) => index.scrapedInfo[e]!))
    ..Sources.addAll(sourcesKeys
        .where(index.scrapedInfo.containsKey)
        .map((e) => index.scrapedInfo[e]!))
    ..Subjects.addAll(['Sociology'])
    ..Titles.addAll([index.title]);
}

epub.EpubContent _contentFor(
  BookContents contents,
  epub.EpubContentFile navigationFile,
) {
  final content = epub.EpubContent();
  content
    ..Html.addAll(contents.htmls.map((k, v) => MapEntry(
          k,
          v.toEpubContentFile(contents.indexBasePath)
              as epub.EpubTextContentFile,
        )))
    ..Css.addAll(contents.css.map((k, v) => MapEntry(
          k,
          v.toEpubContentFile(contents.indexBasePath)
              as epub.EpubTextContentFile,
        )))
    ..Images.addAll(contents.images.map((k, v) => MapEntry(
          k,
          v.toEpubContentFile(contents.indexBasePath)
              as epub.EpubByteContentFile,
        )));
  content.AllFiles.addAll({
    ...content.Html,
    ...content.Css,
    ...content.Fonts,
    ...content.Images,
    navigationFile.FileName!: navigationFile
  });
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
        ..MediaType = e.mimeType

      //..Properties = contents.navFilePath == e.path ? 'nav' : null
      ));
  manifest.Items.add(epub.EpubManifestItem()
    ..Id = idFor(tocPath)
    ..Href = tocPath
    ..MediaType = kNcxMime);
  return manifest;
}

epub.EpubSpine _spineFor(
  BookContents contents,
) {
  final spine = epub.EpubSpine();
  final ids = contents.htmls.values.map((e) => e.id);
  final chapterIds = [contents.indexPath]
      .followedBy([contents.navFilePath])
      .followedBy(contents.documentChapterNameMap.entries.map((e) => e.key))
      .map((e) => p.normalize(p.join(contents.indexBasePath, e)))
      .map(idFor)
      .toSet();
  spine.Items.addAll(ids.map((e) => epub.EpubSpineItemRef()
        ..IdRef = e
        // The write logic is flipped on package:epub, the condition
        // needs to be negated for the correct behavior.
        ..IsLinear =
            !chapterIds.contains(e) //!chapterIds.contains(e), // FIXXXX
      ));
  spine.TableOfContents = 'toc';
  return spine;
}

epub.EpubGuide _guideFor(
  BookContents contents,
) {
  final guide = epub.EpubGuide();
  const docNamesAndTypes = [
    Tuple2('index.htm', 'index'),
    Tuple2('preface.htm', 'preface'),
    Tuple2('intro.htm', 'text'),
    Tuple2('author.htm', 'other.author'),
    Tuple2('index.xhtml', 'index'),
    Tuple2('preface.xhtml', 'preface'),
    Tuple2('intro.xhtml', 'text'),
    Tuple2('author.xhtml', 'other.author'),
  ];
  final localDocNamesAndTypes = docNamesAndTypes.map(
      (e) => Tuple2(p.normalize(p.join(contents.indexBasePath, e.e0)), e.e1));

  for (final localDt
      in localDocNamesAndTypes.where((e) => contents.htmls.containsKey(e.e0))) {
    guide.Items.add(
      epub.EpubGuideReference()
        ..Href = localDt.e0
        ..Type = localDt.e1
        ..Title = contents.chapterNameFor(localDt.e0),
    );
  }

  return guide;
}
