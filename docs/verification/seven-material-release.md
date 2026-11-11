# 七材料生产与增量发布

2026-11-11，用户要求完成生产发布和扩展增量发布，并停止原生验证、节约本机电池。本轮全量 AOT 在 clab 的独立冻结目录执行，本机无 AOT 构建进程；不恢复原生登录、签名或真机验收。当前状态：**新基线构建中，尚未部署，增量工作流仍停用**。

## 固定输入与前置检查

- 产品源码：`main@2fa8a335bea2204ada7c0c170e8a28ff95679273`；该提交的[通用 CI](https://github.com/Wybxc/karuyomi/actions/runs/42953840361)和[Cloudflare 部署权限检查](https://github.com/Wybxc/karuyomi/actions/runs/42954478943)通过。
- 四个 submodule 按提交的 gitlink 初始化，跟踪输入干净；扩展上游为 `efa93f5a3537856fe830450bbe33f69d21d28167`。
- hostFingerprint：`0fa4bda380f85e322d362cc2595bd03f9f0a156a5b645340d37432c1830d2c67`。
- 七材料版本：`785088dcdd123ce1b640c044b83f590ff5e075833c2abf727f0762ece16d5c5b`；`materials.json` SHA-256 为 `a307dca6daeff7592f6e742e8462b088570c68be267fa284f4add27841d82b36`，与本机同提交的正式材料生成结果一致。
- 以正式 `pull-state` 读取生产父 revision `3c24b0d7c0a745a58de4bd6b5ffb7654`；state SHA-256 为 `18dea38e6c99418eefdc85b2d640feb2566d12b02dc6aeb6ad750ae08dc35a22`，未修改父状态或历史检查点。
- 完整计划发现并选择 1,448 包，零发现失败；plan SHA-256 为 `02e972028f0caa209867ec1f3b9ec74f81ace7299fa11f5ddc7c7442f8bf144c`。

clab 独立目录为 `/home/fedora/.local/karuyomi-seven-2fa8a33.NxbBAV`，冻结 clone 位于 `source/`。依赖按锁文件安装，Node 24.15.0、pnpm 12.6.0；工具链、seed 和材料经过正式准备入口校验。已有依赖缓存只用于加速，未导入旧六材料 AOT 或修改旧冻结批次。

正式 `bootstrap --jobs 1 --finalize` 已启动，并通过实际 PID、首包日志及结果确认执行。clab 为 4 CPU、3.8 GiB 内存，Maven 和 Gradle heap 均限制为 1 GiB，JVM 活跃处理器为 3。进程使用 nohup，与本机 SSH 会话分离；逐包结果保存在 `builds/`，汇总日志为 `bootstrap.log`。恢复须先确认原进程及其子进程已退出，再按 [EXTENSIONS](../EXTENSIONS.md#首次本地全量与恢复)使用原计划；不能并行启动两个发布器。

## 首个实际交付

`eu.kanade.tachiyomi.extension.all.ahottie` 1.6.5 的原版 Gradle 构建与正式 AOT 成功，builder 总耗时 218.79 秒。canonical 为 4,251,027 B，SHA-256 `cac399991fc0fa79d6b51fad144181e9cda43ce042f313e8f6da44965b7a39bd`；gzip 为 873,970 B，SHA-256 `206979ac09d7216e2ed0f3b4442c63efad07525bf6bd32ba79df3ee81a734d49`。

公开 buildId 为 `ext-all.ahottie-6284b6146ba79eb4353a1db065cce03b-cac399991fc0fa79d6b51fad144181e9cda43ce042f313e8f6da44965b7a39bd`。清单包含五桥和两份 WASM；正式 runner 的 `artifactIntegrity=passed`，`workerInit/browserLoad=not_run`，状态保持 `compiled_unverified/runtimeReady=false`。首包成功不表示完整候选或 Source 在线行为通过。

## 剩余验收

1. 等完整计划取得所有包的终态；检查失败原因和现网包的保留情况，正式生成七材料完整候选。不能把六材料旧清单补标签混装，也不把本轮失败算作兼容。
2. 完成候选的 Web/Worker 构建、部署预演与内置浏览器验收；紧邻部署执行 `check-base`。部署后确认全部流量、D1、匿名静态交付和生产测试账号的阅读、保存、续读，再以正式 `commit-snapshot` 确认检查点。
3. 匹配的完整基线确认后，启用扩展工作流并运行真实有界增量。核对实际构建、完整快照部署、失败保留、已确认检查点与客户端更新；启用开关不等于增量发布通过。

现网继续服务[首版六材料快照](first-web-release.md)。本记录不提升原生未通过项，也不声称已发布七材料或已完成增量验收。原始计划、日志和逐包结果留在上述 ignored 目录；本机交接入口为 `.local/production-seven-2fa8a33.7Js42X/REPRODUCE.md`。
