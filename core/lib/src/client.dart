import 'dart:convert';
import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:http/src/utils.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mime/mime.dart' as mime;
import 'package:http_parser/http_parser.dart';
import 'package:collection/collection.dart';
import 'package:synchronized/synchronized.dart';
import 'package:synchronized/extension.dart';
part 'client.g.dart';

abstract class ClientStorage {
  Future<void> storeRequest(
    Uri uri,
    Map<String, String> headers,
    Response response,
  );
  Future<Response> fetchRequest(
    Uri uri,
    Map<String, String> headers,
  );
}

@HiveType(typeId: 1)
@JsonSerializable()
class RecordedInteraction {
  @HiveField(0)
  final Uri uri;
  @HiveField(1)
  final Map<String, String> headers;
  @HiveField(2)
  final HiveResponse response;

  Map<String, dynamic> toJson() => _$RecordedInteractionToJson(this);
  const RecordedInteraction(this.uri, this.headers, this.response);
}

/// Returns the encoding to use for a response with the given headers.
///
/// Defaults to [latin1] if the headers don't specify a charset or if that
/// charset is unknown.
Encoding _encodingForHeaders(Map<String, String> headers) =>
    encodingForCharset(_contentTypeForHeaders(headers).parameters['charset']);

/// Returns the [MediaType] object for the given headers's content-type.
///
/// Defaults to `application/octet-stream`.
MediaType _contentTypeForHeaders(Map<String, String> headers) {
  var contentType = headers['content-type'];
  if (contentType != null) return MediaType.parse(contentType);
  return MediaType('application', 'octet-stream');
}

@HiveType(typeId: 2)
@JsonSerializable()
class HiveResponse implements Response {
  String get body => _encodingForHeaders(headers).decode(bodyBytes);
  @HiveField(0)
  @JsonKey(ignore: true)
  final Uint8List bodyBytes;

  @HiveField(1)
  final int contentLength;
  @HiveField(2)
  final Map<String, String> headers;
  @HiveField(3)
  final bool isRedirect;
  @HiveField(4)
  final bool persistentConnection;
  @HiveField(5)
  final String reasonPhrase;
  @HiveField(6)
  final HiveRequest request;
  @HiveField(7)
  final int statusCode;

  HiveResponse(
    this.contentLength,
    this.headers,
    this.isRedirect,
    this.persistentConnection,
    this.reasonPhrase,
    this.request,
    this.statusCode, [
    this.bodyBytes,
  ]);
  Map<String, dynamic> toJson() => _$HiveResponseToJson(this);
  factory HiveResponse.fromJson(Map<String, dynamic> json) =>
      _$HiveResponseFromJson(json);
  factory HiveResponse.fromResponse(Response response) => HiveResponse(
        response.contentLength,
        response.headers,
        response.isRedirect,
        response.persistentConnection,
        response.reasonPhrase,
        HiveRequest.fromRequest(response.request),
        response.statusCode,
        response.bodyBytes,
      );
}

@HiveType(typeId: 3)
@JsonSerializable()
class HiveRequest implements BaseRequest {
  @HiveField(0)
  int contentLength;

  @HiveField(1)
  bool followRedirects;

  @HiveField(2)
  int maxRedirects;

  @HiveField(3)
  bool persistentConnection;

  @HiveField(4)
  final bool finalized = true;

  @HiveField(5)
  final Map<String, String> headers;

  @HiveField(6)
  final String method;

  @HiveField(7)
  final Uri url;

  HiveRequest(
    this.headers,
    this.method,
    this.url,
  );
  Map<String, dynamic> toJson() => _$HiveRequestToJson(this);

  factory HiveRequest.fromJson(Map<String, dynamic> json) =>
      _$HiveRequestFromJson(json);
  factory HiveRequest.fromRequest(BaseRequest request) => HiveRequest(
        request.headers,
        request.method,
        request.url,
      )
        ..contentLength = request.contentLength
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection;

  Never noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UriAdapter extends TypeAdapter<Uri> {
  @override
  Uri read(BinaryReader reader) => Uri.parse(reader.readString());

  @override
  final int typeId = 5;

  @override
  void write(BinaryWriter writer, Uri obj) =>
      writer..writeString(obj.toString());
}

class HiveProxyClientStorage implements ClientStorage {
  LazyBox<List<dynamic>> _box;
  Future<void> init() async {
    Hive.registerAdapter(HiveRequestAdapter());
    Hive.registerAdapter(HiveResponseAdapter());
    Hive.registerAdapter(RecordedInteractionAdapter());
    Hive.registerAdapter(UriAdapter());
    _box = await Hive.openLazyBox('proxy-client-storage');
  }

  static const _headerEquality = MapEquality<String, String>();

  @override
  Future<Response> fetchRequest(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final uriString = uri.toString();
    if (!_box.containsKey(uriString)) {
      return null;
    }
    final interactions =
        await _box.get(uriString).then((es) => es.cast<RecordedInteraction>());
    final interaction = interactions
        .singleWhereOrNull((e) => _headerEquality.equals(e.headers, headers));
    return interaction?.response;
  }

  @override
  Future<void> storeRequest(
    Uri uri,
    Map<String, String> headers,
    Response response,
  ) async {
    final uriString = uri.toString();
    final interactions = await _box.get(uriString,
        defaultValue: []).then((es) => es.cast<RecordedInteraction>());
    final newInteraction =
        RecordedInteraction(uri, headers, HiveResponse.fromResponse(response));

    await _box.put(uriString, interactions..add(newInteraction));
  }

  Future<void> dump() async {
    final interactions = await Future.wait(_box.keys.map((e) => _box.get(e)));
    print(JsonEncoder.withIndent(' ').convert(interactions));
  }
}

class RateLimitedClient implements Client {
  final Client _client;
  final Duration rateLimit;

  RateLimitedClient(this._client, this.rateLimit);
  Future<Response> get(Uri uri, {Map<String, String> headers}) =>
      _client.synchronized(() => Future.delayed(
            rateLimit,
            () => _client.get(uri, headers: headers),
          ));

  Never noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingClient implements Client {
  final Client _client;
  final ClientStorage storage;

  RecordingClient(this._client, this.storage);

  Future<Response> get(Uri uri, {Map<String, String> headers}) =>
      _client.get(uri, headers: headers).then(
            (response) => storage
                .storeRequest(uri, headers, response)
                .then((_) => response),
          );

  Never noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ReplayingClient implements Client {
  final ClientStorage storage;

  ReplayingClient(this.storage);

  Future<Response> get(Uri uri, {Map<String, String> headers}) =>
      storage.fetchRequest(uri, headers).then((response) =>
          response == null ? throw StateError('Invalid request') : response);

  Never noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
