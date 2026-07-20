/// App 顯示與「檢查更新」版本比對用的版本號。
///
/// **每次發 GitHub release 時,連同 `pubspec.yaml` 的 `version` 一起 bump 這裡。**
/// 更新比對是拿本常數和 GitHub 最新 release 的 `tag_name` 比,
/// 故此值必須反映目前這份 build 實際對應的 release 版本。
const String kAppVersion = '1.0.4';
