import 'dart:io';

import 'package:core/core.dart';
import 'package:core/src/client.dart';
import 'package:epub/epub.dart';
import 'package:args/args.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:path/path.dart' as p;

Future<int> main(List<String> args) async {
  args = args.toList();
  assert(() {
    args.addAll([
      '-u',
      'https://www.marxists.org/archive/marx/works/1847/wage-labour/index.htm',
      '-b',
      'https://www.marxists.org/',
      '-s',
      '../marxists.css',
      '-d',
      '1'
    ]);
    return true;
  }());
  final parser = ArgParser()
    ..addOption(
      'url',
      abbr: 'u',
      help: 'The url for the work to be downloaded',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'The output epub file',
    )
    ..addOption(
      'cssOverride',
      abbr: 's',
      help: 'The file which will be used to override the style sheets',
    )
    ..addOption(
      'baseUrl',
      abbr: 'b',
      help: 'The base url for the documents which will be downloaded.',
    )
    ..addOption(
      'depth',
      abbr: 'd',
      help: 'The recursion depth for downloading documents',
      defaultsTo: '1',
    )
    ..addOption(
      'rateLimit',
      abbr: 'l',
      help: 'The interval between requests',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Display this menu',
    );
  final results = parser.parse(args);
  if (results['help']) {
    print(parser.usage);
    return 0;
  }
  final rateLimit = results['rateLimit'] == null
      ? null
      : int.tryParse(results['rateLimit'] as String);
  final url = ArgumentError.checkNotNull(results['url'] as String);
  final baseUrl = results['baseUrl'] as String ?? p.dirname(url);
  final depth =
      int.parse(ArgumentError.checkNotNull(results['depth'] as String));
  final cssOverride = results['cssOverride'] as String;

  final mode = 'none'; //results['mode'] as String;
  Hive.init(Directory.current.path);
  var client = Client();
  if (rateLimit != null) {
    client = RateLimitedClient(client, Duration(milliseconds: rateLimit));
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

  final bookContents =
      await fetchBook(url, withTrailingSlash(baseUrl), depth, client);

  if (cssOverride != null) {
    final css = File(cssOverride);
    if (!css.existsSync()) {
      throw StateError('Invalid css!');
    }
    final cssContents = await css.readAsString();
    final originalCssPath = bookContents.css.keys.single;
    final data = DocumentContents(cssContents, null, originalCssPath);
    bookContents.css[originalCssPath] = data;
  }

  final book = bookFrom(bookContents);

  final userDefinedOutput = results['output'] as String;
  var output = p.setExtension(book.Title, '.epub');
  if (userDefinedOutput != null) {
    final type = await FileSystemEntity.type(userDefinedOutput);
    switch (type) {
      case FileSystemEntityType.directory:
        output = p.join(userDefinedOutput, output);
        break;
      default:
        output = userDefinedOutput;
    }
  }
  await File(output).writeAsBytes(EpubWriter.writeBook(book));
  return 0;
}
