#import "ACTouchEngine.h"
#import <mach/mach_time.h>

#pragma mark - IOKit / IOHIDEvent 私有 API

typedef uint32_t IOHIDDigitizerTransducerType;
typedef double IOHIDFloat;
typedef struct __IOHIDEvent *IOHIDEventRef;
#ifndef IOOptionBits
typedef uint32_t IOOptionBits;
#endif

enum {
    kIOHIDDigitizerEventRange    = 1 << 0,
    kIOHIDDigitizerEventTouch    = 1 << 1,
    kIOHIDDigitizerEventPosition = 1 << 2,
};
#define kIOHIDDigitizerTransducerTypeHand 2
#define kIOHIDEventFieldDigitizerIsDisplayIntegrated 0x0b0017

extern IOHIDEventRef IOHIDEventCreateDigitizerEvent(
    CFAllocatorRef allocator, uint64_t timeStamp,
    IOHIDDigitizerTransducerType type, uint32_t index, uint32_t identity,
    uint32_t eventMask, uint32_t buttonMask,
    IOHIDFloat x, IOHIDFloat y, IOHIDFloat z,
    IOHIDFloat tipPressure, IOHIDFloat twist,
    boolean_t range, boolean_t touch, IOOptionBits options);

extern IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(
    CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t index, uint32_t identity, uint32_t eventMask,
    IOHIDFloat x, IOHIDFloat y, IOHIDFloat z,
    IOHIDFloat tipPressure, IOHIDFloat twist,
    boolean_t range, boolean_t touch, IOOptionBits options);

extern void IOHIDEventSetIntegerValue(IOHIDEventRef event, uint32_t field, int value);
extern void IOHIDEventAppendEvent(IOHIDEventRef event, IOHIDEventRef childEvent, IOOptionBits options);
extern void IOHIDEventSetSenderID(IOHIDEventRef event, uint64_t senderID);

#pragma mark - UIKit 私有 API

@interface UIApplication (ACPrivate)
- (UIEvent *)_touchesEvent;
- (void)_enqueueHIDEvent:(IOHIDEventRef)event;
@end

@interface UITouch (ACPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTapCount:(NSUInteger)tapCount;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)_setIsFirstTouchForView:(BOOL)firstTouchForView;
- (void)_setHidEvent:(IOHIDEventRef)event;
@end

@interface UIEvent (ACPrivate)
- (void)_setTimestamp:(NSTimeInterval)timestamp;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_clearTouches;
@end


@interface ACTouchEngine ()
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
        _deliveryMode = ACDeliveryModeUITouch;
    }
    return self;
}

#pragma mark - 目標視窗

- (UIWindow *)targetWindow {
    UIApplication *app = [UIApplication sharedApplication];
    Class overlayClass = NSClassFromString(@"ACOverlayWindow");
    UIWindow *best = nil;
    for (UIWindow *w in app.windows) {
        if (overlayClass && [w isKindOfClass:overlayClass]) continue;
        if (w.hidden || w.alpha <= 0.01) continue;
        if (!best || w.windowLevel >= best.windowLevel) best = w;
    }
    if (!best) {
        for (UIWindow *w in app.windows) {
            if (overlayClass && [w isKindOfClass:overlayClass]) continue;
            best = w; break;
        }
    }
    return best;
}

#pragma mark - IOHIDEvent 建立

- (CGPoint)normalizePoint:(CGPoint)point {
    UIScreen *screen = [UIScreen mainScreen];
    CGPoint fixed = [screen.coordinateSpace convertPoint:point
                                       toCoordinateSpace:screen.fixedCoordinateSpace];
    CGRect b = screen.fixedCoordinateSpace.bounds;
    if (b.size.width <= 0 || b.size.height <= 0) return CGPointZero;
    CGFloat nx = fixed.x / b.size.width;
    CGFloat ny = fixed.y / b.size.height;
    nx = MAX(0, MIN(1, nx));
    ny = MAX(0, MIN(1, ny));
    return CGPointMake(nx, ny);
}

// 回傳一個新的 IOHIDEvent（呼叫端負責 CFRelease）
- (IOHIDEventRef)createHIDEventAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex touch:(BOOL)touch {
    CGPoint n = [self normalizePoint:point];
    uint64_t ts = mach_absolute_time();
    uint32_t mask = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventPosition;

    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, ts, kIOHIDDigitizerTransducerTypeHand, 0, 0,
        mask, 0, n.x, n.y, 0, 0, 0, touch, touch, 0);
    if (!parent) return NULL;
    IOHIDEventSetIntegerValue(parent, kIOHIDEventFieldDigitizerIsDisplayIntegrated, 1);
    IOHIDEventSetSenderID(parent, 0x8000000817319375);

    IOHIDEventRef finger = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, ts, fingerIndex, 2, mask,
        n.x, n.y, 0, touch ? 1 : 0, 0, touch, touch, 0);
    if (finger) {
        IOHIDEventAppendEvent(parent, finger, 0);
        CFRelease(finger);
    }
    return parent;
}

#pragma mark - 派送

- (void)deliverAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex phase:(UITouchPhase)phase {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self deliverAtPoint:point fingerIndex:fingerIndex phase:phase]; });
        return;
    }

    BOOL isTouch = (phase != UITouchPhaseEnded && phase != UITouchPhaseCancelled);
    IOHIDEventRef hid = [self createHIDEventAtPoint:point fingerIndex:fingerIndex touch:isTouch];

    // --- 方式一：合成 UITouch（附掛 HID 背景事件）+ sendEvent ---
    if (self.deliveryMode == ACDeliveryModeUITouch || self.deliveryMode == ACDeliveryModeBoth) {
        [self sendUITouchAtPoint:point fingerIndex:fingerIndex phase:phase hid:hid];
    }

    // --- 方式二：純 IOHIDEvent enqueue ---
    if (self.deliveryMode == ACDeliveryModeHID || self.deliveryMode == ACDeliveryModeBoth) {
        UIApplication *app = [UIApplication sharedApplication];
        if (hid && [app respondsToSelector:@selector(_enqueueHIDEvent:)]) {
            [app _enqueueHIDEvent:hid];
        }
    }

    if (hid) CFRelease(hid);
}

- (void)sendUITouchAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex phase:(UITouchPhase)phase hid:(IOHIDEventRef)hid {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *window = [self targetWindow];
    if (!window) return;
    NSTimeInterval ts = [[NSProcessInfo processInfo] systemUptime];
    UIView *hitView = [window hitTest:point withEvent:nil] ?: window;

    NSNumber *key = @(fingerIndex);
    UITouch *touch = self.touches[key];
    BOOL isBegin = (phase == UITouchPhaseBegan) || !touch;

    if (isBegin) {
        touch = [[UITouch alloc] init];
        self.touches[key] = touch;
    }
    if ([touch respondsToSelector:@selector(setWindow:)]) [touch setWindow:window];
    if ([touch respondsToSelector:@selector(setView:)]) [touch setView:hitView];
    if ([touch respondsToSelector:@selector(setTapCount:)]) [touch setTapCount:1];
    if ([touch respondsToSelector:@selector(_setLocationInWindow:resetPrevious:)])
        [touch _setLocationInWindow:point resetPrevious:isBegin];
    if (isBegin && [touch respondsToSelector:@selector(_setIsFirstTouchForView:)])
        [touch _setIsFirstTouchForView:YES];
    if ([touch respondsToSelector:@selector(setTimestamp:)]) [touch setTimestamp:ts];
    if (hid && [touch respondsToSelector:@selector(_setHidEvent:)]) [touch _setHidEvent:hid];
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
    [self deliverAtPoint:point fingerIndex:fingerIndex phase:UITouchPhaseBegan];
}
- (void)touchMoveToPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    [self deliverAtPoint:point fingerIndex:fingerIndex phase:UITouchPhaseMoved];
}
- (void)touchUpAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    [self deliverAtPoint:point fingerIndex:fingerIndex phase:UITouchPhaseEnded];
}

- (void)tapAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    [self touchDownAtPoint:point fingerIndex:fingerIndex];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self touchUpAtPoint:point fingerIndex:fingerIndex];
    });
}

- (void)testTapAtCenter {
    UIWindow *w = [self targetWindow];
    CGPoint c = w ? CGPointMake(CGRectGetMidX(w.bounds), CGRectGetMidY(w.bounds))
                  : CGPointMake(200, 400);
    [self tapAtPoint:c fingerIndex:99];
}

- (NSString *)diagnostics {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *w = [self targetWindow];
    NSString *modeStr = (self.deliveryMode == ACDeliveryModeUITouch) ? @"UITouch+HID背景" :
                        (self.deliveryMode == ACDeliveryModeHID) ? @"純HID" : @"兩者";
    UITouch *probe = [[UITouch alloc] init];
    return [NSString stringWithFormat:
        @"模式:%@\n目標視窗:%@\n_touchesEvent:%@ _enqueueHID:%@\n_setHidEvent:%@ setPhase:%@\n_addTouch:%@ setWindow:%@",
        modeStr,
        w ? NSStringFromClass([w class]) : @"(無)",
        [app respondsToSelector:@selector(_touchesEvent)] ? @"Y" : @"N",
        [app respondsToSelector:@selector(_enqueueHIDEvent:)] ? @"Y" : @"N",
        [probe respondsToSelector:@selector(_setHidEvent:)] ? @"Y" : @"N",
        [probe respondsToSelector:@selector(setPhase:)] ? @"Y" : @"N",
        [[UIEvent new] respondsToSelector:@selector(_addTouch:forDelayedDelivery:)] ? @"Y" : @"N",
        [probe respondsToSelector:@selector(setWindow:)] ? @"Y" : @"N"];
}

@end
