import 'package:http/http.dart';

class FetchProgress {
  final Uri source;
  final int length;
  final int downloaded;

  FetchProgress(this.source, this.length, this.downloaded);
}
