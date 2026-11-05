# 自定义封面

自定义封面已接入生成协议、Worker API、D1、私有 R2、共享 Dart 数据层与正式详情/书架 UI，状态为**已实现，待独立客户端验收**。实现和实际验证分别维护；当前证据见[自定义封面验证](../verification/custom-covers.md)，生产 bucket 配置和部署尚未验收。

## 权威状态与身份

D1 的 `cover_assets` 保存每个 `subject + mangaKey` 的当前封面描述和私有 R2 object key，查询漫画及书架时投影为 `MangaState.customCover`。漫画 JSON 不再保存第二份封面关系。R2 保存编码图片正文，不作为业务当前版本的判据；客户端只显示 D1 已确认的引用，不维护本地权威封面或持久待提交队列。

`CustomCover` 包含独立 UUIDv4 `assetId`、`contentType`、`byteLength` 和 SHA-256。客户端在新操作开始时生成 assetId，独立于 mutation UUID；描述不含任意 URL 或 R2 key。支持 JPEG/PNG，正文为 1 字节至 1 MiB，服务端按真实文件识别格式、检查两轴均不超过 4096，并验证长度与 SHA-256。自定义封面与 Source 的原始 Manga 快照及 thumbnailUrl 分开；刷新源元数据、取消收藏、修改分类或阅读进度不清除封面。

API 复用已验证的 Access subject，额外核对 `X-App-Subject` 与该身份一致。`GET /api/covers/:assetId` 只查询该 subject 的当前 D1 引用，再读取私有 R2；替换或清除后旧 asset 不再通过此入口读取。正文响应为 `private, no-store`，不进入公共 Static Assets、扩展分发或 Source 图片通道。

## 一次上传与作品 CAS

上传使用 `POST /api/covers/:mangaKey` 的标准 multipart，仅包含两个字段：

| 字段       | 内容                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `mutation` | 完整 `StateMutation` 的标准 ProtoJSON 字符串，含 schemaVersion、mutationId、mangaKey、expectedRevision 和 `setCustomCover.cover` |
| `image`    | 与描述匹配的二进制文件                                                                                                           |

二进制正文独立于小消息控制通道，不做 Base64 或把图片嵌入 ProtoJSON。multipart 总量、控制字段和文件均有独立限额；路由要求路径漫画与 mutation 相同，且操作为有 cover 的 `setCustomCover`。普通 `POST /api/state/mutations` 拒绝携带非空 cover 的替换操作；清除使用该 JSON 路由的 `setCustomCover: {}`。

封面与收藏、分类、阅读进度共用漫画 revision、每漫画队列和幂等记录，没有封面专属 CAS。编辑固定打开时的已确认漫画 revision，上传和清除都要求精确匹配。API 返回标准 `StateMutationResponse`；客户端验证 mutation、漫画身份、确认 revision 和封面描述或 absence 后才结束原操作。

一次 API 请求不代表 R2 与 D1 具备跨存储事务。服务端先核对持久幂等结果与当前 CAS，实际需要写入时为每次尝试创建独立 R2 key：`covers/<subject摘要>/<assetId>/<attempt UUID>`。R2 候选写入成功后，D1 batch 的 CAS/nonce gate 原子确认当前引用、漫画/account revision 和幂等结果。失败或并发落败的候选不会成为可读取的当前封面；已提交的重复 mutation 复用原结果，不再上传候选。每次尝试使用新 key，避免迟到失败尝试覆盖已经确认的对象。

## 客户端与第三方库

文件选择直接使用 `file_selector`，编解码、方向与缩小直接使用 `image`，标准 multipart 和有界 HTTP 使用 `http`/`http_parser`。依赖版本固定在 Flutter 包清单和锁文件中，不自行实现文件选择器、multipart codec 或通用图片编解码。

正式选择流程在读取前限制输入不超过 16 MiB，按实际图片头限制不超过 3200 万像素，使用首帧、应用方向，长边最多 1024，编码为 quality 85 的 JPEG，输出不超过 1 MiB。此处理只作用于用户选中的自定义封面，不改 Source 图片或原始 DTO。

`CoverRepository` 使用共享 `BusinessStateClient`，详情和书架通过已确认漫画状态获得描述。私有图片由 `CoverTransport` 单独读取；HTTP 传输限制正文、超时和重定向，并在下载边界验证类型、长度和 SHA-256 一次，后续复用已验证字节交给 Flutter。平台提供同源身份会话：Web 使用浏览器 HTTP 客户端，Native 从现有 WebView Cookie 会话取请求头；该接线的实际 Native Cookie/Access 行为仍须独立验收。

## 未确认、冲突与生命周期

首次提交保存原 mutation UUID、assetId、CAS、序列化控制正文和不可变图片字节。未确认操作归属于当前共享业务会话，重建 repository 或编辑窗口不丢失；同一漫画的新操作不能替换它，只有明确重试才重发原请求。清除也保留原 JSON 请求，不把重试转换成新决定。

响应丢失后，幂等成功只说明原写入曾发生。客户端重读当前权威漫画状态，远端替换/清除或已知更新不能被旧 ACK 当作当前封面；明确拒绝后读取最新状态，用户才能作出新的编辑决定。普通读取保留仍可重试的未确认操作。

会话固定 origin 与 subject，不能重绑成另一身份。客户端关闭后清除内存草稿并拒绝迟到 ACK/读取结果，平台关闭时停止尚在进行的 HTTP；界面也检查当前业务会话，旧窗口不能导航或提交到新身份。未确认图片只留当前会话，关闭应用后不承诺恢复。

## 私有对象的显式清理

替换、清除和失败后不立即删除 R2 对象，避免并发尝试或丢 ACK 后的精确重试误删另一次成功引用。当前 D1 引用立即决定 API 可见性，物理对象回收另行进行。

`pnpm covers:cleanup` 显式列举 `covers/` 下的有界一页对象，先检查上传年龄，再向 D1 核对 object key 没有当前引用，才删除。宽限期默认一小时且不可小于一小时；输出 scanned/deleted、truncated 和续页 cursor。没有自动清理计划任务。

```sh
# 本地 Wrangler D1/R2 状态，一页一执行
pnpm covers:cleanup --grace-hours 1
# 远端须已完成 bucket/DB 配置及授权；truncated 时保留参数并传回 cursor
pnpm covers:cleanup --remote --grace-hours 24
pnpm covers:cleanup --remote --grace-hours 24 --cursor '<上次返回的cursor>'
```

生产 `COVERS` 私有 bucket 创建/绑定、D1 schema 和实际清理运行须在部署时另验。以上命令是操作入口，不表示已经执行远端清理或部署。
