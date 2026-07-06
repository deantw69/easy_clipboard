# 備忘錄同步事故分析：舊內容蓋回新內容（2026-07-06）

> 目的：在 Windows 端 pull 下此檔後，執行診斷腳本蒐集實際時間戳，判定根因屬於
> 「同步/合併方向 bug」還是「時間戳寫入異常」。**分析未完成前不要修改程式碼。**

## 一、事故描述

- 週五（2026-07-03）晚上之後，這台 **Mac 就沒有再開機**。
- 週日（2026-07-05）晚上，在 **Windows 電腦與 iPhone** 上都有修改備忘錄內容，兩者也互相同步過，iPhone 上確實看得到兩台的新修改。
- 週一（2026-07-06）早上開這台 **Mac**，結果 iPhone 上的內容被**還原成舊的（週五以前）**。

## 二、已在 Mac 端蒐集到的證據

1. `~/Downloads/SyncNest/memos.json` 內**所有** `updatedAt` 皆 ≤ **1783075256890**（= 2026-07-03 18:40:56，週五），**沒有任何未來時間戳**。
2. 該檔**檔案修改時間停在 `Jul 3 18:40`（週五）**，且**沒有 `.bak`**。
   - `_save()`（`lib/memos/memo_store.dart`）只要合併到任何較新資料就會覆寫主檔並產生 `.bak`。
   - 檔案沒動、無 .bak ⇒ **Mac 自週五起沒再寫過檔** ⇒ 今早那次同步**沒有從 iPhone 收到任何比週五更新的資料**。

## 三、已排除的假設

- **時鐘偏移**：Windows 時鐘雖不準，但漂移在 **1 分鐘內**；週五↔週日差約 2 天，1 分鐘偏差不可能讓週五資料贏過週日資料。**排除**。
- **`_monotonicNow` 灌成未來值（T21 副作用）**：Mac 檔案無任何未來時間戳。**排除**（至少 Mac 端沒發生）。
- **Mac 端編輯路徑漏 `_touch`**：編輯器（`memos_page.dart:834-844`，走 `store.add`＋`store.update`）、`toggleTodo`、`reorder`、`add`、`delete`、`restore` 全都有呼叫 `_touch`；`_monotonicNow = max(now, maxSeen+1)` 只會讓時間戳往上，理論上不可能把週日編輯寫成早於週五。**Mac 端寫入邏輯查無漏洞**。

## 四、目前唯一自洽的結論（待驗證）

今早 iPhone 上那些被還原的 memo，其 `updatedAt` **比 Mac 的週五（1783075256890）還舊**：
- 所以 Mac push 過去時 `Friday > iPhone` → iPhone 被 LWW 蓋回舊內容；
- 同時 iPhone 回給 Mac 的東西不比 Mac 新 → Mac 不寫檔（符合「檔案停在週五、無 .bak」）。

**異常點**：內容是週日編輯的、時間戳卻早於週五。這在目前程式碼下「不該發生」，所以要用 Windows 的實際資料把它逼出來。

## 五、Windows 端要蒐集的資料（請執行）

Windows 沒參與今早 Mac 的同步，**很可能還留著昨晚的真實狀態**。

> ⚠️ 執行前：**先讓 Windows 這台 App 不要跟其他裝置同步**（關掉 App／拔網路／確認 Mac、iPhone 不在同網），以免它的狀態也被覆蓋。

在專案根目錄執行（PowerShell）：

```powershell
powershell -ExecutionPolicy Bypass -File tools\dump_memos.ps1
```

或指定自訂儲存路徑：

```powershell
powershell -ExecutionPolicy Bypass -File tools\dump_memos.ps1 -Path "C:\你的\SyncNest\memos.json"
```

把整段輸出貼回來即可。腳本會列出每則 memo 的 `updatedAt`（epoch 毫秒＋可讀時間）、`deleted`、`sortKey`、文字摘要，並標示與關鍵門檻的關係。

## 六、判讀分岔（拿到 Windows 輸出後）

以你**昨晚編輯過**的那則 memo 的 `updatedAt` 為準：

- **≥ 1783075256890（晚於週五 18:40，理應是週日）**
  → Windows 有正確的新時間戳。
  → bug 在**同步／合併方向**：iPhone 本可從 Windows 取得新資料，卻仍被 Mac 的舊資料蓋掉。
  → 往 `syncMemos`（送出/往返方向）、`mergeJson`、以及「今早 Mac 與 iPhone 之外，iPhone 是否也跟 Windows 同步過」的時序查。

- **< 1783075256890（竟早於週五）**
  → 週日的編輯帶到了舊時間戳。
  → bug 在**時間戳寫入**：某條編輯/合併路徑沒正確 bump `updatedAt`，或該裝置當下 `maxSeen`/寫入時機出事。
  → 往 Windows 端實際觸發的編輯路徑、以及 `_monotonicNow` 在該情境的輸入查。

## 七、附帶蒐集（可選，有助交叉比對）

- iPhone 目前狀態：用 App 內「匯出備忘錄」匯出 JSON，一併提供其 `updatedAt`。
- Windows 的 `memos.json.bak`（若有）：可看上一版 known-good，腳本會一併 dump。
