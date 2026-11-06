# 图像适配与二维阅读位置验证

2026-11-06，阅读设置新增完整显示、适宽和适高，全局默认与逐漫画覆盖沿用 Protobuf、Worker API + D1 和服务端确认链路。阅读位置增加原图 x 与对应视口 x/y，保持原图 y、稳定页身份、epoch、当前/最远和显式完成语义。设计见[阅读设置](../design/reader-settings.md)。

## 协议、真实 D1 与数据

- 10 项协议 golden 通过，正式 Protobuf-ES / Google Dart codec 双向往返新增 fit 枚举、显式 CONTAIN 覆盖、HEIGHT、继承清空和非默认二维坐标；坐标越界与非有限值由业务校验拒绝。
- 合同 10 项与官方 Cloudflare Vitest / 真实 workerd 状态 32 项通过；新增组合核对默认 CONTAIN、覆盖 presence、清空继承、非法值无写入，以及二维 current/furthest 的 D1 保存、另一 API 调用方读回、列表和清单重排。原图 x 不加入最远进度排序。
- reader_core 全包 21 项、Dart 数据与阅读进度控制器 44 项通过；同页同 y 下仅改变原图 x、视口 x 或视口 y，599 ms 不写入、600 ms 节流确认。受控 Access 恢复组件 9 项通过，恢复 JSON 使用完整四坐标并拒绝旧形状或非法坐标。

## 正式阅读行为

三种适配统一使用 UI 实际解码尺寸；分页页组、连续/Webtoon 和独立图片放大窗口都应用当前偏好。适宽长图可纵向平移，适高宽图可横向平移；双页适高按实际宽度组成页组。超视口平移期间不抢翻页，显式导航保留。没有新增 Source 预解码或图片元数据通道。

用户滚动或平移时取视口顶部阅读起始侧最近的真实可见图像点，保存原图 x/y 及该点在视口中的归一化 x/y。布局、适配、真实尺寸学习、窗口变化和重开按同一点恢复，约束到新布局可达范围；占位比例不改写持久锚的视口位置。只有已确认重新阅读的明确导航才按当前方向定位起始边，普通恢复不镜像原图 x。

观察来自当前 generation 已解码图像的实际矩形与视口交集，缩放和平移后仍可观察。最后一页底边与阅读末边的交点实际可见才允许自然完成入口；长图顶部或宽图起始边显示不代表已读完。完成仍需显式操作，不因切换适配自动标已读。

## 组件与正式入口

设置 11 项通过，包含原三项正式导航组合的适配扩展：全局适宽、漫画适高、显式完整显示与清空继承、快捷模式/页组保存保留 fit、切章/重开，以及 480×800 表单的截断 ACK 原 UUID/正文/CAS 重试。已确认重新阅读按当前阅读方向定位起始边，迟到结果仍须绑定同一进度控制器、身份和 Source 会话。

`reader_screen_test.dart` 24 项通过（原 19 加 5 个组合），覆盖长图适宽和宽图适高的内容可达与真实末端、LTR/RTL、双页平移、连续横向浏览和 Webtoon 完整显示；非默认二维锚经未知尺寸学习、fit、页组、窗口尺寸、缩放、重开与显式请求保持。增加已知尺寸但延迟同尺寸图片帧的视口锚校正，保留下一帧发布观察的时效；切换到实际相同页组仍结束恢复状态。重复帧不反复恢复，模态放大窗口关闭后重新发布主阅读视口，资源最终释放。

组件采用受控图片帧通知，不作为实际图片解码或目标设备证据。正式进度导航 5 项在整库回归通过，其中已增加原图 x/y 与视口 x/y 的远端明确重开、新客户端续读恢复断言；该入口使用受控 API supplier，与真实独立客户端分别计证据。

## 集中工程与剩余门槛

- `pnpm format` 与完整 `pnpm format:check` 通过，覆盖全部项目自有语言。
- `pnpm check` 完整通过：生成一致性、portable 格式、严格类型与依赖层级、384 项 Vitest、10 项协议 golden 及全部工具回归。
- `pnpm flutter:check` 完整通过：reader_core 21、source_runtime 42、客户端 349 项，三个项目静态分析无问题。
- `pnpm build` 通过：Web/Native runtime 资源、Flutter Web 和 Worker/Static Assets 正式构建成功；没有构建或运行新的 iOS/Android App。

测试使用受控 supplier/图像组件的部分不作为实际浏览器、Native 或真实图片性能证据。

```sh
pnpm test:protocol
pnpm exec vitest run packages/contracts/test/business-state.test.ts apps/api/test/state-workerd.test.ts
cd apps/reader
flutter test test/settings/ test/reader/reading_progress_navigation_test.dart test/reader/reader_screen_test.dart
```

全库入口为 `pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check` 和 `pnpm build`。临时日志保留在忽略的 `.local/fit-*.log` 与 `.local/reader-fit-screen.log`。

后续全局适配偏好的双 Web 与双 iOS 顺序读回、新文档/进程恢复分项见[设置记录](reader-settings.md)；实际阅读二维位置、生产 Access、其余平台和真机手势仍须分别验收。本轮不部署生产；裁白和自定义封面已继续接入，分别见[裁白](reader-crop.md)与[自定义封面](custom-covers.md)，不把工程通过当作完整 P1/P2 验收。
