### 最重要、最严重的问题（优先级 P0）

- **环境与平台强绑定，导致可移植性差**：`halligan/pyproject.toml` 将 `requires-python` 固定为 `==3.12.4`，Pixi 仅声明 `linux-64` 平台；依赖中包含 `pytorch==2.3.1`、`torchvision==0.18.1`、`faiss-gpu>=1.9.0` 等重依赖且未提供 CPU 替代或平台条件，给 macOS/Windows 用户和无 GPU 环境带来安装与运行障碍。
- **环境管理割裂、文档路径跨目录，开发者上手成本高**：根目录 README 指导分别进入 `benchmark/`（Docker/Conda）与 `halligan/`（Pixi）两套体系，缺少顶层一键编排（如顶层 `docker compose` 或 Makefile），新同学很难正确拉起端到端环境。
- **测试不稳定且与外部服务强耦合**：`halligan/basic_test.py` 将基准服务期望返回码断言为 500 且依赖 UI 渲染与 `time` 等待、ARIA 快照相似度（`SequenceMatcher`），对运行时序、渲染差异高度敏感；未区分单元/集成/E2E 层次，CI 中容易出现雪花失败（flaky）。
- **基准服务错误处理与日志实现存在缺陷**：`benchmark/server.py` 的 `after_request` 直接访问 `response.json`，在某些响应类型上可能抛错；`handle_exception` 使用 `logging.info(traceback.print_exc())` 实际记录为 `None`；默认 `debug=True` 不适合生产/CI；日志文件未滚动，长期运行会膨胀。
- **缺乏统一的代码质量守门**：仓库未见格式化/静态检查/类型检查配置（如 Black/ Ruff/ Mypy），没有 pre-commit 与 CI 质量门禁，长期易积累风格不一致与潜在缺陷。
- **核心脚本导入即触发外部调用，缺少运行入口控制**：`halligan/execute.py` 在模块导入阶段直接遍历 `SAMPLES` 并连接远程浏览器/基准服务，任何单元测试或工具模块若意外导入该文件都会发起真实网络操作并写日志文件，既破坏测试隔离，也可能耗尽配额或泄露密钥。
- **CI 条件表达式错误导致集成任务无法运行**：`.github/workflows/ci.yml` 的 `integration` 作业使用 `join(github.event.pull_request.changed_files, ',')` 判断改动目录，但该属性并非数组，表达式在 PR 和 push 上都会抛异常，直接使工作流失败且无法触发集成校验。

- **CI 中 Pixi 设置寻找错误位置导致缓存与清理失败（当前报错）**：`prefix-dev/setup-pixi@v0.8.1` 在仓库根目录默认查找 `pixi.toml`/`pixi.lock`，而项目的 Pixi 清单位于 `halligan/pyproject.toml`，锁文件为 `halligan/pixi.lock`。由于未显式指定清单路径，动作在生成缓存键时报错 `ENOENT: no such file or directory, open 'pixi.lock'`，并在 Post Job 阶段因缺失工作目录 `.pixi` 再次报错 `lstat '.pixi'`，导致 `lint-and-test` 任务早期失败。

### 其他关键问题（简述）

- **版本锁定策略不一致**：部分严格锁定（如 `ultralytics==8.2.51`、`transformers==4.42.4`），部分宽松（`faiss-gpu>=1.9.0,<2`），缺少说明与升级策略，容易出现“升级地雷”。
- **模型/权重下载缺少校验与缓存策略**：`halligan/get_models.sh` 未体现哈希校验、断点续传与镜像源回退，首配体验与可重复性弱。
- **结果产出与状态缺少结构化可观测性**：`benchmark` 只写入 `results.log`，缺少结构化日志/指标；`/health` 未返回 JSON 体，自动化探活/诊断不便。
- **仓库治理资料缺失**：未见 `CONTRIBUTING.md`、`CODE_OF_CONDUCT.md`、`SECURITY.md`、`CHANGELOG.md`、Issue/PR 模板等，外部协作与可持续演进成本高。
- **执行脚本缺少配置显式校验**：`halligan/execute.py` 直接读取 `BROWSER_URL`、`BENCHMARK_URL`、`OPENAI_API_KEY` 环境变量未做检查，默认值为 `None` 时会在运行时抛出晦涩异常，调试体验差。
- **静态检查模块解析告警**：CI 中 Ruff 对 `dotenv`、`playwright` 报告 `unresolved-import`，当前推测为缺少对应依赖或安装顺序问题，需确认是否通过安装 `python-dotenv`、`playwright`（或配置忽略）来收敛警告。

---

### 改进与优化方案

#### 1) 环境与可移植性
- 将 `requires-python` 放宽为 `>=3.10,<3.13`（经回归验证后生效），为 `darwin-64`、`win-64` 增加 Pixi 平台；提供 `cpu` 与 `cuda` 两种特性环境：
  - `faiss-cpu` 作为 CPU 备选，`faiss-gpu` 置于 `cuda` 特性；
  - `torch` 采用官方通道并根据 CUDA 版本自动选择构建。
- 提供顶层 `docker compose` 统一编排三服务：Benchmark、无头浏览器（Playwright）、Halligan Core，内置 `.env` 显式变量与默认值。
- 在根目录增加 `Makefile`：`make up`、`make test-unit`、`make test-integration`、`make e2e`、`make fmt` 一键化。

#### 2) 执行入口与配置防护
- 为 `halligan/execute.py` 增加 `main()` 封装与 `if __name__ == "__main__":` 守卫，避免导入即执行。
- 在 `main()` 前校验关键环境变量并给出友好错误信息或 CLI 提示；将浏览器/基准地址改为命令行参数或配置文件。
- 将日志处理配置延迟到 `main()` 内部，禁止导入阶段就写磁盘文件。

#### 3) 测试分层与稳定性
- 测试分层：
  - 单元测试：无 I/O、无网络、可并行；
  - 集成测试：本地起 `benchmark` 与浏览器容器，打 `pytest -m integration` 标记；
  - E2E/回归：涉及模型推理与真实页面交互，标记 `-m e2e`，仅在受控环境或自托管 Runner 运行。
- 稳定性措施：去除对 500 状态码的“成功”断言，改为 `/health` 探活 + 关键路由 200 验证；减少 `sleep`，使用明确的等待条件；对快照测试固定随机种子与确定性资源。

#### 4) 基准服务健壮性
- `after_request` 使用 `response.is_json` 或 `response.content_type` 判断再解析；
- `handle_exception` 使用 `logging.exception(e)` 记录完整堆栈；
- 默认关闭 `debug`，通过 `FLASK_DEBUG` 环境变量控制；
- 使用 `RotatingFileHandler` 或结构化 JSON 日志（便于后续采集）。

#### 5) 代码质量治理
- 引入工具：Black（格式化）、Ruff（lint）、Mypy（类型）、isort（导入排序）。
- 增加 `pre-commit` 钩子，提交即检查；CI 作为强制门禁。
- 逐步类型化关键模块（公共 API、核心算法），其余以 `py.typed`/渐进式策略推进。

#### 6) 模型与数据资产
- `get_models.sh` 增加 SHA256 校验、断点续传与镜像回退；
- 统一缓存目录（如 `~/.cache/halligan`），避免重复下载；
- 在 README 标注模型许可与使用边界，提供最小可运行权重（小模型）以便 CI/本地快速验证。

#### 7) 文档与项目治理
- 新增与完善：`CONTRIBUTING.md`、`CODE_OF_CONDUCT.md`、`SECURITY.md`、`CHANGELOG.md`、Issue/PR 模板；
- 在根 README 增加“一键起服务”与“常见问题”章节；
- 定义版本策略（SemVer）与发布流程（含 Docker 多平台镜像）。

#### 8) CI 表达式与策略
- 将 `integration` 作业触发条件改为：push 默认执行、带 `run-integration` 标签的 PR、手动 workflow dispatch；不再使用不可用的 `changed_files` 字段。
- 如需基于改动路径决定是否运行，在作业内引入 `dorny/paths-filter` 或自定义脚本计算差异，再通过输出变量控制后续步骤。

---

### 持续集成 / 持续交付（CI/CD）方案

#### 目标
- 对 PR 执行快速、稳定、可重复的质量检查；对主干执行集成与（可选）GPU E2E；产出可追溯工件（日志、快照、镜像）。

#### 作业划分
- `quality`（PR 必跑）：安装、格式化检查、lint、类型检查、单元测试；
- `integration`（合入主干或带标签触发）：拉起容器跑集成测试；
- `e2e-gpu`（自托管 Runner/夜间任务）：最重的端到端回归；
- 安全与运维：CodeQL、Dependabot、Trivy 镜像扫描、Secret 扫描（push/weekly）。

#### GitHub Actions 示例（精简）
```yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: prefix-dev/setup-pixi@v0
      - name: Install deps
        run: |
          cd halligan
          pixi install
      - name: Lint & Format
        run: |
          cd halligan
          pixi run ruff check .
          pixi run black --check .
          pixi run mypy halligan || true
      - name: Unit tests
        run: |
          cd halligan
          pixi run pytest -m "not integration and not e2e" -q

  integration:
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    services:
      benchmark:
        image: ghcr.io/OWNER/REPO/benchmark:latest
        ports: ['3334:3334']
      browser:
        image: mcr.microsoft.com/playwright:v1.52.0-jammy
        ports: ['3000:3000']
        options: >-
          --entrypoint sh -c "npx playwright@1.52.0 launch-server chromium --port=3000 --headless=1"
    steps:
      - uses: actions/checkout@v4
      - uses: prefix-dev/setup-pixi@v0
      - name: Install deps
        run: |
          cd halligan
          pixi install
      - name: Integration tests
        env:
          BROWSER_URL: ws://localhost:3000/
          BENCHMARK_URL: http://localhost:3334
        run: |
          cd halligan
          pixi run pytest -m integration --maxfail=1 -q
```

#### 关键实施点
- 使用缓存（pip/conda/pixi 与模型缓存）加速 CI；
- PR 默认只跑 `quality`；`integration` 在主干或带 `run-integration` 标签时触发；
- 秘钥管理：在仓库 Secrets 中配置（如 OpenAI Key），分环境隔离；
- 产物归档：失败时上传日志、快照、HTML 报告，便于排错。

---

### 里程碑与落地顺序
- M1（1 周）：顶层 `docker compose`/Makefile、一键起服务；修正 `server.py` 错误处理与日志；新增 `/health` JSON；
- M2（1-2 周）：引入 Black/Ruff/Mypy/pre-commit；测试分层与标记；稳定化断言；
- M3（1-2 周）：CI `quality` 上线并设为门禁，随后加入 `integration`；
- M4（2+ 周）：模型下载校验与缓存、文档与治理文件、Dependabot/CodeQL/Trivy、安全扫描；视资源接入 `e2e-gpu`。

---

### 预期收益
- 跨平台与无 GPU 环境可运行，降低上手与复现成本；
- 测试稳定、问题可回溯，PR 质量可量化；
- 运行期更可观测、更安全，日志不丢失不膨胀；
- 更清晰的版本与发布流程，便于学术/工业复用与扩展。
