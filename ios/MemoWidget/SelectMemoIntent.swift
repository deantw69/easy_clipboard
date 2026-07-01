import AppIntents

/// 可被 widget 選取的一則備忘錄(以 id 對應 App Group 內的資料)。
struct MemoEntity: AppEntity {
  let id: String
  let name: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "備忘錄"
  static var defaultQuery = MemoEntityQuery()

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

/// 供設定畫面列出/還原備忘錄選項;資料一律讀 App Group。
struct MemoEntityQuery: EntityQuery {
  func entities(for identifiers: [MemoEntity.ID]) async throws -> [MemoEntity] {
    let data = MemoWidgetStore.load()
    return identifiers.compactMap { id in
      data.memo(id: id).map { MemoEntity(id: $0.id, name: $0.displayName) }
    }
  }

  func suggestedEntities() async throws -> [MemoEntity] {
    MemoWidgetStore.load().memos.map { MemoEntity(id: $0.id, name: $0.displayName) }
  }

  func defaultResult() async -> MemoEntity? {
    MemoWidgetStore.load().memos.first.map { MemoEntity(id: $0.id, name: $0.displayName) }
  }
}

/// Widget 設定 intent:每個 widget 實例各自選一則要顯示的備忘錄。
struct SelectMemoIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "選擇備忘錄"
  static var description = IntentDescription("選擇要在此小工具顯示的備忘錄。")

  @Parameter(title: "備忘錄")
  var memo: MemoEntity?
}
