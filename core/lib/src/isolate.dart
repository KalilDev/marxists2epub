import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'package:tuple/tuple.dart';

import '../core.dart';
import 'book_generation.dart';
import 'epub_exports.dart';
import 'fetching.dart';
import 'package:core/src/event.dart';

enum IsolateStatus {
  starting,
  idle,
  busy,
  disposed,
}

class _JobSpec {
  final String indexUrl;
  final List<String> baseUrls;
  final int depth;
  final bool parallel;
  final bool images;
  final bool stripCss;

  _JobSpec(
    this.indexUrl,
    this.baseUrls,
    this.depth,
    this.parallel,
    this.images,
    this.stripCss,
  );
}

class _MainJobState {
  final _JobSpec spec;
  final Capability capability = Capability();
  final StreamController<BookEvent> eventsController = StreamController();
  final Completer<List<int>> epubCompleter = Completer();

  _MainJobState(this.spec);

  Future<void> close() async {
    await eventsController.close();
    if (!epubCompleter.isCompleted) {
      epubCompleter
          .completeError(StateError('The state was closed before completion'));
    }
  }
}

class EbookIsolate {
  EbookIsolate._() {
    _isolateStreamSubs = _isolateStream.listen(_onIsolateMessage);
  }
  Isolate _isolate;
  final _isolateStream = ReceivePort('Main port EbookIsolate');
  StreamSubscription _isolateStreamSubs;
  SendPort _isolateSink;

  IsolateStatus status = IsolateStatus.starting;

  void _onIsolateMessage(dynamic rawData) async {
    final data = rawData as _IsolateMessage;
    if (data is _Ready) {
      assert(status == IsolateStatus.starting);
      status = IsolateStatus.idle;
      _isolateSink = data.isolateSink;
      _maybeSendNextRequest();
    }
    if (data is _BookEvent) {
      _jobState[data.identity].eventsController.add(data.event);
    }
    if (data is _CompleteErrorEvent) {
      _jobState[data.identity].epubCompleter.completeError(data.error);
      await _jobState.remove(data.identity).close();
      status = IsolateStatus.idle;
      _maybeSendNextRequest();
    }
    if (data is _CompleteSuccessEvent) {
      _jobState[data.identity].epubCompleter.complete(data.data);
      await _jobState.remove(data.identity).close();
      status = IsolateStatus.idle;
      _maybeSendNextRequest();
    }
  }

  void _sendNextRequest() {
    assert(status == IsolateStatus.idle);
    status = IsolateStatus.busy;
    final state = _jobQueue.removeLast();
    _jobState[state.capability] = state;
    _isolateSink.send(_StartJob(state.spec, state.capability));
  }

  void _maybeSendNextRequest() {
    if (status != IsolateStatus.idle) {
      return;
    }
    if (_jobQueue.isEmpty) {
      return;
    }
    _sendNextRequest();
  }

  final _jobQueue = Queue<_MainJobState>();

  final Map<Capability, _MainJobState> _jobState = {};

  Future<void> dispose() async {
    _isolate.kill(priority: Isolate.immediate);
    for (final e in _jobState.values) {
      e.epubCompleter
          .completeError(StateError('Isolate disposed before completion'));
      await e.close();
    }
    status = IsolateStatus.disposed;
  }

  void _add(_MainJobState job) {
    _jobQueue.add(job);
    _maybeSendNextRequest();
  }

  static Future<EbookIsolate> spawn() async {
    final self = EbookIsolate._();

    final isolate =
        await Isolate.spawn(_EbookIsolate.main, self._isolateStream.sendPort);
    self._isolate = isolate;
    return self;
  }

  BookResult fetchBook(
    String indexUrl,
    List<String> baseUrls,
    int depth,
    bool parallel,
    bool images,
    bool stripCss,
  ) {
    if (status == IsolateStatus.disposed) {
      throw StateError('Isolate was disposed already!');
    }
    final job = _MainJobState(_JobSpec(
      indexUrl,
      baseUrls,
      depth,
      parallel,
      images,
      stripCss,
    ));
    _add(job);
    return BookResult(job.epubCompleter.future, job.eventsController.stream);
  }
}

class BookResult {
  final Future<List<int>> contents;
  final Stream<BookEvent> events;

  BookResult(this.contents, this.events);
}

abstract class _IsolateMessage {}

class _Ready implements _IsolateMessage {
  final SendPort isolateSink;

  _Ready(this.isolateSink);
}

class _BookEvent implements _IsolateMessage {
  final BookEvent event;
  final Capability identity;

  _BookEvent(this.event, this.identity);
}

class _CompleteErrorEvent implements _IsolateMessage {
  final Object error;
  final Capability identity;

  _CompleteErrorEvent(this.error, this.identity);
}

class _CompleteSuccessEvent implements _IsolateMessage {
  final List<int> data;
  final Capability identity;

  _CompleteSuccessEvent(this.data, this.identity);
}

abstract class _MainMessage {}

class _StartJob implements _MainMessage {
  final _JobSpec specification;
  final Capability identity;

  _StartJob(this.specification, this.identity);
}

class _EbookIsolate {
  final SendPort mainSink;
  _EbookIsolate(this.mainSink) {
    _mainStreamSubs = _mainStream.listen(_onMainMessage);
    mainSink.send(_Ready(_mainStream.sendPort));
  }
  static _EbookIsolate current;
  StreamSubscription _mainStreamSubs;
  final _mainStream = ReceivePort('Isolate port _EbookIsolate');

  void startJob(_JobSpec specification, Capability identity) async {
    final events = StreamController<BookEvent>();
    void sendEvent(BookEvent e) {
      mainSink.send(_BookEvent(e, identity));
    }

    final eventSubs = events.stream.listen(sendEvent);
    try {
      final contents = await fetchBook(
        specification.indexUrl,
        specification.baseUrls,
        specification.depth,
        events,
        null,
        specification.parallel,
        specification.images,
        specification.stripCss,
      );
      final book = bookFrom(contents);
      events.add(EpubCreated());
      final data = EpubWriter.writeBook(book);
      mainSink.send(_CompleteSuccessEvent(data, identity));
    } on Object catch (e) {
      mainSink.send(_CompleteErrorEvent(e, identity));
    } finally {
      await eventSubs.cancel();
      await events.close();
    }
  }

  void _onMainMessage(dynamic rawData) {
    final data = rawData as _MainMessage;
    if (data is _StartJob) {
      startJob(data.specification, data.identity);
    }
  }

  static void main(SendPort mainSink) {
    final self = _EbookIsolate(mainSink);
    current = self;
  }
}
