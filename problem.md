### 最重要、最严重的问题（优先级 P0）

- **环境与平台强绑定，导致可移植性差**：`halligan/pyproject.toml` 将 `requires-python` 固定为 `==3.12.4`，Pixi 仅声明 `linux-64` 平台；依赖中包含 `pytorch==2.3.1`、`torchvision==0.18.1`、`faiss-gpu>=1.9.0` 等重依赖且未提供 CPU 替代或平台条件，给 macOS/Windows 用户和无 GPU 环境带来安装与运行障碍。
- **环境管理割裂、文档路径跨目录，开发者上手成本高**：根目录 README 指导分别进入 `benchmark/`（Docker/Conda）与 `halligan/`（Pixi）两套体系，缺少顶层一键编排（如顶层 `docker compose` 或 Makefile），新同学很难正确拉起端到端环境。
- **测试不稳定且与外部服务强耦合**：`halligan/basic_test.py` 将基准服务期望返回码断言为 500 且依赖 UI 渲染与 `time` 等待、ARIA 快照相似度（`SequenceMatcher`），对运行时序、渲染差异高度敏感；未区分单元/集成/E2E 层次，CI 中容易出现雪花失败（flaky）。
- **基准服务错误处理与日志实现存在缺陷**：`benchmark/server.py` 的 `after_request` 直接访问 `response.json`，在某些响应类型上可能抛错；`handle_exception` 使用 `logging.info(traceback.print_exc())` 实际记录为 `None`；默认 `debug=True` 不适合生产/CI；日志文件未滚动，长期运行会膨胀。
- **缺乏统一的代码质量守门**：仓库未见格式化/静态检查/类型检查配置（如 Black/ Ruff/ Mypy），没有 pre-commit 与 CI 质量门禁，长期易积累风格不一致与潜在缺陷。
- **核心脚本导入即触发外部调用，缺少运行入口控制**：`halligan/execute.py` 在模块导入阶段直接遍历 `SAMPLES` 并连接远程浏览器/基准服务，任何单元测试或工具模块若意外导入该文件都会发起真实网络操作并写日志文件，既破坏测试隔离，也可能耗尽配额或泄露密钥。
- **CI 条件表达式错误导致集成任务无法运行**：`.github/workflows/ci.yml` 的 `integration` 作业使用 `join(github.event.pull_request.changed_files, ',')` 判断改动目录，但该属性并非数组，表达式在 PR 和 push 上都会抛异常，直接使工作流失败且无法触发集成校验。

- **CI 中 Pixi 设置寻找错误位置导致缓存与清理失败（当前报错）**：`prefix-dev/setup-pixi@v0.8.1` 在仓库根目录默认查找 `pixi.toml`/`pixi.lock`，而项目的 Pixi 清单位于 `halligan/pyproject.toml`，锁文件为 `halligan/pixi.lock`。由于未显式指定清单路径，动作在生成缓存键时报错 `ENOENT: no such file or directory, open 'pixi.lock'`，并在 Post Job 阶段因缺失工作目录 `.pixi` 再次报错 `lstat '.pixi'`，导致 `lint-and-test` 任务早期失败。

- **CI 中 `pixi install --locked` 失败（动作默认行为）**：`setup-pixi` 会在安装阶段使用 `--locked`，当锁文件与 `pyproject.toml` 不一致或存在无效依赖时直接退出。虽然已移除无效的本地依赖，但由于我们近期调整了 `pyproject.toml`（平台、依赖与开发工具），仓库中的 `halligan/pixi.lock` 仍为旧版本，导致 `setup-pixi` 在强制锁定安装阶段失败，日志为：

  ```
  Run prefix-dev/setup-pixi@v0.8.1
  Downloading Pixi
  Restoring pixi cache
  pixi install --locked
  Error: The process '/home/runner/.pixi/bin/pixi' failed with exit code 1
  ```

  该失败发生在动作自身步骤内，先于我们后续显式的 `pixi install -p ./halligan` 步骤，因此工作流提前中止。

- **CI 中 setup-pixi 缓存报错（Cannot cache without running install）**：当 `with.cache: true` 且 `run-install: false` 同时设置时，动作无法执行安装以生成/恢复缓存，于主步骤与 Post Job 清理阶段均会报 `Error: Cannot cache without running install`，从而使任务失败。

- **CI 中 pixi CLI 参数顺序错误导致安装失败（当前报错）**：在步骤 `Install deps (CPU)` 中使用了 `pixi install -p ./halligan`，但 `-p/--project` 是 pixi 的全局参数，必须置于子命令之前。错误日志：

  ```
  Run pixi install -p ./halligan
  error: unexpected argument '-p' found
  Usage: pixi install [OPTIONS]
  Error: Process completed with exit code 2.
  ```

  因此 `install` 子命令将 `-p` 视为非法参数，导致作业失败。

- **项目内 Makefile 同样存在 pixi 参数顺序错误**：`Makefile` 使用了 `pixi install -p ./halligan` 与多处 `pixi run -p ./halligan ...`，同样会触发 CLI 解析错误，导致本地开发者复现 CI 步骤时踩坑。

- **CI 仍出现旧日志提示（原因是远端配置未更新）**：GitHub Actions 日志显示 `Run pixi install -p ./halligan`，表明远端工作流仍为旧版。需要同步更新工作流至使用 `working-directory: halligan` 或正确的 `pixi -p ./halligan ...` 形式。

- **Pixi 解算跨平台环境导致 `faiss-gpu` 在 `osx-arm64` 上失败（当前报错）**：`halligan/pyproject.toml` 在 `[tool.pixi.workspace]` 中声明了多平台（含 `osx-arm64`），并定义了环境 `cuda = ["cuda"]`。`pixi install` 会尝试为所有声明的环境与平台求解，哪怕 CI 正在运行 CPU 安装步骤。由于 `faiss-gpu>=1.9.0,<2` 在 `osx-arm64` 无可用候选，导致安装失败，错误如下：

  ```
  Run pixi install
  Error:   × failed to solve requirements of environment 'cuda' for platform 'osx-arm64'
    ├─▶   × failed to solve the environment

    ╰─▶ Cannot solve the request because of: No candidates were found for faiss-gpu >=1.9.0,<2.

  Error: Process completed with exit code 1.
  ```

  根因：项目存在名为 `cuda` 的环境且工作空间平台包含 `osx-arm64`，使得 Pixi 在 CI 的 CPU 安装阶段也会对 `cuda@osx-arm64` 进行求解，从而命中 `faiss-gpu` 的不可用平台。

- **CI 预提交阶段出现 Pixi Manifest 警告（信息级别）**：`pixi run precommit` 前输出 `The feature 'cuda' is defined but not used in any environment.`。这是我们将 CUDA 依赖保留为“按需启用”的 `feature.cuda` 后，Pixi 的提示性告警，表示该特性未在任何命名环境中被引用。当前设计为避免 CI 在非 GPU 平台上误求解 GPU 依赖，因此告警可忽略，不影响功能或安装。

- **pre-commit 在验证阶段仍报告“文件被修改”（当前报错）**：我们同时启用了 `ruff-format` 与 `black` 两个 Python 格式化器，且 `isort` 排在 `black` 之后。第一次修复阶段中，`isort` 在 `black` 之后改动了 import，导致第二次“验证”再运行时 `black`/`ruff-format` 继续改写文件，从而让“Verify pre-commit is clean” 失败。根因是“重复格式化器 + 错误的钩子顺序”引发的格式化回摆循环，而非真实语法/风格错误。

- **单元测试包含对外部依赖的强依赖用例（当前报错）**：在“Run unit tests with JUnit” 阶段，`basic_test.py::test_browser` 与 `basic_test.py::test_halligan` 失败：
  - `test_browser` 依赖 `BROWSER_URL` 与容器化 Playwright 浏览器，CI 单元测试环境未提供，报错 `ws_endpoint: expected string, got undefined`。
  - `test_halligan` 导入 `from halligan.models import CLIP, Segmenter, Detector`，而当前仓库的 `halligan/models/__init__.py` 为空，导致 `ImportError: cannot import name 'CLIP'`。
  - 这两项未标记为 `@pytest.mark.integration` 且缺少环境/依赖存在性的兜底跳过逻辑，在 `-m 'not integration'` 的单元测试任务中仍被执行，导致 CI 失败。

- **CI 单元测试阶段全部用例被筛掉导致退出码 5（当前报错）**：工作流按 `-m 'not integration'` 运行单元测试，但 `halligan/basic_test.py` 中所有实际用例均带有 `@pytest.mark.integration` 标记（含参数化的 26 个 CAPTCHA 用例）。因此 PyTest 日志为 `29 deselected / 0 selected`，并以退出码 5 结束，导致步骤失败。根因：缺少至少 1 条不依赖外部服务的“单元级”用例作为保底集合。

- **集成测试未配置外部环境变量导致大面积失败（当前报错）**：`integration` 作业在默认环境下未设置 `BROWSER_URL`/`BENCHMARK_URL`，但 `test_benchmark` 与所有 `test_captchas[...]` 在缺少兜底跳过逻辑时仍尝试 `p.chromium.connect(BROWSER_URL)`，触发 `ws_endpoint: expected string, got undefined` 并导致 27 个用例失败。该问题属于回归：此前建议的 `pytest.skip(...)` 兜底被移除，导致集成测试在未配置外部依赖时不再自动跳过。

- **Benchmark 服务引用不存在的模块导致 Gunicorn 无法启动（当前报错）**：`benchmark/server.py` 在导入阶段执行 `from apis.arkose import arkose`、`from apis.lemin import lemin`、`from apis.tencent import tencent`、`from apis.yandex import yandex`，但仓库仅包含 `benchmark/apis/{amazon,baidu,botdetect,geetest,hcaptcha,mtcaptcha,recaptchav2}`，缺少上述四个提供方目录与蓝图。Gunicorn 在加载 WSGI 应用时抛出 `ModuleNotFoundError: No module named 'apis.arkose'`，导致 worker 无法启动、容器健康检查失败、CI 集成作业中止。

- **测试样本与可用路由不一致**：`halligan/samples.py` 中包含 `arkose/*`、`lemin`、`tencent`、`yandex/*` 等样本，但 Benchmark 实际未提供对应路由，`test_captchas` 在访问这些端点时将得到 404，缺少兜底跳过会引发集成测试失败。

- **Playwright 事件循环提前关闭（当前报错）**：`basic_test.py::test_captchas` 中 `page.goto(...)` 与后续页面交互在 `with sync_playwright() as p:` 代码块之外执行（缩进错误），导致上下文提前退出并关闭 Playwright 的同步事件循环，运行时在 `goto()` 抛出 `Error: Event loop is closed! Is Playwright already stopped?`。根因是测试生命周期管理不当：在关闭 Playwright 后仍使用其对象。

- **集成作业未可靠拉起 Benchmark 服务（当前报错）**：虽然工作流中使用 `docker compose up -d` 预期拉起 `benchmark` 与 `browser`，但在 Runner 上出现 `net::ERR_CONNECTION_REFUSED` 到 `http://127.0.0.1:3334/health` 以及所有 CAPTCHA 路由的错误，说明基准服务未正确监听宿主机端口或容器未存活。由于健康检查早于依赖安装，且失败时未输出足够的服务日志，排障困难，导致 29/30 用例全部连接拒绝而失败。

- **浏览器健康检查方式错误（当前报错）**：CI 中对浏览器容器的探活使用了 `curl http://127.0.0.1:5000/ | grep 'playwright'` 的 HTTP 内容检查，但 `mcr.microsoft.com/playwright` 的 `run-server` 只暴露 WebSocket 端点（`ws://127.0.0.1:5000/`），根路径 HTTP 不返回标识内容，导致探活一致失败并报 `Browser not healthy`，容器日志却显示 `Listening on ws://0.0.0.0:5000/`。此外，导出的 `BROWSER_URL` 带有多余的查询参数 `?ws=1`，与实际端点不匹配，增加连接不确定性。

- **Pixi 环境激活方式错误导致找不到激活脚本（当前报错）**：在集成作业中通过 `. halligan/.pixi/envs/default/bin/activate` 试图“激活” Pixi 环境以安装 `benchmark/requirements.txt` 并启动 Gunicorn。Pixi 的环境不是 Python `virtualenv`，不会提供该路径下的 `bin/activate` 脚本，因此步骤报错 `No such file or directory` 并中止。正确做法是使用 `pixi run <cmd>` 在 Pixi 环境中执行命令，配合步骤的 `working-directory: halligan` 保证命令在项目环境内运行。

- **Pixi 环境内未包含 pip，导致运行时安装失败（当前报错）**：改用 `pixi run python -m pip install -r ../benchmark/requirements.txt` 后，CI 报错 `/halligan/.pixi/envs/default/bin/python: No module named pip`。根因：Pixi（基于 Conda）默认不自动安装 `pip`，除非将其声明为依赖。对 CI 来说，在 Pixi 环境内临时用 `pip` 安装运行时依赖是脆弱方案：既要求额外增补 `pip` 包，又引入与 Pixi 解析/缓存体系并行的第二套包管理，增加不确定性。

- **跨平台解析失败（当前报错）— `gunicorn` 在 `win-64` 无可用包**：工作区声明了多平台（含 `win-64`），将 `gunicorn>=23,<24` 纳入 `[tool.pixi.dependencies]` 后，Pixi 需要为所有平台求解默认环境，结果在 `win-64` 上无候选包而失败：
  
  ```
  Error:   × failed to solve requirements of environment 'default' for platform 'win-64'
    ╰─▶ Cannot solve the request because of: No candidates were found for gunicorn >=23.0.0,<24.
  ```
  
  根因：`gunicorn` 不支持 Windows/在 conda-forge 上无 `win-64` 构建；一旦出现在“默认环境”的通用依赖中，求解会在 Windows 平台上必然失败。

- **Waitress 启动失败：`Bad module 'benchmark.server'`（当前报错）**：集成作业中通过 `waitress-serve --listen=0.0.0.0:3334 benchmark.server:app` 启动基准服务，但 `benchmark/server.py` 使用了顶层导入 `from apis.* import ...`。在 CI 下 `PYTHONPATH` 指向仓库根目录，仅存在包 `benchmark`，不存在顶层包 `apis`，导致 `ModuleNotFoundError: No module named 'apis'`，Waitress 报告无法导入模块，服务未启动，`/health` 探活持续连接拒绝。
  - 根因：包内模块未使用包相对/绝对导入，破坏了包结构隔离；当以 `benchmark.server` 作为包模块被导入时，`from apis...` 无法解析到 `benchmark/apis/...`。

### 其他关键问题（简述）

- **版本锁定策略不一致**：部分严格锁定（如 `ultralytics==8.2.51`、`transformers==4.42.4`），部分宽松（`faiss-gpu>=1.9.0,<2`），缺少说明与升级策略，容易出现“升级地雷”。
- **模型/权重下载缺少校验与缓存策略**：`halligan/get_models.sh` 未体现哈希校验、断点续传与镜像源回退，首配体验与可重复性弱。
- **结果产出与状态缺少结构化可观测性**：`benchmark` 只写入 `results.log`，缺少结构化日志/指标；`/health` 未返回 JSON 体，自动化探活/诊断不便。
- **仓库治理资料缺失**：未见 `CONTRIBUTING.md`、`CODE_OF_CONDUCT.md`、`SECURITY.md`、`CHANGELOG.md`、Issue/PR 模板等，外部协作与可持续演进成本高。
- **执行脚本缺少配置显式校验**：`halligan/execute.py` 直接读取 `BROWSER_URL`、`BENCHMARK_URL`、`OPENAI_API_KEY` 环境变量未做检查，默认值为 `None` 时会在运行时抛出晦涩异常，调试体验差。
- **静态检查模块解析告警**：CI 中 Ruff 对 `dotenv`、`playwright` 报告 `unresolved-import`，当前推测为缺少对应依赖或安装顺序问题，需确认是否通过安装 `python-dotenv`、`playwright`（或配置忽略）来收敛警告。

-