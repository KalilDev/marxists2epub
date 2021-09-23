import 'package:http/http.dart';

class FetchProgress {
  final Uri source;
  final int length;
  final int downloaded;

  FetchProgress(this.source, this.length, this.downloaded);
}

class FetchProgressClient extends BaseClient {
  final Client parent;
  final Sink<FetchProgress> sink;

  FetchProgressClient(this.parent, this.sink);

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final response = await parent.send(request);
    var length = response.contentLength;
    var downloaded = 0;
    void send() {
      sink.add(FetchProgress(request.url, length, downloaded));
    }

    send();
    return StreamedResponse(
      response.stream.map((bytes) {
        downloaded += bytes.length;
        send();
        return bytes;
      }),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
