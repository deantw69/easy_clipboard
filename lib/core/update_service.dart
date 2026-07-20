import 'package:dio/dio.dart';

import 'app_version.dart';

/// 一次「檢查更新」的結果。
class UpdateInfo {
  /// GitHub release 的 tag,例如 `v1.0.4`(原樣保留)。
  final String latestTag;

  /// 正規化後的最新版本號(去掉 v/pre-release/build),例如 `1.0.4`。
  final String latestVersion;

  /// release 頁面網址,供使用者手動下載安裝。
  final String htmlUrl;

  /// release 說明(可能為空)。
  final String? body;

  /// 遠端是否比本機 [kAppVersion] 新。
  final bool hasUpdate;

  const UpdateInfo({
    required this.latestTag,
    required this.latestVersion,
    required this.htmlUrl,
    required this.body,
    required this.hasUpdate,
  });
}

/// 檢查 GitHub release 是否有新版本(Tier A:只檢查+提示,不自動下載/覆蓋)。
///
/// public repo 免認證即可查詢,未認證限速 60 次/小時,足夠手動點擊使用。
class UpdateService {
  static const String _api =
      'https://api.github.com/repos/deantw69/easy_clipboard/releases/latest';

  /// 打 GitHub API 取最新 release 並和本機版本比對。
  /// 失敗(逾時/斷網/API 異常)直接丟例外,由 UI catch 顯示。
  static Future<UpdateInfo> check() async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: const {'Accept': 'application/vnd.github+json'},
    ));
    final res = await dio.get<Map<String, dynamic>>(_api);
    final data = res.data ?? const {};
    final tag = (data['tag_name'] ?? '').toString();
    final url = (data['html_url'] ?? '').toString();
    final body = data['body']?.toString();
    final latest = _normalize(tag);
    return UpdateInfo(
      latestTag: tag,
      latestVersion: latest,
      htmlUrl: url,
      body: (body == null || body.isEmpty) ? null : body,
      hasUpdate: _compare(latest, _normalize(kAppVersion)) > 0,
    );
  }

  /// 去掉開頭的 v/V、pre-release(`-`)與 build metadata(`+`),只留 `x.y.z`。
  static String _normalize(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('-')
      .first;

  /// 語意化版本比對:回傳 >0 表示 [a] 比 [b] 新,<0 舊,0 相同。
  static int _compare(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }
}
