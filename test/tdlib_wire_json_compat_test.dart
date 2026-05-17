import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/oxplayer/telegram/utils/tdlib_wire_json_compat.dart';

void main() {
  group('tdlibJsonPeekForLog', () {
    test('returns @type for object JSON', () {
      expect(tdlibJsonPeekForLog('{"@type":"getMe"}'), 'getMe');
    });

    test('includes @extra when present', () {
      expect(
        tdlibJsonPeekForLog('{"@type":"foo","@extra":1}'),
        'foo @extra=1',
      );
    });
  });
}
