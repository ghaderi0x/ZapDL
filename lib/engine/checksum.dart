import 'dart:io';

import 'package:crypto/crypto.dart';

enum ChecksumAlgorithm { sha256, md5 }

/// Streams the file through the hash (constant memory) and returns lowercase hex.
///
/// This only *calculates* a checksum. Verification means comparing it to a
/// trusted expected value, see [verifyChecksum]. MD5 is not collision
/// resistant and must not be treated as proof of authenticity.
Future<String> calculateChecksum(File file, ChecksumAlgorithm algorithm) async {
  final hash = algorithm == ChecksumAlgorithm.sha256 ? sha256 : md5;
  final digest = await hash.bind(file.openRead()).first;
  return digest.toString();
}

Future<bool> verifyChecksum(
  File file,
  ChecksumAlgorithm algorithm,
  String expectedHex,
) async {
  final actual = await calculateChecksum(file, algorithm);
  return actual == expectedHex.trim().toLowerCase();
}
