# v6 本地 AOT 试编与公开构建身份

2026-11-07，在干净的独立 checkout 固定项目 `993fe544`、Keiyoushi `efa93f5a`、host ABI v6 / control 2 / HTTP bridge 2 / release9。以匿名 HTTPS 重新核对线上 build-state 与 index 的精确字节，基线 revision 为 `702cc6bfb2974682bf1c83325458535a`，`bootstrap.complete=false`。正式发现 1,448 包，无发现失败；全量计划 SHA-256 为 `ed1e73ed6eb423fdab76cdbf6b9cf82fb642f602b094597aa3d2c07b0e556eec`，大小 14,321,059 B。仅从该计划选三个代表包，按 `jobs=1` 走正式构建与静态快照装配。

| 扩展             |    耗时 |      gzip |
| ---------------- | ------: | --------: |
| xkcd             | 42.14 s | 930,610 B |
| Arknights Comics | 36.27 s | 669,533 B |
| CuuTruyen        | 41.46 s | 888,248 B |

三份终态均为 `compiled_unverified`，静态候选 revision 为 `21204762900b4cb88ed88c9d908d1a5a`，index SHA-256 为 `e424ec777f9fbdb12fd6c6d5abf041a436086e9a9ea6a3c7c134029efc26276e`。构建与装配正常退出，其余 1,445 包没有启动，未部署、未提交生产 checkpoint、未启用增量 CI。固定输入、输出和逐包记录留在本地忽略的 `/private/tmp/karuyomi-local-baseline-993fe54-yDXFKs`，只作该次证据。

## 同一输入两次输出的对照

当前候选和先前 `5ba6fff` 的 xkcd 使用同一个输入指纹 `dd84d305506e2bdc34ac62988aef645f56bb7b6567c85ed55b73d2b4284ca491`。原始 JAR、15 份 donor、seed、材料及实际工具链 JAR 摘要一致。两份 canonical JS 均为 4,477,929 B，AST 可正常解析，字符串池排序后完全相同；37 个索引和相应代码顺序发生移动。当前 SHA-256 为 `31de2bd8c529bb0cbd310725b7c400cf511be1863554bf9d55a17ffc03f27e55`，此前为 `5fd6e868d3b077db8893ce4a517dd486dc7938c04a7af5c70507ba0eabea7682`。TeaVM 0.16.0 实际字节码的依赖传播存在按对象身份哈希排列的集合，发射器依赖发现顺序；本轮未隔离触发具体重排的传播边，不声称已使编译器可复现。

当时仅以输入指纹生成公开 ID，两份不同 JS 共用同一个清单路径和索引身份。Flutter 会把已安装记录识别为当前版本，隐藏更新操作；下载准备读取新清单后又会按已确认的旧摘要拒绝打开。现有缓存与授权以 canonical SHA 隔离，两份字节不会被错误混用。旧候选保留为观察证据，原 `5ba6fff` 的在线验收不能移用到新字节。发布身份与恢复合同见[扩展静态分发](../EXTENSIONS.md)。
