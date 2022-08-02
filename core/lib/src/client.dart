import 'dart:async';

import 'package:http/http.dart';
import 'package:synchronized/synchronized.dart';

class ManualLock {
  final Lock _lock;
  final Completer _completer;

  ManualLock(this._lock, this._completer);

  Future<void> lock() => _lock.synchronized(() {
        isLocked = true;
        return _completer.future.then((value) => isLocked = false);
      });

  void unlock() => _completer.future;
  bool isLocked = false;
}

extension on Lock {
  ManualLock createManualLock() {
    final completer = Completer();
    final lock = ManualLock(this, completer);
    return lock;
  }

  Future<ManualLock> lockManually() async {
    final lock = createManualLock();
    await lock.lock();
    return lock;
  }
}

class SequentialClient extends BaseClient {
  final Client _client;

  SequentialClient(this._client);
  final Lock lock = Lock();

  @override
  // Can only fetch responses or bodies at once.
  Future<StreamedResponse> send(BaseRequest request) async {
    final response = await lock.synchronized(() => _client.send(request));
    final manualLock = lock.createManualLock();
    late final StreamController<List<int>> bodySpyController;
    var wasCanceled = false;
    bodySpyController = StreamController(onListen: () async {
      await manualLock.lock();
      if (!wasCanceled) {
        await bodySpyController.addStream(response.stream);
      }
      if (manualLock.isLocked) {
        manualLock.unlock();
      }
    }, onCancel: () async {
      wasCanceled = true;
      if (manualLock.isLocked) {
        manualLock.unlock();
      }
      await bodySpyController.close();
    });
    return StreamedResponse(
      bodySpyController.stream,
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

class RateLimitedClient extends BaseClient {
  final Client _client;
  final Duration rateLimit;

  RateLimitedClient(this._client, this.rateLimit);

  @override
  Future<StreamedResponse> send(BaseRequest request) => Future.delayed(
        rateLimit,
        () => _client.send(request),
      );
}
