import 'dart:convert';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import '../core/models.dart';
import 'discovery.dart';

/// 區網 mDNS / Bonjour 發現實作。
///
/// 服務類型固定為 [serviceType];裝置中繼資料(id/name/platform)放在 TXT 紀錄,
/// 讓對端不必額外連線即可顯示裝置資訊。
class NsdDiscovery implements DiscoveryService {
  static const serviceType = '_easyclip._tcp';

  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  String? _localId;
  DeviceInfo? _local;
  void Function(List<DeviceInfo>)? _onChanged;
  bool _refreshing = false;

  @override
  Future<void> register(DeviceInfo local) async {
    _local = local;
    _localId = local.id;
    _registration = await nsd.register(
      nsd.Service(
        name: local.name,
        type: serviceType,
        port: local.port,
        txt: {
          'id': _utf8(local.id),
          'name': _utf8(local.name),
          'platform': _utf8(local.platform),
        },
      ),
    );
  }

  @override
  Future<void> start(void Function(List<DeviceInfo>) onChanged) async {
    _onChanged = onChanged;
    final discovery = await nsd.startDiscovery(serviceType, autoResolve: true);
    _discovery = discovery;
    discovery.addListener(() {
      final devices = discovery.services
          .map(_toDeviceInfo)
          .whereType<DeviceInfo>()
          .where((d) => d.id != _localId) // 過濾本機
          .toList();
      onChanged(devices);
    });
  }

  @override
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      // 重發通告:unregister 後再 register 一次,讓對端的被動探索補抓到本機。
      final local = _local;
      if (local != null) {
        final r = _registration;
        _registration = null;
        if (r != null) await nsd.unregister(r);
        await register(local);
      }
      // 重啟瀏覽:重新發出查詢,補抓初次可能漏掉的對端。
      final onChanged = _onChanged;
      if (onChanged != null) {
        final d = _discovery;
        _discovery = null;
        if (d != null) await nsd.stopDiscovery(d);
        await start(onChanged);
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  Future<void> stop() async {
    final d = _discovery;
    if (d != null) await nsd.stopDiscovery(d);
    final r = _registration;
    if (r != null) await nsd.unregister(r);
    _discovery = null;
    _registration = null;
  }

  DeviceInfo? _toDeviceInfo(nsd.Service s) {
    final host = s.host;
    final port = s.port;
    if (host == null || port == null) return null; // 尚未 resolve 完成
    final txt = s.txt ?? const {};
    final id = _readTxt(txt, 'id') ?? s.name ?? host;
    final name = _readTxt(txt, 'name') ?? s.name ?? host;
    final platform = _readTxt(txt, 'platform') ?? 'unknown';
    return DeviceInfo(
      id: id,
      name: name,
      platform: platform,
      host: host,
      port: port,
    );
  }

  static Uint8List _utf8(String v) => Uint8List.fromList(utf8.encode(v));

  static String? _readTxt(Map<String, Uint8List?> txt, String key) {
    final bytes = txt[key];
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }
}
