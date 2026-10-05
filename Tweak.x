// CamHook 日志版 —— 只观测相机回调，不碰任何画面
// 不定义任何自定义 ObjC 类，规避 A12+ 设备 ObjC 类注册时的 PAC 陷阱（SIGTRAP 秒退）。

#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <os/log.h>

// ---- 委托回调拦截（用 C 函数做 swizzle，不建类）----

typedef void (*CaptureIMP)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *);

// 记录每个被 hook 的类名 -> 原始实现
static NSMutableDictionary<NSString *, NSValue *> *gOrigIMPs;

static CaptureIMP CamHookLookupOrig(id obj) {
    Class cls = object_getClass(obj);
    while (cls) {
        NSValue *v = gOrigIMPs[NSStringFromClass(cls)];
        if (v) return (CaptureIMP)[v pointerValue];
        cls = class_getSuperclass(cls);
    }
    return NULL;
}

// 替身：只打日志，然后把真实画面原样放过去（%orig 等价）
static void CamHook_captureOutput(id self, SEL _cmd,
                                  AVCaptureOutput *output,
                                  CMSampleBufferRef sampleBuffer,
                                  AVCaptureConnection *connection) {
    CaptureIMP orig = CamHookLookupOrig(self);
    if (!orig) return;

    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    double seconds = CMTimeGetSeconds(pts);
    os_log(OS_LOG_DEFAULT,
           "[CamHook] didOutputSampleBuffer  pts=%{public}.4f  output=%{public}@",
           seconds, NSStringFromClass(object_getClass(output)));

    // 原样透传，一帧都不改
    orig(self, _cmd, output, sampleBuffer, connection);
}

static void CamHookSwizzle(id delegate) {
    if (!delegate) return;
    SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);

    // 找到真正实现该方法的类
    Class implCls = object_getClass(delegate);
    Method m = NULL;
    while (implCls) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(implCls, &count);
        for (unsigned int i = 0; i < count; i++) {
            if (method_getName(methods[i]) == sel) { m = methods[i]; break; }
        }
        if (methods) free(methods);
        if (m) break;
        implCls = class_getSuperclass(implCls);
    }
    if (!m || !implCls) {
        os_log(OS_LOG_DEFAULT, "[CamHook] 委托未实现 didOutputSampleBuffer:（可能走 photo 路径）");
        return;
    }

    NSString *key = NSStringFromClass(implCls);
    @synchronized (gOrigIMPs) {
        if (gOrigIMPs[key]) return;
        IMP origIMP = method_getImplementation(m);
        gOrigIMPs[key] = [NSValue valueWithPointer:origIMP];
        method_setImplementation(m, (IMP)CamHook_captureOutput);
    }
    os_log(OS_LOG_DEFAULT, "[CamHook] 已 hook 委托类: %{public}@", key);
}

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    os_log(OS_LOG_DEFAULT, "[CamHook] setSampleBufferDelegate: %{public}@",
           NSStringFromClass(object_getClass(sampleBufferDelegate)));
    CamHookSwizzle(sampleBufferDelegate);
    %orig;
}

%end

%ctor {
    gOrigIMPs = [NSMutableDictionary new];
    os_log(OS_LOG_DEFAULT, "[CamHook] 日志版已加载（只观测，不改画面）");
}
