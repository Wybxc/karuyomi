# 脚手架验证

2026-11-03，在 macOS 上使用 Flutter 3.47.5 / Dart 3.13.4、Node 26.5.0、pnpm 12.6.0 验证。

| 检查                             | 结果                                                                                                                             |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `pnpm install --frozen-lockfile` | 通过；依赖构建仅允许声明的 esbuild / workerd / sharp                                                                             |
| `pnpm check`                     | 协议生成一致、格式、严格 TS 类型检查通过；20 项测试通过                                                                          |
| `pnpm flutter:check`             | 两个 Dart 包和 Flutter app 静态分析通过；3 项核心测试与 2 项响应式界面测试通过；Dart 格式通过                                    |
| `pnpm build`                     | JS 宿主、Flutter Web release、同源静态产物与 Wrangler dry-run 全部通过                                                           |
| `pnpm db:migrate:local`          | 本地 D1 初始迁移成功                                                                                                             |
| 本地 workerd HTTP 检查           | `/`、`/library`、运行控制页与 Worker 脚本 200；未配置的裸 `/api`、bootstrap 与未知 API 为 JSON 503 / no-store；编码 API 别名 400 |
| 浏览器检查                       | IAB 加载本地完整产物，桌面书架空态和中文文字正常渲染                                                                             |
| 设计副本溯源                     | 五份副本 SHA-256 与 `design/provenance.json` 一致                                                                                |

JWT 测试使用本地生成的 RSA 密钥与真实签名，覆盖错 issuer、AUD、subject、到期、伪造 token / 邮箱头、缺 token、固定登录回跳、鉴权后的 JSON 404；没有修改或绕过线上 Access 配置。

尚未执行 Android/iOS 原生编译或真机验收、线上部署与 Access 联调、TeaVM release9 导入、真实源和图片桥。Worker 握手仍声明 `sourceReady: false`；本记录验证工程起点，不代表 P0 完成。CI 已配置同类检查，尚未在远端执行。
