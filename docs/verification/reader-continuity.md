# 阅读连续性与有界下一章准备

2026-11-03，正式 Flutter 路由保留 Source 原序/反序与重复章节，不按空/零/小数编号排序或丢弃同 URL 的出现。稳定 URL 键包含漫画/Source 作用域；重复 URL 使用带漫画范围的列表快照与 occurrence，列表变化后不猜测对应关系。

切章在同一路由完成。新页面会话可以先取得，但新 Reader 叶必须等待旧 scheduler、图片 pins、取消和 provider 关闭 ACK。路由持有尚未挂载的新 provider，退出时负责关闭它；pages 迟到结果也只清理，不重新打开页面。

下一章只准备页面会话，不取得图片：当前章加至多一个邻章会话。末页实际 Flutter image frame 已显示、当前窗口含取消/释放 ACK 完全空闲，且 catalog/Source 空闲后自动尝试一次；失败不循环后台重试，显式下一章仍可重新获取。顺序改变或退出只标记旧请求无用，等待活动普通 Source 调用返回后关闭，不通过取消它销毁当前 generation。

关闭失败不是已释放：保留失败 provider 所有权并阻止继续 prepare/take；未确认清理前不再占新会话。分页缩放/平移时保守地不宣称完整 observed/atEnd，避免把被裁剪的末页当成已显示；重置后重新报告视口。

相关 34 项 Flutter 回归与 10 项核心调度回归通过，覆盖迟到 pages、挂载前退出、实际 frame 与驻留资源的区别、双页缩放裁剪、拒绝关闭 ACK 后不再新开会话，以及取消/释放未完成时 scheduler 不报告 idle。它们使用产品组件与受控 Provider，尚不代表实际 Source 连续切章、进度落盘、生产 Access 或真机验收。P0/P1 状态见[计划目录](../plan/README.md)。

2026-11-04，第三里程碑已将本地 Drift 进度接入目录/详情/Reader，相关 reader/browse/widget 共 47 项回归通过，包含真实 SQLite 文件关闭重开恢复章节、方向及页内偏移。完成状态仅由实际末页观察后的明确操作推进，邻章准备仍不写进度。该文件恢复分项与上述真实 Source 连续切章/设备门分开，详见[进度记录](local-progress.md)。

2026-11-04，真实 Flutter Web 与原版 Source 已通过连续切章、关标签页重开后的章节/当前页/最远页/顺序恢复，见[Web 产品进度记录](reader-progress-web.md)；浏览器进程退出与 Native 应用重启仍待验收。
