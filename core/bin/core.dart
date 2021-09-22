import 'dart:async';
import 'dart:io';

import 'package:console/console.dart';
import 'package:core/core.dart';
import 'package:core/src/client.dart';
import 'package:epub/epub.dart';
import 'package:args/args.dart';
import 'package:hive/hive.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:path/path.dart' as p;
import 'package:tuple/tuple.dart';

class LogPreferences {
  final bool showSkipped;
  final bool showFetch;
  final bool showIgnored;

  LogPreferences(this.showSkipped, this.showFetch, this.showIgnored);
}

void Function(BookEvent e) _onEvent(LogPreferences p) {
  final fetches = <Uri, Tuple3<Uri, FetchProgress, StreamSubscription>>{};
  void log(Object o) {
    print(o);
  }

  void Function(FetchProgress) _onFetchProgress(Uri uri) => (e) {
        fetches[uri] = fetches[uri].withItem2(e);
      };

  return (e) {
    if (e is Fetch) {
      final subs = e.progress.listen(_onFetchProgress(e.uri));
      fetches[e.uri] = Tuple3(e.parent, null, subs);
    }
    if (e is FetchComplete) {
      final state = fetches.remove(e.uri);
      state.item3.cancel();
      print('FETCHED: ${e.uri}');
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
      log('COMPLET: The book fetching is complete!');
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
  final File cssOverride;
  final int rateLimit;
  final LogPreferences logPrefs;
  final String outputFolder;

  GlobalSettings(
      this.cssOverride, this.rateLimit, this.logPrefs, this.outputFolder);
}

class SingleRequest {
  final GlobalSettings settings;
  final String url;
  final String output;
  final List<String> baseUrls;
  final int depth;

  SingleRequest(
      this.settings, this.url, this.output, this.baseUrls, this.depth);
}

Future<int> main(List<String> args) async {
  args = args.toList();
  assert(() {
    args = [
      'https://www.marxists.org/reference/archive/stalin/works/1938/09.htm'
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
  final cssOverride = results['cssOverride'] as String;
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
  );

  final requests = divideRequests(results.rest).map(singleParser.parse).map(
        (e) => SingleRequest(
            globalPrefs,
            e.rest.single,
            e['output'] as String,
            (e['baseUrl'] as Iterable<String> ?? [])
                .followedBy([p.dirname(e.rest.single)]).toList(),
            int.parse(ArgumentError.checkNotNull(e['depth'], 'depth'))),
      );
  if (requests.isEmpty) {
    print('No requests were defined!!');
    return 1;
  }
  if (globalPrefs.outputFolder != null) {
    final dir = Directory(globalPrefs.outputFolder);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
  }
  await Future.wait(requests.map((e) => processRequest(e, _onEvent(logPrefs))));
  return 0;
}

Future<void> processRequest(
    SingleRequest request, void Function(BookEvent) onEvent) async {
  final mode = 'none'; //results['mode'] as String;
  Hive.init(Directory.current.path);
  var client = Client();
  if (request.settings.rateLimit != null) {
    client = RateLimitedClient(
        client, Duration(milliseconds: request.settings.rateLimit));
  }
  switch (mode) {
    case 'recording':
      final storage = HiveProxyClientStorage();
      await storage.init();
      client = RecordingClient(client, storage);
      break;
    case 'replaying':
      final storage = HiveProxyClientStorage();
      await storage.init();
      await storage.dump();
      client = ReplayingClient(storage);
      break;
    case 'none':
      client = client;
      break;
  }
  final eventController = StreamController<BookEvent>();
  eventController.stream.listen(onEvent);

  final bookContents = await fetchBook(
    request.url,
    request.baseUrls.map(withTrailingSlash),
    request.depth,
    eventController,
    client,
  );

  if (request.settings.cssOverride != null) {
    final css = request.settings.cssOverride;
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
  var output = p.setExtension(book.Title, '.epub');
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
  await outputFile.writeAsBytes(EpubWriter.writeBook(book));
  print('SAVED  : To `$output`!');
  return outputFile;
}

String removeSlashes(String s) => s.replaceAll(r'/', '_');

Iterable<List<String>> divideRequests(List<String> notParsed) sync* {
  var acc = <String>[];
  var needsArg = false;
  for (final e in notParsed) {
    acc.add(e);
    if (e.startsWith('-')) {
      needsArg = true;
      continue;
    }
    if (needsArg) {
      needsArg = false;
      continue;
    }
    // e is the url
    yield acc;
    acc = [];
  }
  if (acc.isNotEmpty) {
    yield acc;
  }
}
