# 同步裁白验证

2026-11-06，裁白已从 Protobuf、Worker API + D1 接入正式 Flutter 设置和 Reader，默认关闭。全局默认、漫画继承/显式 false/true 和确认后应用共用现有设置链路，设计见[阅读设置](../design/reader-settings.md)。

## 协议与权威状态

- 正式 Protobuf-ES / Google Dart 生成模型与 ProtoJSON 的 10 项双向 golden 通过，包含全局 true 和 optional 显式 false。
- 合同 10 项与官方 Cloudflare Vitest / 真实 workerd 状态 32 项通过，核对默认 false、全局 true 被漫画 false 覆盖、清空继承、非法类型无写入、幂等与 CAS。D1 有效设置输出真正的 JSON bool。
- 设置数据回归包含字段逐项解析、presence、有效合并和原请求重试；没有另建客户端权威配置。

## UI 与实际像素

正式设置组件 11 项通过，扩展原导航组合核对全局开启、漫画明确关闭、清空后继承、快捷模式/页组保存保留裁白、切章/重开及 480×800 下待确认原 UUID/正文/CAS 重试。确认快照更新当前 Reader，不替换图片资源或章节。

图片、资源 pool 与设置数据的联合回归 20 项通过。真实 PNG 在 Flutter widget 引擎中经同一 ImageStream 实际解码，验证白边 ROI、近白、全白、彩边和透明边；开关及缓存 ROI 复用同一 codec。暂停不保留额外动画监听，卸载后不发布迟到结果；pending 像素工作在组件卸载后继续持有 pool pin，完成后仅释放一次。

Reader 回归 29 项通过。受控 ROI 组合验证待定观察门、长图有效末端、RTL 重分组、连续/Webtoon/zoom/窗口变化、原图二维锚、完整解码预算及非法/旧尺寸/旧 generation/旧 provider 回调拒绝。另有真实 PNG 临时文件经默认 `buildResourceImage → FileImage → Flutter 解码 → 自动 ROI → Reader` 路径，确认内容末端原图 y≈0.77/x≈0.775、关闭裁白后的整图末端与原图锚保持；文件、ImageCache 及资源均在结束后清理。

裁白直接调用 `image 4.12.0` 的 findTrim，长边最多 1024 的样本、近白角、0.04 颜色容差和两采样像素余量属于启发式。显示裁剪不重编码，UI 的原完整解码预算不变。工程组件证据不等于浏览器、Native App、真实 Source 在线或真机性能。

## 集中工程与剩余门槛

- `pnpm format` 与完整 `pnpm format:check` 通过，覆盖所有项目自有语言。
- `pnpm check` 完整通过：生成一致性、portable 格式、严格类型、依赖层级、384 项 Vitest、10 项协议 golden 与全部工具回归。
- `pnpm flutter:check` 完整通过：reader_core 22、source_runtime 42、客户端 357 项，三个项目静态分析无问题。
- `pnpm build` 通过：Web/Native runtime 资源、Flutter Web 和 Worker/Static Assets 正式构建成功。本轮未构建或运行新的 iOS/Android App。

只读复核另补齐“暂停时开启裁白”边界：重新取得缓存帧后立即停止额外监听，使用已克隆帧继续采样，不等待异步像素读取完成才暂停。原图片组件回归增加读取期间无监听断言，定向六项及上述完整 Flutter 回归通过。

```sh
pnpm test:protocol
pnpm exec vitest run packages/contracts/test/business-state.test.ts apps/api/test/state-workerd.test.ts
cd apps/reader
flutter test test/settings/ test/reader/resource_image_test.dart test/reader/resource_pool_test.dart test/data/settings_repository_test.dart test/reader/reader_screen_test.dart
```

全库入口为 `pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check` 和 `pnpm build`。临时日志位于忽略的 `.local/crop-*.log`、`.local/reader-crop-*.log` 与 `/private/tmp/karuyomi-crop-settings-regression.log`。

后续全局裁白开关的双 Web 与双 iOS 顺序读回、新文档/进程恢复分项见[设置记录](reader-settings.md)；实际裁白效果、漫画覆盖、生产 Access、浏览器/Web GPU 读取、其余平台与真机手势和性能仍须分别验收。本轮不部署生产，不能把工程通过当作完整 P1/P2 验收；自定义封面已继续接入，见[对应记录](custom-covers.md)。
