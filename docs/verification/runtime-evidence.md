# 运行时验证要点

以下为 2026-11-03 的关键观察，代码范围对应 `ea6606c` 及后续正式集成回归。原始请求流水、逐块计时、临时工程与 harness 摘要只保留在被忽略的本地研究归档；这些历史结果不冻结当前项目源码。

## 构建与输入

工具链为 TeaVM 0.16.0 JavaScript、JDK 25.0.4、Maven 3.9.11。MangaDraft Source ID 为字符串 `6866320578550428692`。

| 对象                       | SHA-256 / 身份                                                                      | 含义                                                            |
| -------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| 原版 MangaDraft JAR        | `81d456c80449fc205e50332ff281c0b8ee20e584f7e5670ccd3f79abb71dfa86`                  | 原业务字节未修改                                                |
| 研究交付的 release9 源指纹 | `06b2e8f9b560f41c60ce6779ee320ac50523780bf5dd24c08dc01a65010fe299`                  | 历史来源身份，不作为后续自有代码冻结约束                        |
| 历史基线 bundle            | `f3b8eaf7777d920f700b7a0e8aaa9c82889f105e8cfc56d1f8d58373ae86a687`；3,639,557 bytes | 原宿主对照，不能安装为产品包                                    |
| 当时产品 bundle            | `209ad02ba02eae99147502799c08e1aac0c1c7bc29906aa3d60e99174b1b9f22`；3,660,164 bytes | `release9-mangadraft-product-e3505206005c25f69b92`              |
| 完整私有构建               | 7 个产物，3,957,861 bytes                                                           | 包含桥脚本与 WASM；记录的是当次实际输出，不承诺构建逐字节确定性 |

## 通过的分项与限制

| 范围                   | 核心结果                                                                                                                                                | 不能据此宣称                                                     |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| 真实 workerd / D1 / R2 | RS256 测试签名、manifest/list、全部产物 hash、HEAD/304/Range/416、错误 AUD/host 与注册冲突回滚通过                                                      | Cloudflare 生产会话已验收                                        |
| Chrome 156 Worker      | 实际 IndexedDB 环境执行 `hostInit/hostLoad`，Source IDs 与私有清单一致；缺显式章节引用返回 Java 错误                                                    | 六项 Source 在线语义和图片已通过                                 |
| MangaDraft 在线操作    | 热门第 1/2 页和最新各返回 20 项；页码原样到达源站                                                                                                       | 文本搜索匹配正确、资料闭环已完成                                 |
| 有界字节机制           | 64 KiB 内显式双向复制覆盖 `00/ff`、UTF-8、随机字节与偏移视图；无别名；fiber 取消无迟到回调；双向 transfer 后发送方 detached                             | HTTP/Okio 二进制流、零拷贝、手机或总堆峰值                       |
| Zstd 错误恢复          | 无效流保持 `Truncated Zstd frame`；修正局部名碰撞后，拒绝的宿主 Promise 恢复 Java 异常                                                                  | 所有网络/压缩异常均已覆盖                                        |
| iOS 机制               | iOS 26.4 Simulator / SDK 27.2，本地受信 HTTPS；256 KiB / 4 MiB / 16 MiB 摘要一致，处理后 PNG 为 128×256；下载启动后取消，文件与 Blob 释放、资源目录清空 | Flutter 产品图片通道、物理设备、生产 HTTPS/Access 或合计内存峰值 |

## 已知失败

冻结 MangaDraft 的普通文本查询未加入 catalog 请求。原 JAR 字节码和真实请求均确认此行为；返回列表不能视为搜索匹配成功，完整 URL 查询使用另一条 Source 路径。

详情与章节请求被源站从 `/manga/dragon-ball-kakumei` 以 302 重定向至 `/bot-verification`，最终收到 `Human Verification` 页面。Java 返回 `source_error: Unable to find project script`。没有解决或绕过挑战；未获得真实章节引用，因此未伪造 `pages` 调用。完整资料与阅读闭环仍未通过，图片入口仍明确不支持。

## 正式复验入口

- [API 验证](../../apps/api/test/README.md)：真实签名、workerd、D1/R2、注册与 HTTP 桥回归。
- [Source 浏览器集成](../../apps/api/test/source-metadata-probe.md)：真实 bundle / Worker / Source 网络，默认输出 ignored `.local/probes`。
- `python3 tools/teavm/check-dto.py`：完整 DTO、显式引用、分页和长列表的 JVM 边界回归。
- `pnpm check`、`pnpm flutter:check`：协议、类型、界面与资源调度回归；夹具通过不替代在线或真机验收。

构建协议、工具链锁、依赖/资源清单属于构建输入，继续随代码维护；按构建生成的 manifest、validation 和 provenance 属于发布产物，不把历史验证流水当作构建源。
