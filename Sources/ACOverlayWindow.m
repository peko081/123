#import "ACOverlayWindow.h"
#import "ACManager.h"
#import "ACTouchEngine.h"

#pragma mark - 穿透用根視圖

@class ACOverlayWindow;

@interface ACRootView : UIView
@property (nonatomic, weak) UIView *ball;
@property (nonatomic, weak) UIView *panel;
@property (nonatomic, assign) BOOL recording;
@property (nonatomic, copy) void (^onRecordPoint)(CGPoint p);
@end

@implementation ACRootView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];

    // 控制元件（懸浮球 / 面板）永遠可互動
    UIView *v = hit;
    while (v) {
        if (v == self.ball || v == self.panel) return hit;
        v = v.superview;
    }

    // 錄製模式：攔截空白處觸控以記錄座標
    if (self.recording) return self;

    // 其餘穿透給底層遊戲
    return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.recording && self.onRecordPoint) {
        CGPoint p = [[touches anyObject] locationInView:self];
        self.onRecordPoint(p);
    }
}

@end


#pragma mark - 懸浮視窗

@interface ACOverlayWindow ()
@property (nonatomic, strong) ACRootView *rootView;
@property (nonatomic, strong) UIView *ball;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) NSMutableArray<UIView *> *markers;

@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UILabel *intervalLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UILabel *debugLabel;
@end

@implementation ACOverlayWindow

+ (instancetype)shared {
    static ACOverlayWindow *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[ACOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    });
    return inst;
}

// 視窗層級穿透：空白處（命中視窗自身）一律放行給底層遊戲，
// 只有懸浮球 / 面板 / 錄製攔截層才吃觸控。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}

+ (void)show {
    // 延遲等待 UI 就緒
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[self shared] setup];
    });
}

- (void)setup {
    if (self.rootView) { self.hidden = NO; return; }

    self.windowLevel = UIWindowLevelAlert + 100;
    self.backgroundColor = [UIColor clearColor];

    // 綁定 windowScene（iOS 13+）
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                self.windowScene = (UIWindowScene *)scene;
                break;
            }
        }
    }

    self.markers = [NSMutableArray array];

    UIViewController *vc = [UIViewController new];
    ACRootView *root = [[ACRootView alloc] initWithFrame:self.bounds];
    root.backgroundColor = [UIColor clearColor];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    vc.view = root;
    self.rootViewController = vc;
    self.rootView = root;

    __weak typeof(self) weakSelf = self;
    root.onRecordPoint = ^(CGPoint p) {
        [[ACManager shared] addPoint:p];
        [weakSelf refreshMarkers];
        [weakSelf refreshUI];
    };

    [self buildBall];
    [self buildPanel];
    root.ball = self.ball;
    root.panel = self.panel;

    self.hidden = NO;
    [self makeKeyAndVisible];
    // 不搶奪按鍵焦點
    [self resignKeyWindow];
}

#pragma mark - 懸浮球

- (void)buildBall {
    UIView *ball = [[UIView alloc] initWithFrame:CGRectMake(20, 120, 56, 56)];
    ball.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.85];
    ball.layer.cornerRadius = 28;
    ball.layer.borderWidth = 2;
    ball.layer.borderColor = [UIColor whiteColor].CGColor;

    UILabel *lbl = [[UILabel alloc] initWithFrame:ball.bounds];
    lbl.text = @"連";
    lbl.textColor = [UIColor whiteColor];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.font = [UIFont boldSystemFontOfSize:20];
    [ball addSubview:lbl];

    [ball addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onBallPan:)]];
    [ball addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(onBallTap:)]];

    [self.rootView addSubview:ball];
    self.ball = ball;
}

- (void)onBallPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.rootView];
    CGPoint c = g.view.center;
    g.view.center = CGPointMake(c.x + t.x, c.y + t.y);
    [g setTranslation:CGPointZero inView:self.rootView];
}

- (void)onBallTap:(UITapGestureRecognizer *)g {
    self.panel.hidden = !self.panel.hidden;
    [self refreshUI];
}

#pragma mark - 設定面板

- (void)buildPanel {
    CGFloat maxH = MAX(240, self.bounds.size.height - 90);
    CGFloat panelH = MIN(466, maxH);
    UIScrollView *panel = [[UIScrollView alloc] initWithFrame:CGRectMake(20, 60, 250, panelH)];
    panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.82];
    panel.layer.cornerRadius = 12;
    panel.showsVerticalScrollIndicator = YES;
    panel.hidden = YES;

    CGFloat W = 226;
    CGFloat y = 12;

    self.countLabel = [self labelWithFrame:CGRectMake(12, y, W, 20) text:@"點位：0"];
    [panel addSubview:self.countLabel];
    y += 26;

    self.startButton = [self buttonWithFrame:CGRectMake(12, y, W, 38)
                                       title:@"▶ 開始"
                                       color:[UIColor systemGreenColor]
                                      action:@selector(onStart)];
    [panel addSubview:self.startButton];
    y += 44;

    self.recordButton = [self buttonWithFrame:CGRectMake(12, y, W, 38)
                                        title:@"＋ 錄製點位"
                                        color:[UIColor systemOrangeColor]
                                       action:@selector(onRecordToggle)];
    [panel addSubview:self.recordButton];
    y += 44;

    self.intervalLabel = [self labelWithFrame:CGRectMake(12, y, W, 20)
        text:[NSString stringWithFormat:@"間隔：%ld ms", (long)[ACManager shared].defaultIntervalMs]];
    [panel addSubview:self.intervalLabel];
    y += 22;

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(12, y, W, 28)];
    slider.minimumValue = 10;
    slider.maximumValue = 1000;
    slider.value = [ACManager shared].defaultIntervalMs;
    [slider addTarget:self action:@selector(onSlider:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:slider];
    y += 34;

    UILabel *modeTitle = [self labelWithFrame:CGRectMake(12, y, W, 18) text:@"派送方式："];
    [panel addSubview:modeTitle];
    y += 22;

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"UITouch", @"HID", @"兩者"]];
    self.modeControl.frame = CGRectMake(12, y, W, 30);
    self.modeControl.selectedSegmentIndex = [ACTouchEngine shared].deliveryMode;
    self.modeControl.selectedSegmentTintColor = [UIColor systemBlueColor];
    [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]} forState:UIControlStateNormal];
    [self.modeControl addTarget:self action:@selector(onModeChange:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:self.modeControl];
    y += 38;

    UIButton *test = [self buttonWithFrame:CGRectMake(12, y, W, 34)
                                     title:@"測試點擊（螢幕中央）"
                                     color:[UIColor systemPurpleColor]
                                    action:@selector(onTest)];
    [panel addSubview:test];
    y += 40;

    UIButton *clear = [self buttonWithFrame:CGRectMake(12, y, W, 32)
                                      title:@"清除全部"
                                      color:[UIColor systemRedColor]
                                     action:@selector(onClear)];
    [panel addSubview:clear];
    y += 38;

    self.debugLabel = [self labelWithFrame:CGRectMake(12, y, W, 96) text:@""];
    self.debugLabel.numberOfLines = 0;
    self.debugLabel.font = [UIFont systemFontOfSize:10];
    self.debugLabel.textColor = [UIColor systemGreenColor];
    [panel addSubview:self.debugLabel];
    y += 100;

    panel.contentSize = CGSizeMake(250, y);

    [self.rootView addSubview:panel];
    self.panel = panel;
}

- (UILabel *)labelWithFrame:(CGRect)frame text:(NSString *)text {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:14];
    return l;
}

- (UIButton *)buttonWithFrame:(CGRect)frame title:(NSString *)title
                        color:(UIColor *)color action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    b.backgroundColor = color;
    b.layer.cornerRadius = 8;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

#pragma mark - 動作

- (void)onStart {
    [[ACManager shared] toggle];
    [self refreshUI];
}

- (void)onRecordToggle {
    self.rootView.recording = !self.rootView.recording;
    [self refreshUI];
}

- (void)onSlider:(UISlider *)s {
    NSInteger ms = (NSInteger)s.value;
    [ACManager shared].defaultIntervalMs = ms;
    self.intervalLabel.text = [NSString stringWithFormat:@"間隔：%ld ms", (long)ms];
}

- (void)onClear {
    [[ACManager shared] clearPoints];
    [self refreshMarkers];
    [self refreshUI];
}

- (void)onModeChange:(UISegmentedControl *)c {
    [ACTouchEngine shared].deliveryMode = (ACDeliveryMode)c.selectedSegmentIndex;
    [self refreshUI];
}

- (void)onTest {
    [[ACTouchEngine shared] testTapAtCenter];
    [self refreshUI];
}

#pragma mark - UI 更新

- (void)refreshUI {
    BOOL running = [ACManager shared].running;
    [self.startButton setTitle:running ? @"⏸ 停止" : @"▶ 開始" forState:UIControlStateNormal];
    self.startButton.backgroundColor = running ? [UIColor systemRedColor] : [UIColor systemGreenColor];

    BOOL rec = self.rootView.recording;
    [self.recordButton setTitle:rec ? @"✓ 錄製中（點螢幕新增）" : @"＋ 錄製點位" forState:UIControlStateNormal];
    self.recordButton.backgroundColor = rec ? [UIColor systemTealColor] : [UIColor systemOrangeColor];

    self.countLabel.text = [NSString stringWithFormat:@"點位：%lu", (unsigned long)[ACManager shared].points.count];

    self.debugLabel.text = [[ACTouchEngine shared] diagnostics];
}

- (void)refreshMarkers {
    for (UIView *m in self.markers) [m removeFromSuperview];
    [self.markers removeAllObjects];

    NSArray<ACClickPoint *> *pts = [ACManager shared].points;
    [pts enumerateObjectsUsingBlock:^(ACClickPoint *cp, NSUInteger idx, BOOL *stop) {
        UIView *m = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
        m.center = cp.point;
        m.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.6];
        m.layer.cornerRadius = 15;
        m.userInteractionEnabled = NO; // 標記不攔截觸控

        UILabel *l = [[UILabel alloc] initWithFrame:m.bounds];
        l.text = [NSString stringWithFormat:@"%lu", (unsigned long)(idx + 1)];
        l.textColor = [UIColor whiteColor];
        l.textAlignment = NSTextAlignmentCenter;
        l.font = [UIFont boldSystemFontOfSize:13];
        [m addSubview:l];

        [self.rootView insertSubview:m belowSubview:self.ball];
        [self.markers addObject:m];
    }];
}

@end
