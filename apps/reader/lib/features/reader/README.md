# 阅读器接入边界

`ReaderScreen` 接受 `ChapterManifest`、同一运行代次的 `PageProvider` 和可选逻辑位置。它不会直接访问 Source 的原始图片 URL；图像获取、正文处理、取消与资源销毁由 Provider 负责。默认图片视图消费受管理的 Web 资源 URL 或原生临时文件，退出窗口同时清除 Flutter 解码缓存。

目前已具备：单页/双页、封面与横图独占、RTL 展示、竖向连续/Webtoon、局部缩放、可聚焦缩放按钮、键盘与可见翻页按钮、稳定页身份及旋转/布局恢复、清单变化提示和有界图片窗口。UI 只在逻辑页/窗口或状态变化时重建，普通滚动位置以原图内归一化偏移传给 `onPositionChanged`；业务层负责节流持久化。

`PageProvider.cancel` 的完成必须表示生产已停止；即使图片迟到，调度器也会释放它。`release` 必须确认对应对象 URL、临时文件及处理资源已释放。调度器等待清理确认后才启动新生产，清理失败时停止新请求。平台 Provider 仍需独立限制网络、正文处理和解码临时缓冲。

章节入口现在调用原 Source 的 pages，保留 Java Page 会话；`ChapterPageProvider` 将逻辑页键映射到 opaque Page 引用，供真实 ReaderScreen 使用。资源携带的尺寸会更新布局，保留内容版本、当前逻辑页和归一化偏移。没有稳定 page URL 时，页键绑定完整内容版本，清单变化后明确按页码提示恢复。

调度器与显示组件分别持有资源。ReaderResourcePool 等待普通图片和缩放弹窗的显示引用全部撤销、帧结束及 Flutter ImageProvider 缓存清理后，才向 Source 确认释放；章节关闭等待该过程完成。Web 只显示受管 Blob URL，Native 只允许受管文件；本阶段 Native 图片获取明确不支持。

解码像素预算属于估算，不能作为实测进程/GPU内存；已知超过预算的巨图会明确拒绝显示。尚未实现超长图降采样/分片、裁白、完整阅读设置、章节接续和进度存储。真机触控、能耗、实际合计峰值与首图需要 P0-C 验收。

`test/reader` 的 Provider/渲染夹具只属于开发测试；当前未增加测试漫画导航、用户文件导入或假源入口。
