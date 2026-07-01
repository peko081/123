#import "ACTouchEngine.h"
#import "AutoTouch.h"

// 以 AutoTouch（IOHIDDigitizer 鏈）為底層引擎的薄包裝。
@interface ACTouchEngine ()
// fingerIndex -> AutoTouch slot
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *slots;
@end

@implementation ACTouchEngine

+ (instancetype)shared {
    static ACTouchEngine *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [ACTouchEngine new]; });
    return inst;
}

- (instancetype)init {
    if (self = [super init]) {
        _slots = [NSMutableDictionary dictionary];
        _deliveryMode = ACDeliveryModeUITouch;
    }
    return self;
}

- (void)tapAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self tapAtPoint:point fingerIndex:fingerIndex]; });
        return;
    }
    [AutoTouch tap:point];
}

- (void)touchDownAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self touchDownAtPoint:point fingerIndex:fingerIndex]; });
        return;
    }
    NSInteger slot = [AutoTouch touchAt:point phase:UITouchPhaseBegan slot:0];
    if (slot > 0) self.slots[@(fingerIndex)] = @(slot);
}

- (void)touchMoveToPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self touchMoveToPoint:point fingerIndex:fingerIndex]; });
        return;
    }
    NSNumber *slot = self.slots[@(fingerIndex)];
    if (slot) [AutoTouch touchAt:point phase:UITouchPhaseMoved slot:slot.integerValue];
}

- (void)touchUpAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self touchUpAtPoint:point fingerIndex:fingerIndex]; });
        return;
    }
    NSNumber *slot = self.slots[@(fingerIndex)];
    if (slot) {
        [AutoTouch touchAt:point phase:UITouchPhaseEnded slot:slot.integerValue];
        [self.slots removeObjectForKey:@(fingerIndex)];
    }
}

- (void)testTapAtCenter {
    UIWindow *w = [self resolvedWindow];
    CGPoint c = w ? CGPointMake(CGRectGetMidX(w.bounds), CGRectGetMidY(w.bounds))
                  : CGPointMake(200, 400);
    [AutoTouch tap:c];
}

#pragma mark - 診斷

- (UIWindow *)resolvedWindow {
    UIApplication *app = [UIApplication sharedApplication];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) if (w.isKeyWindow) return w;
            if (ws.windows.firstObject) return ws.windows.firstObject;
        }
    }
    return app.keyWindow;
}

- (NSString *)diagnostics {
    UIWindow *w = [self resolvedWindow];
    UIView *hv = nil;
    if (w) hv = [w hitTest:CGPointMake(CGRectGetMidX(w.bounds), CGRectGetMidY(w.bounds)) withEvent:nil];
    return [NSString stringWithFormat:
        @"引擎:AutoTouch\n目標視窗:%@ %@\n中央命中視圖:%@",
        w ? NSStringFromClass([w class]) : @"(無)",
        w.isKeyWindow ? @"[key]" : @"",
        hv ? NSStringFromClass([hv class]) : @"(無)"];
}

@end
