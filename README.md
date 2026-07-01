# AutoClicker — iOS 免越獄連點器（自行注入）

以 dylib 形式注入到目標 App 進程內，於進程內用 **IOHIDEvent 數位觸控事件** 合成點擊。
非越獄環境下運作，適用 iOS 15+（arm64 / arm64e）。

> 僅供對「自己擁有或有權測試」的 App 做自動化測試用途。請自行承擔使用責任。

## 專案結構

```
.
├── Makefile                  # Theos 建置設定
├── control                   # 套件資訊
├── AutoClicker.plist         # 注入過濾（僅越獄 Substrate 用；自行注入時忽略）
├── Tweak.xm                  # %ctor 進入點
├── README.md
└── Sources/
    ├── ACTouchEngine.{h,m}   # IOHIDEvent 觸控合成引擎（核心）
    ├── ACManager.{h,m}       # 點位管理 + 連點排程
    └── ACOverlayWindow.{h,m} # 懸浮控制面板 UI
```

## 運作原理

1. dylib 被載入時，`%ctor` 觸發，建立一個高層級 `UIWindow`（懸浮面板）。
2. 面板的空白區域觸控會**穿透**到底層遊戲，只有懸浮球/面板本身可互動。
3. 進入「錄製模式」後，點螢幕即記錄座標為連點點位。
4. 按「開始」後，`ACManager` 為每個點位建立獨立計時器，
   依間隔呼叫 `ACTouchEngine` 送出 `IOHIDEventCreateDigitizerFingerEvent` →
   `[UIApplication _enqueueHIDEvent:]`，把觸控注入本進程事件迴圈。

## 建置（需 macOS 或 WSL + Theos）

Windows 無法直接跑 Theos，請用其中一種：
- macOS 安裝 Theos
- Windows 用 WSL2 (Ubuntu) 安裝 Theos

安裝好 Theos 後：

```bash
export THEOS=~/theos
make            # 編譯，產物在 .theos/obj/AutoClicker.dylib
make package    # 打包 .deb（越獄裝置用）
```

**自行注入只需要 `.theos/obj/AutoClicker.dylib` 這個檔案。**

## 自行注入到目標 App（非越獄）

常見流程（擇一）：

1. 取得目標遊戲的 `.ipa`，解壓得到 `Payload/xxx.app`。
2. 用 `insert_dylib` 把 `AutoClicker.dylib` 加入主執行檔的 load commands：
   ```bash
   insert_dylib --strip-codesig --all-yes \
     "@executable_path/AutoClicker.dylib" Payload/xxx.app/xxx
   ```
3. 把 `AutoClicker.dylib` 複製進 `Payload/xxx.app/` 內。
4. 重新壓成 ipa，用你的簽章工具（Sideloadly / ESign / TrollStore 等）重簽並安裝。

> 若走 TrollStore，也可用其 dylib 注入功能直接掛載，免手動 insert_dylib。

## 使用

- 進 App 後左上出現藍色「連」懸浮球，可拖曳。
- 點懸浮球 → 展開面板。
- 「＋ 錄製點位」→ 點畫面要連點的位置（可多點）。
- 用滑桿調整間隔（10~1000 ms）。
- 「▶ 開始 / ⏸ 停止」切換連點。
- 「清除全部」清空點位。

## 關鍵可調參數

| 需求 | 位置 |
|------|------|
| 點擊按下→放開停留時間 | `ACTouchEngine.m` → `tapAtPoint:` 的 `0.02` 秒 |
| 每點獨立間隔 | `ACManager` → `setInterval:forPointAtIndex:` |
| 送事件私有方法 | `ACTouchEngine.m` → `_enqueueHIDEvent:`（若某版本失效可改用其他派送法） |
| 面板層級 | `ACOverlayWindow.m` → `windowLevel` |

## 相容性注意

- `_enqueueHIDEvent:` 為私有 API，Apple 未來可能更動；若在某 iOS 版本無效，
  可改試 `handleHIDEvent:` 或透過 `BKSHIDEventDeliveryManager` 派送。
- 座標使用正規化 0~1，已處理邊界；若遊戲橫向且座標偏移，需在 `normalizePoint:`
  依 `interfaceOrientation` 做旋轉換算。
