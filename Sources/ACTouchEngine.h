#import <UIKit/UIKit.h>

/// 以 IOHIDEvent 數位觸控事件在「當前 App 進程內」合成觸控。
/// 適用於非越獄環境下自行注入的 dylib：事件直接進入本進程的事件迴圈，
/// 對 UIKit / Unity / Cocos / Metal 遊戲相容性最佳。
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
