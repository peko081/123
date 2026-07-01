#import <UIKit/UIKit.h>
#import "Sources/ACOverlayWindow.h"

// dylib 載入時自動執行（無論越獄 Substrate 載入或自行注入皆會觸發）。
%ctor {
    @autoreleasepool {
        // 只在有 UI 的 App 進程中啟動懸浮面板
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([UIApplication sharedApplication]) {
                [ACOverlayWindow show];
            } else {
                // App 尚未完成啟動，監聽啟動完成通知
                [[NSNotificationCenter defaultCenter]
                    addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                    queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [ACOverlayWindow show];
                    }];
            }
        });
    }
}
