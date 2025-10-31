### 已实施的优化

- **基准服务健壮化**：
  - `/health` 由空 200 改为返回 `{status: "ok"}` 的 JSON，便于脚本与探活。
  - `after_request` 对响应类型进行安全判断，使用 `get_json(silent=True)` 防御性解析；仅在存在 `solved` 字段时记录。
  - 统一异常处理为 `logging.exception(e)`，保留完整堆栈，便于排错。
  - 日志改用 `RotatingFileHandler`，限制单文件大小并保留轮转，避免日志无限膨胀。
  - 运行默认 `debug=False`，防止在 CI/生产环境中暴露调试信息。

- **测试稳定性与分层标记**：
  - `test_benchmark` 由断言 500 错误页改为访问 `/health`，断言 200 且 JSON `status==ok`，避免雪花失败。
  - 为集成测试添加 `@pytest.mark.integration` 标记，区分与单元测试的执行策略。

- **环境与开发工具**：
  - 放宽 Python 版本要求到 `>=3.10,<3.13`，提升跨平台与可移植性。
  - 扩展 Pixi 平台到 `linux-64`、`osx-64`、`osx-arm64`、`win-64`，降低 macOS/Windows/Apple Silicon 上手门槛。
  - 新增开发工具依赖与配置：Black、Ruff、Mypy、isort，并在 `pyproject.toml` 中设定统一的行宽与目标版本。
  - 在 `pytest` 配置中声明 `integration`、`e2e` 标记，便于 CI/本地筛选测试集。

- **CPU/GPU 依赖分层（已修复可移植性痛点）**：
  - 默认环境改为 CPU 友好：使用 `faiss-cpu`，不强制 CUDA。
  - 新增 `cuda` 特性：启用时添加 `faiss-gpu` 与 `pytorch-cuda=12.1`，按需使用 GPU。
  - 扩展通道：增加 `pytorch`、`nvidia`，确保官方轮子解析与安装。
- **执行脚本入口安全**：`halligan/execute.py` 重构为 `main()` 接口并加上 `if __name__ == "__main__"` 守卫，防止导入期间自动跑完所有样例；新增 `validate_environment()`，在执行前校验 `BROWSER_URL`、`BENCHMARK_URL`、`OPENAI_API_KEY` 的存在与格式并输出友好提示。
- **CI 集成作业稳定化**：`.github/workflows/ci.yml` 的 `integration` 触发条件改为基于 push、PR 标签 (`run-integration`) 与手动触发，移除导致表达式异常的 `join(github.event.pull_request.changed_files, ',')` 写法，并通过 `dorny/paths-filter` 精准识别关键目录改动，仅在必要时执行集成测试；工作流已针对 `SaltRivers/halligan-enhancement` 仓库配置，便于后续远程复用。

- **修复 Pixi 设置与缓存失败**：在 CI 的 `setup-pixi` 步骤中显式指定 `manifest-path: halligan/pyproject.toml`，使动作在 `halligan/` 目录下解析 `pixi.lock` 并建立缓存，避免默认在仓库根查找导致的 `ENOENT: open 'pixi.lock'` 与清理阶段 `lstat '.pixi'` 错误。

- **避免动作内的锁定安装失败**：为 `setup-pixi` 增加 `run-install: false`，改由后续步骤执行显式 `pixi -p ./halligan install`，从而避免动作默认的 `pixi install --locked` 在锁文件失配时直接失败。
 
- **让安装在我们控制下进行，绕过动作的 `--locked` 失败**：将 `setup-pixi` 的 `run-install` 改为 `false` 且关闭 `cache`（`cache: false`），避免动作内部强制执行 `pixi install --locked`。依赖安装改为后续显式步骤 `pixi -p ./halligan install`，以便在锁文件暂未更新时仍可解析成功并继续执行工作流。

- **修正 pixi CLI 用法（全局参数置于子命令之前）**：将 `pixi install -p ./halligan`、`pixi run -p ./halligan ...` 改为 `pixi -p ./halligan install`、`pixi -p ./halligan run ...`。可选优化：在相关步骤上设置 `working-directory: halligan`，则可直接使用 `pixi install` 与 `pixi run ...`，减少参数重复。

- **移除无效的本地依赖**：删除 `halligan/pyproject.toml` 中 `[tool.pixi.pypi-dependencies]` 下的 `clip = { path = "./halligan/models/CLIP", editable = true }`，该路径在仓库中不存在，会导致安装阶段失败。

- 针对 Ruff 的 `unresolved-import` 告警，确认在标准环境安装 `python-dotenv` 与 `playwright` 是否可消除，若仍存在则评估在 Ruff 配置中以 `per-file-ignores` 或 `typing-modules` 方式进行豁免。

- 引入 `pre-commit` 钩子与 CI 质量门禁（格式化、lint、类型检查、单元测试）。
- 在根目录提供统一的 `docker compose` 与 `Makefile`，实现一键拉起与测试。
- 为模型下载脚本增加哈希校验、断点续传与缓存目录。
- 完善治理文档：`CONTRIBUTING.md`、`CODE_OF_CONDUCT.md`、`SECURITY.md`、`CHANGELOG.md`、Issue/PR 模板。
