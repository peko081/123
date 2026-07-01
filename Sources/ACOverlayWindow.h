#import <UIKit/UIKit.h>

/// 懸浮控制面板視窗：獨立高層級 UIWindow，含懸浮球、設定面板、點位標記。
/// 非控制元件的觸控會直接穿透到底層遊戲。
@interface ACOverlayWindow : UIWindow
+ (instancetype)shared;
/// 在 App 啟動後建立並顯示（自動延遲等待 keyWindow / scene 就緒）。
+ (void)show;
@end
