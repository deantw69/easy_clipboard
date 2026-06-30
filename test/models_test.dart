import 'package:syncnest/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TransferEnvelope JSON 來回轉換保留欄位', () {
    final env = TransferEnvelope(
      id: 'abc',
      kind: PayloadKind.file,
      senderDeviceId: 'dev-1',
      timestamp: DateTime.parse('2026-06-24T10:00:00.000Z'),
      fileName: 'movie.mp4',
      sizeBytes: 12345,
      mime: 'video/mp4',
    );
    final round = TransferEnvelope.fromJson(env.toJson());
    expect(round.id, env.id);
    expect(round.kind, PayloadKind.file);
    expect(round.fileName, 'movie.mp4');
    expect(round.sizeBytes, 12345);
    expect(round.mime, 'video/mp4');
    expect(round.timestamp, env.timestamp);
  });

  test('DeviceInfo.isReachable 取決於 host', () {
    const local = DeviceInfo(id: '1', name: 'A', platform: 'macos', port: 53318);
    expect(local.isReachable, false);
    expect(local.copyWith(host: '192.168.0.2').isReachable, true);
  });
}
