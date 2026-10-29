import 'dart:convert';
import 'dart:typed_data';

Uint8List encodePacket(Map<String, dynamic> message) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(message)));
  if (bytes.length > 1400) throw const FormatException('UDP 数据包过大');
  return bytes;
}

Map<String, dynamic> decodePacket(List<int> wire) {
  if (wire.length > 1400) throw const FormatException('UDP 数据包过大');
  final result = jsonDecode(utf8.decode(wire));
  if (result is! Map<String, dynamic> || result['v'] != 2) {
    throw const FormatException('协议版本不匹配，请更新主板接入层和 App 至 0.4');
  }
  return result;
}
