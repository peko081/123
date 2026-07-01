#import <UIKit/UIKit.h>

/// 單一連點點位
@interface ACClickPoint : NSObject
@property (nonatomic, assign) CGPoint point;
/// 每次點擊間隔（毫秒）
@property (nonatomic, assign) NSInteger intervalMs;
+ (instancetype)pointAt:(CGPoint)p intervalMs:(NSInteger)ms;
@end


/// 連點排程管理器：管理點位清單、啟動/停止、各點獨立計時。
@interface ACManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<ACClickPoint *> *points;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// 全域預設間隔（毫秒），新增點位時採用。
@property (nonatomic, assign) NSInteger defaultIntervalMs;

- (void)addPoint:(CGPoint)point;
- (void)removePointAtIndex:(NSUInteger)index;
- (void)clearPoints;
- (void)setInterval:(NSInteger)ms forPointAtIndex:(NSUInteger)index;

- (void)start;
- (void)stop;
- (void)toggle;

@end
