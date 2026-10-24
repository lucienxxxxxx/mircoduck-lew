import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

List<int> pairingKey(String text) {
  final key = text.trim();
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key)) {
    throw const FormatException('配对密钥应为 64 位十六进制字符');
  }
  return [
    for (int i = 0; i < key.length; i += 2)
      int.parse(key.substring(i, i + 2), radix: 16),
  ];
}

Uint8List encodePacket(List<int> key, Map<String, dynamic> message) {
  final body = jsonEncode(message);
  final mac = Hmac(sha256, key).convert(utf8.encode(body)).toString();
  final bytes = Uint8List.fromList(
    utf8.encode(jsonEncode({'p': body, 'h': mac})),
  );
  if (bytes.length > 1400) throw const FormatException('UDP 数据包过大');
  return bytes;
}

Map<String, dynamic> decodePacket(List<int> key, List<int> wire) {
  if (wire.length > 1400) throw const FormatException('UDP 数据包过大');
  final envelope = jsonDecode(utf8.decode(wire));
  if (envelope is! Map ||
      envelope.length != 2 ||
      envelope['p'] is! String ||
      envelope['h'] is! String) {
    throw const FormatException('无效报文');
  }
  final body = envelope['p'] as String, signature = envelope['h'] as String;
  final expected = Hmac(sha256, key).convert(utf8.encode(body)).toString();
  int mismatch = signature.length ^ expected.length;
  if (signature.length == expected.length) {
    for (int i = 0; i < expected.length; i++) {
      mismatch |= signature.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
  }
  if (mismatch != 0) throw const FormatException('报文认证失败');
  final result = jsonDecode(body);
  if (result is! Map<String, dynamic> || result['v'] != 1) {
    throw const FormatException('协议版本不匹配');
  }
  return result;
}
