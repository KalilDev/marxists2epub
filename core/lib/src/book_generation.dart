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
      .map((chapter) => epub.EpubChapter(
            chapter.e0,
            withContentPath(chapter.e0),
            null,
            contents.htmls[chapter.e0]!.contents,
            [], // todo
          ))
      .toList();
}

epub.EpubBook bookFrom(
  BookContents contents,
) {
  final uid = _uuid.v4();
  final navigation = _navigationFor(contents, uid);
  final navigationFile = epub.EpubTextContentFile(
    'toc.ncx',
    epub.EpubContentType.DTBOOK_NCX,
    kNcxMime,
    navigationToXmlString(navigation),
  );

  return epub.EpubBook(
    contents.index.title,
    contents.index.author,
    [contents.index.author],
    epub.EpubSchema(
        epub.EpubPackage(
          epub.EpubVersion.Epub3,
          _metadataFor(contents.index, uid),
          _manifestFor(contents, 'toc.ncx'),
          _spineFor(contents),
          _guideFor(contents),
        ),
        navigation,
        contentPath),
    _contentFor(
      contents,
      navigationFile,
    ),
    null,
    _chaptersFor(contents),
  );
}

final _uuid = Uuid();
epub.EpubNavigation _navigationFor(BookContents contents, String uid) {
  final epub.EpubNavigationMap navMap;
  {
    var i = 1;
    navMap = epub.EpubNavigationMap([
      for (final doc in [contents.indexPath]
          .followedBy(contents.documentChapterNameMap.keys)
          .toSet())
        () {
          final point = epub.EpubNavigationPoint(
            'navPoint-${_uuid.v4()}',
            null,
            (i++).toString(),
            [epub.EpubNavigationLabel(contents.chapterNameFor(doc))],
            epub.EpubNavigationContent(
              null,
              p.normalize(p.join(contents.indexBasePath, doc)),
            ),
            [],
          );
          return point;
        }(),
    ]);
  }
  return epub.EpubNavigation(
    epub.EpubNavigationHead([
      epub.EpubNavigationHeadMeta(
        uid,
        'dtb:uid',
        null,
      ),
      epub.EpubNavigationHeadMeta(
        '0',
        'dtb:totalPageCount',
        null,
      ),
      epub.EpubNavigationHeadMeta(
        '0',
        'dtb:maxPageNumber',
        null,
      ),
      epub.EpubNavigationHeadMeta(
        '2', // should be 1, but idk what else to try to fix the pagination with.
        'dtb:depth',
        null,
      ),
    ]),
    epub.EpubNavigationDocTitle([contents.index.title]),
    [
      epub.EpubNavigationDocAuthor([contents.index.author])
    ],
    navMap,
    epub.EpubNavigationPageList([]),
    [],
  );
}

epub.EpubMetadata _metadataFor(ScrapedDocument index, String uid) {
  const contributorRoles = {
    'Transcription\\HTML Markup': 'trc',
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
  return epub.EpubMetadata(
    [index.title],
    [
      epub.EpubMetadataCreator(index.author, null, null),
      ...creatorKeys
          .where(index.scrapedInfo.containsKey)
          .map((e) => epub.EpubMetadataCreator(
                index.scrapedInfo[e]!,
                null,
                e,
              ))
    ],
    ['Sociology'],
    null,
    ['Marxists.org'],
    contributorRoles.keys
        .where(index.scrapedInfo.containsKey)
        .map(
          (e) => epub.EpubMetadataContributor(
            index.scrapedInfo[e]!,
            null,
            contributorRoles[e]!,
          ),
        )
        .toList(),
    datesKeys
        .where(index.scrapedInfo.containsKey)
        .map((e) => epub.EpubMetadataDate(
              index.scrapedInfo[e]!,
              e,
            ))
        .toList(),
    [],
    [],
    [
      epub.EpubMetadataIdentifier(
        'uuid_id',
        null,
        uid,
      )
    ],
    sourcesKeys
        .where(index.scrapedInfo.containsKey)
        .map((e) => index.scrapedInfo[e]!)
        .toList(),
    ['en'],
    [],
    [],
    copyrightsKeys
        .where(index.scrapedInfo.containsKey)
        .map((e) => index.scrapedInfo[e]!)
        .toList(),
    [],
  );
}

epub.EpubContent _contentFor(
  BookContents contents,
  epub.EpubTextContentFile navigationFile,
) {
  final content = epub.EpubContent(
    {
      ...contents.htmls.map((k, v) => MapEntry(
            k,
            v.toEpubContentFile(contents.indexBasePath)
                as epub.EpubTextContentFile,
          )),
      navigationFile.fileName: navigationFile
    },
    contents.css.map((k, v) => MapEntry(
          k,
          v.toEpubContentFile(contents.indexBasePath)
              as epub.EpubTextContentFile,
        )),
    contents.images.map((k, v) => MapEntry(
          k,
          v.toEpubContentFile(contents.indexBasePath)
              as epub.EpubByteContentFile,
        )),
    {},
  );
  return content;
}

epub.EpubManifest _manifestFor(
  BookContents contents,
  String tocPath,
) {
  final manifest = epub.EpubManifest([
    ...contents.allContents.map((e) => epub.EpubManifestItem(
              e.id,
              e.path,
              e.mimeType,
              // The rest is ignored by the writer
              '',
              '',
              '',
              '',
            )
        //..Properties = contents.navFilePath == e.path ? 'nav' : null
        ),
    epub.EpubManifestItem(
      idFor(tocPath),
      tocPath,
      kNcxMime,
      // The rest is ignored by the writer
      '',
      '',
      '',
      '',
    )
  ]);
  return manifest;
}

epub.EpubSpine _spineFor(
  BookContents contents,
) {
  final ids = contents.htmls.values.map((e) => e.id);
  final chapterIds = [contents.indexPath]
      .followedBy([contents.navFilePath])
      .followedBy(contents.documentChapterNameMap.entries.map((e) => e.key))
      .map((e) => p.normalize(p.join(contents.indexBasePath, e)))
      .map(idFor)
      .toSet();
  return epub.EpubSpine(
    'toc',
    ids
        .map((e) => epub.EpubSpineItemRef(
              e,
              chapterIds.contains(e),
            ))
        .toList(),
  );
}

epub.EpubGuide _guideFor(
  BookContents contents,
) {
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

  return epub.EpubGuide(localDocNamesAndTypes
      .where((e) => contents.htmls.containsKey(e.e0))
      .map((localDt) => epub.EpubGuideReference(
            localDt.e1,
            contents.chapterNameFor(localDt.e0),
            localDt.e0,
          ))
      .toList());
}
