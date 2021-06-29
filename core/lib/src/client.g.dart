// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RecordedInteractionAdapter extends TypeAdapter<RecordedInteraction> {
  @override
  final int typeId = 1;

  @override
  RecordedInteraction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return RecordedInteraction(
      fields[0] as Uri,
      (fields[1] as Map)?.cast<String, String>(),
      fields[2] as HiveResponse,
    );
  }

  @override
  void write(BinaryWriter writer, RecordedInteraction obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.uri)
      ..writeByte(1)
      ..write(obj.headers)
      ..writeByte(2)
      ..write(obj.response);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordedInteractionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HiveResponseAdapter extends TypeAdapter<HiveResponse> {
  @override
  final int typeId = 2;

  @override
  HiveResponse read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return HiveResponse(
      fields[1] as int,
      (fields[2] as Map)?.cast<String, String>(),
      fields[3] as bool,
      fields[4] as bool,
      fields[5] as String,
      fields[6] as HiveRequest,
      fields[7] as int,
      fields[0] as Uint8List,
    );
  }

  @override
  void write(BinaryWriter writer, HiveResponse obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.bodyBytes)
      ..writeByte(1)
      ..write(obj.contentLength)
      ..writeByte(2)
      ..write(obj.headers)
      ..writeByte(3)
      ..write(obj.isRedirect)
      ..writeByte(4)
      ..write(obj.persistentConnection)
      ..writeByte(5)
      ..write(obj.reasonPhrase)
      ..writeByte(6)
      ..write(obj.request)
      ..writeByte(7)
      ..write(obj.statusCode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveResponseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HiveRequestAdapter extends TypeAdapter<HiveRequest> {
  @override
  final int typeId = 3;

  @override
  HiveRequest read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return HiveRequest(
      (fields[5] as Map)?.cast<String, String>(),
      fields[6] as String,
      fields[7] as Uri,
    )
      ..contentLength = fields[0] as int
      ..followRedirects = fields[1] as bool
      ..maxRedirects = fields[2] as int
      ..persistentConnection = fields[3] as bool;
  }

  @override
  void write(BinaryWriter writer, HiveRequest obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.contentLength)
      ..writeByte(1)
      ..write(obj.followRedirects)
      ..writeByte(2)
      ..write(obj.maxRedirects)
      ..writeByte(3)
      ..write(obj.persistentConnection)
      ..writeByte(4)
      ..write(obj.finalized)
      ..writeByte(5)
      ..write(obj.headers)
      ..writeByte(6)
      ..write(obj.method)
      ..writeByte(7)
      ..write(obj.url);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveRequestAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RecordedInteraction _$RecordedInteractionFromJson(Map<String, dynamic> json) {
  return RecordedInteraction(
    json['uri'] == null ? null : Uri.parse(json['uri'] as String),
    (json['headers'] as Map<String, dynamic>)?.map(
      (k, e) => MapEntry(k, e as String),
    ),
    json['response'] == null
        ? null
        : HiveResponse.fromJson(json['response'] as Map<String, dynamic>),
  );
}

Map<String, dynamic> _$RecordedInteractionToJson(
        RecordedInteraction instance) =>
    <String, dynamic>{
      'uri': instance.uri?.toString(),
      'headers': instance.headers,
      'response': instance.response,
    };

HiveResponse _$HiveResponseFromJson(Map<String, dynamic> json) {
  return HiveResponse(
    json['contentLength'] as int,
    (json['headers'] as Map<String, dynamic>)?.map(
      (k, e) => MapEntry(k, e as String),
    ),
    json['isRedirect'] as bool,
    json['persistentConnection'] as bool,
    json['reasonPhrase'] as String,
    json['request'] == null
        ? null
        : HiveRequest.fromJson(json['request'] as Map<String, dynamic>),
    json['statusCode'] as int,
  );
}

Map<String, dynamic> _$HiveResponseToJson(HiveResponse instance) =>
    <String, dynamic>{
      'contentLength': instance.contentLength,
      'headers': instance.headers,
      'isRedirect': instance.isRedirect,
      'persistentConnection': instance.persistentConnection,
      'reasonPhrase': instance.reasonPhrase,
      'request': instance.request,
      'statusCode': instance.statusCode,
    };

HiveRequest _$HiveRequestFromJson(Map<String, dynamic> json) {
  return HiveRequest(
    (json['headers'] as Map<String, dynamic>)?.map(
      (k, e) => MapEntry(k, e as String),
    ),
    json['method'] as String,
    json['url'] == null ? null : Uri.parse(json['url'] as String),
  )
    ..contentLength = json['contentLength'] as int
    ..followRedirects = json['followRedirects'] as bool
    ..maxRedirects = json['maxRedirects'] as int
    ..persistentConnection = json['persistentConnection'] as bool;
}

Map<String, dynamic> _$HiveRequestToJson(HiveRequest instance) =>
    <String, dynamic>{
      'contentLength': instance.contentLength,
      'followRedirects': instance.followRedirects,
      'maxRedirects': instance.maxRedirects,
      'persistentConnection': instance.persistentConnection,
      'headers': instance.headers,
      'method': instance.method,
      'url': instance.url?.toString(),
    };
