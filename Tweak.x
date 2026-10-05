// CamHook 日志版 + 可见横幅 —— 只观测，不碰任何画面
// 相机会话启动时在屏幕顶部弹一条横幅，证明插件已生效。
// 不定义任何自定义 ObjC 类，规避 A12+ 设备 ObjC 类注册时的 PAC 陷阱（SIGTRAP 秒退）。

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <os/log.h>

// ---- 顶部横幅（只用系统类，不建自定义类）----

static NSTimeInterval gLastBanner = 0;

static void CamHookShowBanner(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 节流：3 秒内只弹一次，避免 startRunning 被反复调用时刷屏
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (now - gLastBanner < 3.0) return;
        gLastBanner = now;

        // 找当前的 key window
        UIWindow *win = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { win = w; break; }
                }
            }
            if (win) break;
        }
        if (!win) win = UIApplication.sharedApplication.windows.firstObject;
        if (!win) return;

        CGFloat width = win.bounds.size.width - 24.0;
        CGFloat topY = win.safeAreaInsets.top > 0 ? win.safeAreaInsets.top : 44.0;

        UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(12, -90, width, 60)];
        banner.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        banner.layer.cornerRadius = 14.0;
        banner.clipsToBounds = YES;
        banner.userInteractionEnabled = NO;

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, width - 28, 60)];
        label.text = @"✓ CamHook 已接管相机回调";
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont boldSystemFontOfSize:16.0];
        label.numberOfLines = 2;
        [banner addSubview:label];
        [win addSubview:banner];

        // 滑入 -> 停 2 秒 -> 滑出移除
        [UIView animateWithDuration:0.35 animations:^{
            banner.frame = CGRectMake(12, topY + 8, width, 60);
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.35 animations:^{
                    banner.frame = CGRectMake(12, -90, width, 60);
                } completion:^(BOOL f2) {
                    [banner removeFromSuperview];
                }];
            });
        }];
    });
}

// ---- 相机会话启动：弹横幅 ----

%hook AVCaptureSession

- (void)startRunning {
    %orig;
    os_log(OS_LOG_DEFAULT, "[CamHook] AVCaptureSession startRunning -> 弹横幅");
    CamHookShowBanner();
}

%end

// ---- 视频输出委托注册：打日志（观测，不改画面）----

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    os_log(OS_LOG_DEFAULT, "[CamHook] setSampleBufferDelegate: %{public}@",
           NSStringFromClass(object_getClass(sampleBufferDelegate)));
    %orig;
}

%end

%ctor {
    os_log(OS_LOG_DEFAULT, "[CamHook] 日志+横幅版已加载（只观测，不改画面）");
}
