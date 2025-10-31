### 最重要、最严重的问题（优先级 P0）

- **环境与平台强绑定，导致可移植性差**：`halligan/pyproject.toml` 将 `requires-python` 固定为 `==3.12.4`，Pixi 仅声明 `linux-64` 平台；依赖中包含 `pytorch==2.3.1`、`torchvision==0.18.1`、`faiss-gpu>=1.9.0` 等重依赖且未提供 CPU 替代或平台条件，给 macOS/Windows 用户和无 GPU 环境带来安装与运行障碍。
- **环境管理割裂、文档路径跨目录，开发者上手成本高**：根目录 README 指导分别进入 `benchmark/`（Docker/Conda）与 `halligan/`（Pixi）两套体系，缺少顶层一键编排（如顶层 `docker compose` 或 Makefile），新同学很难正确拉起端到端环境。
- **测试不稳定且与外部服务强耦合**：`halligan/basic_test.py` 将基准服务期望返回码断言为 500 且依赖 UI 渲染与 `time` 等待、ARIA 快照相似度（`SequenceMatcher`），对运行时序、渲染差异高度敏感；未区分单元/集成/E2E 层次，CI 中容易出现雪花失败（flaky）。
- **基准服务错误处理与日志实现存在缺陷**：`benchmark/server.py` 的 `after_request` 直接访问 `response.json`，在某些响应类型上可能抛错；`handle_exception` 使用 `logging.info(traceback.print_exc())` 实际记录为 `None`；默认 `debug=True` 不适合生产/CI；日志文件未滚动，长期运行会膨胀。
- **缺乏统一的代码质量守门**：仓库未见格式化/静态检查/类型检查配置（如 Black/ Ruff/ Mypy），没有 pre-commit 与 CI 质量门禁，长期易积累风格不一致与潜在缺陷。
- **核心脚本导入即触发外部调用，缺少运行入口控制**：`halligan/execute.py` 在模块导入阶段直接遍历 `SAMPLES` 并连接远程浏览器/基准服务，任何单元测试或工具模块若意外导入该文件都会发起真实网络操作并写日志文件，既破坏测试隔离，也可能耗尽配额或泄露密钥。
- **CI 条件表达式错误导致集成任务无法运行**：`.github/workflows/ci.yml` 的 `integration` 作业使用 `join(github.event.pull_request.changed_files, ',')` 判断改动目录，但该属性并非数组，表达式在 PR 和 push 上都会抛异常，直接使工作流失败且无法触发集成校验。

- **CI 中 Pixi 设置寻找错误位置导致缓存与清理失败（当前报错）**：`prefix-dev/setup-pixi@v0.8.1` 在仓库根目录默认查找 `pixi.toml`/`pixi.lock`，而项目的 Pixi 清单位于 `halligan/pyproject.toml`，锁文件为 `halligan/pixi.lock`。由于未显式指定清单路径，动作在生成缓存键时报错 `ENOENT: no such file or directory, open 'pixi.lock'`，并在 Post Job 阶段因缺失工作目录 `.pixi` 再次报错 `lstat '.pixi'`，导致 `lint-and-test` 任务早期失败。

- **CI 中 `pixi install --locked` 失败（动作默认行为）**：`setup-pixi` 会在安装阶段使用 `--locked`，当锁文件与 `pyproject.toml` 不一致或存在无效依赖时直接退出。当前 `halligan/pyproject.toml` 声明了 `clip` 的本地可编辑依赖 `./halligan/models/CLIP`，但仓库内不存在该目录，导致解析失败，进而使 `pixi install --locked` 返回非零退出码。

### 其他关键问题（简述）

- **版本锁定策略不一致**：部分严格锁定（如 `ultralytics==8.2.51`、`transformers==4.42.4`），部分宽松（`faiss-gpu>=1.9.0,<2`），缺少说明与升级策略，容易出现“升级地雷”。
- **模型/权重下载缺少校验与缓存策略**：`halligan/get_models.sh` 未体现哈希校验、断点续传与镜像源回退，首配体验与可重复性弱。
- **结果产出与状态缺少结构化可观测性**：`benchmark` 只写入 `results.log`，缺少结构化日志/指标；`/health` 未返回 JSON 体，自动化探活/诊断不便。
- **仓库治理资料缺失**：未见 `CONTRIBUTING.md`、`CODE_OF_CONDUCT.md`、`SECURITY.md`、`CHANGELOG.md`、Issue/PR 模板等，外部协作与可持续演进成本高。
- **执行脚本缺少配置显式校验**：`halligan/execute.py` 直接读取 `BROWSER_URL`、`BENCHMARK_URL`、`OPENAI_API_KEY` 环境变量未做检查，默认值为 `None` 时会在运行时抛出晦涩异常，调试体验差。
- **静态检查模块解析告警**：CI 中 Ruff 对 `dotenv`、`playwright` 报告 `unresolved-import`，当前推测为缺少对应依赖或安装顺序问题，需确认是否通过安装 `python-dotenv`、`playwright`（或配置忽略）来收敛警告。

-