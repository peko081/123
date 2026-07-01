#import <UIKit/UIKit.h>

/// 以合成 UITouch + [UIApplication sendEvent:] 在「當前 App 進程內」注入觸控，
/// 事件直接送往遊戲視窗（非懸浮視窗），對 UIKit / Unity 遊戲相容性最佳。
/// 座標使用視窗座標，不需依螢幕方向做正規化換算。
@interface ACTouchEngine : NSObject

+ (instancetype)shared;

/// 在指定座標（螢幕座標，point 單位）做一次完整點擊（按下→放開）。
/// fingerIndex 為觸控通道，多點連點請用不同 index。
- (void)tapAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex;

/// 手動控制的按下 / 移動 / 放開（可做長按、拖曳）。
- (void)touchDownAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex;
- (void)touchMoveToPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex;
- (void)touchUpAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex;

@end
