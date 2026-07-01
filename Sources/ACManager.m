#import "ACManager.h"
#import "ACTouchEngine.h"

@implementation ACClickPoint
+ (instancetype)pointAt:(CGPoint)p intervalMs:(NSInteger)ms {
    ACClickPoint *cp = [ACClickPoint new];
    cp.point = p;
    cp.intervalMs = ms > 0 ? ms : 100;
    return cp;
}
@end


@interface ACManager ()
@property (nonatomic, strong) NSMutableArray<ACClickPoint *> *mutablePoints;
// 每個點位一條 GCD timer
@property (nonatomic, strong) NSMutableArray<dispatch_source_t> *timers;
@property (nonatomic, assign) BOOL running;
@end

@implementation ACManager

+ (instancetype)shared {
    static ACManager *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [ACManager new]; });
    return inst;
}

- (instancetype)init {
    if (self = [super init]) {
        _mutablePoints = [NSMutableArray array];
        _timers = [NSMutableArray array];
        _defaultIntervalMs = 100;
    }
    return self;
}

- (NSArray<ACClickPoint *> *)points { return [_mutablePoints copy]; }

#pragma mark - 點位管理

- (void)addPoint:(CGPoint)point {
    [_mutablePoints addObject:[ACClickPoint pointAt:point intervalMs:self.defaultIntervalMs]];
    if (self.running) [self restart];
}

- (void)removePointAtIndex:(NSUInteger)index {
    if (index >= _mutablePoints.count) return;
    [_mutablePoints removeObjectAtIndex:index];
    if (self.running) [self restart];
}

- (void)clearPoints {
    [_mutablePoints removeAllObjects];
    if (self.running) [self restart];
}

- (void)setInterval:(NSInteger)ms forPointAtIndex:(NSUInteger)index {
    if (index >= _mutablePoints.count) return;
    _mutablePoints[index].intervalMs = ms > 0 ? ms : 1;
    if (self.running) [self restart];
}

#pragma mark - 排程

- (void)start {
    if (self.running || _mutablePoints.count == 0) return;
    self.running = YES;

    for (ACClickPoint *cp in _mutablePoints) {
        uint32_t fingerIndex = (uint32_t)[_mutablePoints indexOfObject:cp] + 1;
        CGPoint p = cp.point;
        double intervalSec = MAX(cp.intervalMs, 1) / 1000.0;

        dispatch_source_t timer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer,
            dispatch_time(DISPATCH_TIME_NOW, 0),
            (uint64_t)(intervalSec * NSEC_PER_SEC),
            (uint64_t)(0.005 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(timer, ^{
            [[ACTouchEngine shared] tapAtPoint:p fingerIndex:fingerIndex];
        });
        dispatch_resume(timer);
        [_timers addObject:timer];
    }
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;
    for (dispatch_source_t timer in _timers) {
        dispatch_source_cancel(timer);
    }
    [_timers removeAllObjects];
}

- (void)restart {
    [self stop];
    [self start];
}

- (void)toggle {
    if (self.running) [self stop]; else [self start];
}

@end
