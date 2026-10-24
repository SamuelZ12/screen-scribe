# 本地识别测试图片

全部为人工编写的合成样例，PNG 由同名 TeX 经 LuaLaTeX + Poppler 渲染，非 API 输出。公式预期内容在 `.expected.txt`。可运行 `scripts/verify-fixtures.sh` 重建。

| 样例 | 核查点 |
| --- | --- |
| 01-single | 单行、分数、根式、上下标 |
| 02-aligned | 两行 aligned、Dirac 双线性、希腊字母、动量指标 |
| 03-complex | 积分、Theta、delta、plus distribution、求和、张量、Dirac slash、矩阵 |
| 04-fermion-photon | 四条外腿、两个顶点、波浪内部线、箭头、标签 |
| 05-multiple-vertices | 四个顶点、多条内部边、弯曲边、箭头、动量 k |

图 04/05 的线型与标签是测试源明示的绘图约定。识别系统仍应区分观测到的线型和推断的粒子身份；图 05 用于连接关系测试，不声称是特定物理过程。

本轮已验证源码编译和 PNG 可读性，未向真实服务提交这些图片。真实 API 验收应逐图记录服务/模型、源码、待确认项、耗时、数学/拓扑差异及 TikZ 编译结果；不能只凭“能编译”判定图结构正确。
