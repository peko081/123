#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ACDeliveryMode) {
    ACDeliveryModeUITouch = 0,  // 合成 UITouch（附掛 HID 背景事件）+ sendEvent
    ACDeliveryModeHID     = 1,  // 純 IOHIDEvent enqueue
    ACDeliveryModeDirect  = 2,  // 直接呼叫命中視圖的 touchesBegan/Moved/Ended
};

/// 在「當前 App 進程內」注入觸控，對 UIKit / Unity 遊戲相容。
@interface ACTouchEngine : NSObject

+ (instancetype)shared;

/// 派送方式（可在面板即時切換以測試哪種對此遊戲有效）
@property (nonatomic, assign) ACDeliveryMode deliveryMode;

- (void)tapAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex;
- (void)touchDownAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex;
- (void)touchMoveToPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex;
- (void)touchUpAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex;

/// 對螢幕中央送一次測試點擊。
- (void)testTapAtCenter;

/// 回傳目前環境診斷（可用的私有 API、目標視窗等），顯示在面板上協助除錯。
- (NSString *)diagnostics;

@end
