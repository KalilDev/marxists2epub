import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:core/src/client.dart';
import 'package:epub/epub.dart';
import 'package:args/args.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:path/path.dart' as p;
import 'package:utils/utils.dart';

class LogPreferences {
  final bool showSkipped;
  final bool showFetch;
  final bool showIgnored;

  LogPreferences(this.showSkipped, this.showFetch, this.showIgnored);
}

void Function(BookEvent e) _onEvent(LogPreferences p) {
  final fetches = <Uri, Tuple3<Uri?, FetchProgress?, StreamSubscription>>{};
  void log(Object o) {
    print(o);
  }

  void Function(FetchProgress) _onFetchProgress(Uri uri) => (e) {
        fetches[uri] = Tuple3(fetches[uri]!.e0, e, fetches[uri]!.e2);
      };

  return (e) {
    if (e is Fetch) {
      final subs = e.progress.listen(_onFetchProgress(e.uri));
      fetches[e.uri] = Tuple3(e.parent, null, subs);
    }
    if (e is FetchComplete) {
      final state = fetches.remove(e.uri);
      state!.e2.cancel();
      print('FETCHED: ${e.uri}');
    }
    if (e is FetchFailed) {
      final state = fetches.remove(e.uri);
      state!.e2.cancel();
      print('FAILED : ${e.uri}: ${e.exception}');
    }
    if (e is Skipped) {
      if (!p.showSkipped) {
        return;
      }
      log('SKIP   : ${e.indexed ? '[indexed]' : '[fetched]'}: ${e.uri}');
    }
    if (e is Ignored) {
      if (!p.showIgnored) {
        return;
      }
      log('IGNORE : ${e.reason}: ${e.uri}'
          '${e.parent != null ? ' <- ${e.parent}' : ''}');
    }
    if (e is BookFetched) {
      log('COMPLETE: The book fetching is complete!');
    }
    if (e is BookContentsCreated) {
      log('CONTENT: The book content information was created');
    }
    if (e is IndexFetched) {
      log('META   : The index was fetched and the metadata was scraped');
    }
    if (e is EpubCreated) {
      log('EPUB   : The book contents were transformed into an EPUB');
    }
  };
}

class GlobalSettings {
  final File? cssOverride;
  final int? rateLimit;
  final LogPreferences logPrefs;
  final String? outputFolder;
  final bool parallel;
  final bool images;
  final bool stripCss;

  GlobalSettings(
    this.cssOverride,
    this.rateLimit,
    this.logPrefs,
    this.outputFolder,
    this.parallel,
    this.images,
    this.stripCss,
  );
}

class SingleRequest {
  final GlobalSettings settings;
  final String url;
  final String? output;
  final List<String> baseUrls;
  final int depth;

  SingleRequest(
      this.settings, this.url, this.output, this.baseUrls, this.depth);
}

Future<int> main(List<String> args) async {
  args = args.toList();
  assert(() {
    args = [
      'https://www.marxists.org/archive/lenin/works/1916/imp-hsc',
      '-S',
      '-F',
      '-I',
      '-P',
    ];
    return true;
  }());
  final globalParser = ArgParser()
    ..addOption(
      'cssOverride',
      abbr: 's',
      help: 'The file which will be used to override the style sheets',
    )
    ..addOption(
      'rateLimit',
      abbr: 'l',
      help: 'The interval between requests',
    )
    ..addOption('outputFolder', abbr: 'O', help: 'The output folder')
    ..addFlag('logSkipped', abbr: 'S', defaultsTo: false)
    ..addFlag('showFetch', abbr: 'F', defaultsTo: true)
    ..addFlag('logIgnored', abbr: 'I', defaultsTo: false)
    ..addFlag('parallel', abbr: 'P', defaultsTo: false)
    ..addFlag('images', abbr: 'G', defaultsTo: true)
    ..addFlag('stripCss', abbr: 'T', defaultsTo: false)
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Display this menu',
    );

  final singleParser = ArgParser()
    ..addOption(
      'output',
      abbr: 'o',
      help: 'The output epub file',
    )
    ..addMultiOption(
      'baseUrl',
      abbr: 'b',
      help: 'The base urls for the documents which can be downloaded.',
    )
    ..addOption(
      'depth',
      abbr: 'd',
      help: 'The recursion depth for downloading documents',
      defaultsTo: '1',
    );

  final results = globalParser.parse(args);
  if (results['help']) {
    print(globalParser.usage);
    print(singleParser.usage);
    return 0;
  }
  final rateLimit = results['rateLimit'] == null
      ? null
      : int.tryParse(results['rateLimit'] as String);
  final cssOverride = results['cssOverride'] as String?;
  final logPrefs = LogPreferences(
    results['logSkipped'] as bool,
    results['showFetch'] as bool,
    results['logIgnored'] as bool,
  );
  final globalPrefs = GlobalSettings(
    cssOverride == null ? null : File(cssOverride),
    rateLimit,
    logPrefs,
    results['outputFolder'],
    results['parallel'],
    results['images'],
    results['stripCss'],
  );

  final requests = divideRequests(results.rest).map(singleParser.parse).map(
    (e) {
      var url = e.rest.single;
      url = p.extension(url) == '.htm' ? url : p.join(url, 'index.htm');
      return SingleRequest(
          globalPrefs,
          url,
          e['output'] as String?,
          (e['baseUrl'] as Iterable<String>? ?? [])
              .followedBy([p.dirname(url)]).toList(),
          int.parse(ArgumentError.checkNotNull(e['depth'], 'depth')));
    },
  );
  if (requests.isEmpty) {
    print('No requests were defined!!');
    return 1;
  }
  if (globalPrefs.outputFolder != null) {
    final dir = Directory(globalPrefs.outputFolder!);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
  }
  await Future.wait(requests.map((e) => processRequest(e, _onEvent(logPrefs))));
  return 0;
}

Future<void> processRequest(
    SingleRequest request, void Function(BookEvent) onEvent) async {
  var client = Client();
  if (request.settings.rateLimit != null) {
    client = RateLimitedClient(
      client,
      Duration(milliseconds: request.settings.rateLimit!),
    );
  }
  final eventController = StreamController<BookEvent>();
  eventController.stream.listen(onEvent);

  final bookContents = await fetchBook(
    request.url,
    request.baseUrls.map(withTrailingSlash),
    request.depth,
    eventController,
    client,
    request.settings.parallel,
    request.settings.images,
    request.settings.stripCss,
  );

  if (request.settings.cssOverride != null) {
    final css = request.settings.cssOverride!;
    if (!css.existsSync()) {
      throw StateError('Invalid css!');
    }
    final cssContents = await css.readAsString();
    final originalCssPath = bookContents.css.keys.single;
    final data = DocumentContents(cssContents, null, originalCssPath);
    bookContents.css[originalCssPath] = data;
  }

  final book = bookFrom(bookContents);
  eventController.add(EpubCreated());
  await eventController.close();

  final userDefinedOutput = request.output;
  var output = p.setExtension(book.title!, '.epub');
  if (userDefinedOutput != null) {
    final type = await FileSystemEntity.type(userDefinedOutput);
    switch (type) {
      case FileSystemEntityType.directory:
        output = p.join(userDefinedOutput, removeSlashes(output));
        break;
      default:
        output = p.join(request.settings.outputFolder ?? '.',
            removeSlashes(userDefinedOutput));
    }
  } else {
    output =
        p.join(request.settings.outputFolder ?? '.', removeSlashes(output));
  }
  final outputFile = File(output);
  await outputFile.writeAsBytes(EpubWriter.writeBook(book)!);
  print('SAVED  : To `$output`!');
}

String removeSlashes(String s) => s.replaceAll(r'/', '_');

Iterable<List<String>> divideRequests(List<String> notParsed) sync* {
  for (final line in notParsed) {
    yield line.split(';').toList();
  }
}
