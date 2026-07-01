#import "ACTouchEngine.h"
#import <mach/mach_time.h>

#pragma mark - IOKit / IOHIDEvent 私有 API 宣告

typedef uint32_t IOHIDDigitizerTransducerType;
typedef double IOHIDFloat;
typedef struct __IOHIDEvent *IOHIDEventRef;
#ifndef IOOptionBits
typedef uint32_t IOOptionBits;
#endif

// 數位觸控事件遮罩
enum {
    kIOHIDDigitizerEventRange       = 1 << 0,
    kIOHIDDigitizerEventTouch       = 1 << 1,
    kIOHIDDigitizerEventPosition    = 1 << 2,
};

// transducer 類型：手（多指）
#define kIOHIDDigitizerTransducerTypeHand 2

// 事件欄位：是否為整合式顯示器
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

// UIApplication 私有：把 HID 事件塞進本進程事件迴圈
@interface UIApplication (ACPrivate)
- (void)_enqueueHIDEvent:(IOHIDEventRef)event;
- (void)handleKeyHIDEvent:(IOHIDEventRef)event;
@end


@implementation ACTouchEngine

+ (instancetype)shared {
    static ACTouchEngine *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [ACTouchEngine new]; });
    return inst;
}

#pragma mark - 座標正規化

// 數位觸控事件使用 0.0~1.0 的正規化座標，且以「實體直向」為基準。
// 用 fixedCoordinateSpace 轉換，可自動處理橫向 / 反向等各種螢幕方向。
- (CGPoint)normalizePoint:(CGPoint)point {
    UIScreen *screen = [UIScreen mainScreen];
    CGPoint fixed = [screen.coordinateSpace convertPoint:point
                                       toCoordinateSpace:screen.fixedCoordinateSpace];
    CGRect b = screen.fixedCoordinateSpace.bounds;
    if (b.size.width <= 0 || b.size.height <= 0) return CGPointMake(0, 0);
    CGFloat nx = fixed.x / b.size.width;
    CGFloat ny = fixed.y / b.size.height;
    if (nx < 0) nx = 0; else if (nx > 1) nx = 1;
    if (ny < 0) ny = 0; else if (ny > 1) ny = 1;
    return CGPointMake(nx, ny);
}

#pragma mark - 事件送出

- (void)postFingerEventAtPoint:(CGPoint)point
                   fingerIndex:(uint32_t)fingerIndex
                     eventMask:(uint32_t)eventMask
                         range:(BOOL)range
                         touch:(BOOL)touch {
    CGPoint n = [self normalizePoint:point];
    uint64_t timestamp = mach_absolute_time();

    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, timestamp,
        kIOHIDDigitizerTransducerTypeHand, 0, 0,
        eventMask, 0,
        n.x, n.y, 0, 0, 0,
        range, touch, 0);
    if (!parent) return;

    IOHIDEventSetIntegerValue(parent, kIOHIDEventFieldDigitizerIsDisplayIntegrated, 1);

    IOHIDEventRef finger = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, timestamp,
        fingerIndex, 2, eventMask,
        n.x, n.y, 0, 0, 0,
        range, touch, 0);
    if (finger) {
        IOHIDEventAppendEvent(parent, finger, 0);
        CFRelease(finger);
    }

    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(_enqueueHIDEvent:)]) {
        // 事件必須在主執行緒送出
        if ([NSThread isMainThread]) {
            [app _enqueueHIDEvent:parent];
            CFRelease(parent);
        } else {
            IOHIDEventRef captured = parent;
            dispatch_async(dispatch_get_main_queue(), ^{
                [app _enqueueHIDEvent:captured];
                CFRelease(captured);
            });
        }
    } else {
        CFRelease(parent);
    }
}

#pragma mark - Public

- (void)touchDownAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    uint32_t mask = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventPosition;
    [self postFingerEventAtPoint:point fingerIndex:fingerIndex eventMask:mask range:YES touch:YES];
}

- (void)touchMoveToPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    uint32_t mask = kIOHIDDigitizerEventPosition;
    [self postFingerEventAtPoint:point fingerIndex:fingerIndex eventMask:mask range:YES touch:YES];
}

- (void)touchUpAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    uint32_t mask = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventPosition;
    [self postFingerEventAtPoint:point fingerIndex:fingerIndex eventMask:mask range:NO touch:NO];
}

- (void)tapAtPoint:(CGPoint)point fingerIndex:(uint32_t)fingerIndex {
    [self touchDownAtPoint:point fingerIndex:fingerIndex];
    // 短暫停留讓 App 認得為一次點擊
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self touchUpAtPoint:point fingerIndex:fingerIndex];
    });
}

@end
