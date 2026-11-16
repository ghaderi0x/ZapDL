import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Makes sure only one ZapDL process runs per user session (desktop).
///
/// The first process listens on a loopback port. A second launch connects,
/// says "show", gets the reply `zapdl-ok` (so an unrelated program holding the
/// port is never mistaken for ZapDL), and then exits, leaving the first
/// process to bring its window to the front.
class SingleInstance {
  SingleInstance._();

  static const port = 47653;
  static const _hello = 'zapdl-show';
  static const _reply = 'zapdl-ok';
  static ServerSocket? _server;

  /// Returns true when this process is the only instance and may continue.
  /// Returns false when another ZapDL answered: the caller should exit.
  static Future<bool> acquire({required Future<void> Function() onActivate}) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _server = server;
      server.listen((client) {
        client.listen(
          (data) {
            if (utf8.decode(data, allowMalformed: true).trim() == _hello) {
              client.write(_reply);
              unawaited(client.flush().then((_) => client.close()).catchError((_) {}));
              unawaited(onActivate());
            }
          },
          onError: (_) {},
          cancelOnError: true,
        );
      }, onError: (_) {});
      return true;
    } on SocketException {
      return !(await _pingExisting());
    }
  }

  static Future<bool> _pingExisting() async {
    Socket? s;
    try {
      s = await Socket.connect(InternetAddress.loopbackIPv4, port,
          timeout: const Duration(seconds: 1));
      s.write(_hello);
      await s.flush();
      final reply = await s
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      return reply.trim() == _reply;
    } catch (_) {
      return false; // not ZapDL (or not answering): do not block this launch
    } finally {
      s?.destroy();
    }
  }
}
