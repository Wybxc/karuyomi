# Bitmap 所有权与自然回收

## 实现与边界

Bitmap 现在实际持有 opaque JSO lease，取 surface ID 时同步验证该对象确由 bridge 创建，并通过 WeakRef.deref 保持本 JavaScript job 的活引用。Surface Map 只弱持 lease；FinalizationRegistry 的 held value 只有单调 surface ID，回调仅执行同步、幂等 retire，不进入 Fiber/异步 Java 桥。Canvas 保持对 Java Bitmap 的正常强引用。

End 仅回收该操作创建但尚未交给 Java 的 surface，不能扫描删除 Source 仍持有的 Bitmap。预算不足或新操作开始时只回收 WeakRef 已清空的 owner；浏览器编码已有 pins，retire 后继续计费至 convertToBlob 终态，再清空画布及释放 reservation。显式 recycle 同样走这个生命周期，重复调用不重复释放。

Bitmap.copy 的像素复制保持独立；先完成新 b 的内部绘制，再私有设置最终 mutable 标志并返回同一个包装，不再为同一新 surface 创建第二个包装。原 Android NATIVE 对照同时纠正同尺寸缩放：immutable 源可返回自身，mutable 源必须产生独立 mutable 副本。

TeaVM 固定版本已有 JSWeakRef、JSFinalizationRegistry 及 Cleaner；本实现直接使用标准浏览器 API 和正式 JSO overlay，不额外叠加 Java registry。固定上游 Cleaner/WeakReference 的 GC 测试跳过 JavaScript，不能以存在 API 代替真实 TeaVM/browser 验证。

GC 的时机由引擎决定。即使 Java 对象已不可达，也不能保证何时清除 WeakRef 或调用 callback；OffscreenCanvas 的外部像素内存也不保证及时触发 JavaScript GC。因此现有内存和64-surface预算仍可在延迟回收时拒绝新分配，本阶段不承诺永不拒绝或固定回收时延。

## 正式测试入口

- `tools/teavm/BitmapLifetimeScenarios.java`：原 Android 与 TeaVM 共享13项复制/immutable/缩放/回收契约；另提供故意不 recycle 的局部对象和静态 Bitmap/Canvas-only 持有入口。
- `tools/teavm/fixtures/bitmap-lifetime/BitmapLifetimeProbe.java`：真实 TeaVM Fiber 入口；与 TextLayoutScenarios101项同跑。
- `packages/runtime-host/test/bitmap-lifetime-browser-suite.ts`：真实 Canvas lease机制、存活64 owner预算拒绝、编码pin及有限自然GC观测。
- `packages/runtime-host/test/bitmap-lifetime-java-browser-suite.ts`：真实编译 Java 对象跨任务持有、局部未recycle对象回收、保留对象继续使用及丢弃后回收。

```sh
pnpm typecheck:bridges
pnpm typecheck:tools
node tools/teavm/check-text-layout.ts
```

Android runner继续固定 Robolectric4.17/API35/NATIVE、SDK与产物SHA，清理生成src/target后复制共同场景，断言原Android框架及native shadows；没有seed、owned Android替身或AWT。

浏览器gate用正式prepareSources/compileExtension生成owned class覆盖的TeaVM0.16 JS，将测试POM mainClass设为BitmapLifetimeProbe；拼接正式compileBridge('graphics')产物、该Java入口JS与对应严格TS driver，在Worker执行。临时Maven工程、HTTP server及报告留在ignored .local/bitmap-lifetime{,-java}/，不将临时工程作为维护源码。测试不改官方扩展JAR。

## 实测状态

2026-11-04，macOS arm64，固定官方 Android NATIVE runner 从维护源码重新生成工程后通过 Bitmap 13 项与 Text 101 项；原 Android 图片指标仍为 1000×140、9536 非白像素、PNG 12820 字节。

Codex 内置浏览器 Chrome 156 实跑最新真实 Canvas 五组全部通过：活 owner 跨 End 与假/重复 owner 拒绝；显式 recycle 幂等与旧 owner 拒绝；未交付结果 End 清理；64 个活 owner 时拒绝新分配且不逐出；编码过程中 retire 保持 pin 和预算至迟到结果丢弃。另八个 adopted owner 没有显式 recycle，自然 GC 观测为 true、forced=false，账本全零。

同环境实际加载新编译 TeaVM 0.16 的 BitmapLifetimeProbe（JavaScript 809781 字节），通过共享 Bitmap13、Text101。TeaVM 文本指标仍为 1000×190、10468 非白像素、PNG 22876 字节；不同默认字体不声称与原 Android 像素等价。未 recycle 的局部 Bitmap 自然回收后，只剩静态 Bitmap 和仅由 Canvas 持有的 Bitmap 两个 surface，total/raster 均为 2048 字节；后续 Java 操作仍可读取像素和绘制。丢弃这两个真实 Java 引用后再观测自然回收，total/raster/surfaces/decoders/fonts/handles 全部为零。两次均 forced=false，没有用显式 recycle 代替自然回收。

Canvas 和 Java 门的单次观测分别约 16.4 ms、24.7/88.8 ms，只记录机制事实，不是时延分布或承诺。严格 bridge/tools 类型检查通过；机器报告、官方 oracle 日志及截图留在 ignored 验证目录。

## 原 Source 新材料复验

固定 `5148c60`，使用与旧门严格相同SHA的官方 xkcd JAR 重新AOT；新的host、bundle和材料完整身份见[Source记录](graphics-source-runtime.md#新生命周期材料的原-xkcd-source)。Codex内置Chrome156的正式两页门再次通过，第二页由未经修改的原TextInterceptor实际生成。其后同一真实pageKey连续获取、解码和释放80次，诊断记录恰好新增80个Java Bitmap lease；未注入recycle，处理中多次自然回收，观测峰值18 surfaces，成功跨过64次处理。

空闲最终回收没有固定时限：第一轮完成留17 surfaces/19448000字节，空闲15010ms没有再回收，原始失败报告已保留。第二轮留16 surfaces，空闲1532ms仍未归零；仅测试Worker每批分配/丢弃32768个普通JS对象后，5批观察到账本全零。没有显式GC API，但有测试分配压力，不能把forced=false写成无压力空闲保证。

原Source实际PNG编码的取消门另外通过：测试harness暂缓真实convertToBlob结果，取消时pending reservation仍保留；放行后返回cancelled、没有发布迟到图片、handles为0，并能在同一generation重新获取文字页。取消及恢复后的两个Bitmap在空闲1532ms未回收，22批同样的有界分配后观察到所有账本归零。详细计费、单次时间及诊断接线见Source记录；它们不是进程/GPU峰值或延时分布。

## 未完成门

生产Access、Native应用的Bitmap生命周期、所有HTTP/解码阶段的取消、长期负载、进程/GPU实际峰值仍须另验。本次取消覆盖受控的真实PNG编码等待阶段；普通对象分配压力下的最终回收与原Source80次处理事实分开记录，不保证所有引擎总会及时回收外部画布内存。旧926b93d的Source/UI证据继续保留，不能混用材料身份。

依据：[TeaVM JSO](https://teavm.org/docs/runtime/jso.html)、[固定上游 JSWeakRef](https://github.com/konsoletyper/teavm/blob/e87d452e4bd70c77b9e19314a46c3d6971c148b6/jso/apis/src/main/java/org/teavm/jso/core/JSWeakRef.java)、[固定上游 Cleaner](https://github.com/konsoletyper/teavm/blob/e87d452e4bd70c77b9e19314a46c3d6971c148b6/classlib/src/main/java/org/teavm/classlib/java/lang/ref/TCleaner.java)、[TC39 WeakRef处理模型](https://tc39.es/ecma262/multipage/executable-code-and-execution-contexts.html#sec-processing-model-of-weakref-and-finalizationregistry-targets)、[Android15 Bitmap](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-15.0.0_r1/graphics/java/android/graphics/Bitmap.java)。
