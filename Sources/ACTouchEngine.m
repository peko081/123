#import "ACTouchEngine.h"
#import <objc/runtime.h>

#pragma mark - UIKit 私有 API 宣告（合成觸控用）

@interface UIApplication (ACPrivate)
- (UIEvent *)_touchesEvent;
@end

@interface UITouch (ACPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTapCount:(NSUInteger)tapCount;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)_setIsFirstTouchForView:(BOOL)firstTouchForView;
- (void)setIsTap:(BOOL)isTap;
@end

@interface UIEvent (ACPrivate)
- (void)_setTimestamp:(NSTimeInterval)timestamp;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_clearTouches;
@end


@interface ACTouchEngine ()
// 每個 fingerIndex 保留一個 UITouch，供 down→up 沿用
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UITouch *> *touches;
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
        _touches = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - 目標視窗（遊戲的視窗，非懸浮視窗）

- (UIWindow *)targetWindow {
    UIApplication *app = [UIApplication sharedApplication];
    Class overlayClass = NSClassFromString(@"ACOverlayWindow");
    UIWindow *best = nil;

    NSArray<UIWindow *> *windows = app.windows;
    for (UIWindow *w in windows) {
        if (overlayClass && [w isKindOfClass:overlayClass]) continue;
        if (w.hidden || w.alpha <= 0.01) continue;
        if (!best || w.windowLevel >= best.windowLevel) best = w;
    }
    if (!best) {
        for (UIWindow *w in windows) {
            if (overlayClass && [w isKindOfClass:overlayClass]) continue;
            best = w; break;
        }
    }
    return best;
}

#pragma mark - 送出一個相位的觸控

- (void)sendTouchAtPoint:(CGPoint)point
             fingerIndex:(uint32_t)fingerIndex
                   phase:(UITouchPhase)phase {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *window = [self targetWindow];
    if (!window) return;

    NSTimeInterval ts = [[NSProcessInfo processInfo] systemUptime];
    UIView *hitView = [window hitTest:point withEvent:nil] ?: window;

    NSNumber *key = @(fingerIndex);
    UITouch *touch = self.touches[key];

    if (phase == UITouchPhaseBegan || !touch) {
        touch = [[UITouch alloc] init];
        self.touches[key] = touch;
        if ([touch respondsToSelector:@selector(setWindow:)]) [touch setWindow:window];
        if ([touch respondsToSelector:@selector(setView:)]) [touch setView:hitView];
        if ([touch respondsToSelector:@selector(setTapCount:)]) [touch setTapCount:1];
        if ([touch respondsToSelector:@selector(_setIsFirstTouchForView:)]) [touch _setIsFirstTouchForView:YES];
        if ([touch respondsToSelector:@selector(setIsTap:)]) [touch setIsTap:YES];
        if ([touch respondsToSelector:@selector(_setLocationInWindow:resetPrevious:)])
            [touch _setLocationInWindow:point resetPrevious:YES];
    } else {
        if ([touch respondsToSelector:@selector(setWindow:)]) [touch setWindow:window];
        if ([touch respondsToSelector:@selector(setView:)]) [touch setView:hitView];
        if ([touch respondsToSelector:@selector(_setLocationInWindow:resetPrevious:)])
            [touch _setLocationInWindow:point resetPrevious:NO];
    }

    if ([touch respondsToSelector:@selector(setTimestamp:)]) [touch setTimestamp:ts];
    if ([touch respondsToSelector:@selector(setPhase:)]) [touch setPhase:phase];

    if (![app respondsToSelector:@selector(_touchesEvent)]) return;
    UIEvent *event = [app _touchesEvent];
    if (!event) return;

    if ([event respondsToSelector:@selector(_clearTouches)]) [event _clearTouches];
    if ([event respondsToSelector:@selector(_setTimestamp:)]) [event _setTimestamp:ts];
    if ([event respondsToSelector:@selector(_addTouch:forDelayedDelivery:)])
        [event _addTouch:touch forDelayedDelivery:NO];

    [app sendEvent:event];

    if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) {
        [self.touches removeObjectForKey:key];
    }
}

#pragma mark - Public

- (void)touchDownAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self touchDownAtPoint:point fingerIndex:fingerIndex]; });
        return;
    }
    [self sendTouchAtPoint:point fingerIndex:fingerIndex phase:UITouchPhaseBegan];
}

- (void)touchMoveToPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self touchMoveToPoint:point fingerIndex:fingerIndex]; });
        return;
    }
    [self sendTouchAtPoint:point fingerIndex:fingerIndex phase:UITouchPhaseMoved];
}

- (void)touchUpAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self touchUpAtPoint:point fingerIndex:fingerIndex]; });
        return;
    }
    [self sendTouchAtPoint:point fingerIndex:fingerIndex phase:UITouchPhaseEnded];
}

- (void)tapAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    [self touchDownAtPoint:point fingerIndex:fingerIndex];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self touchUpAtPoint:point fingerIndex:fingerIndex];
    });
}

@end
