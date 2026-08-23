# 测试套件重组设计

## 目标

将职责失真的 `tests/sing-box-static.sh` 拆成按被测对象命名、可独立运行的测试脚本，并提供统一入口 `tests/run.sh`。

## 文件边界

- `tests/check-sops-age-key.sh`: age identity 预检。
- `tests/bootstrap.sh`: 首次 bootstrap、Rosetta 和失败传播。
- `tests/prefetch-uu-booster.sh`: UU Booster 缓存预取。
- `tests/rebuild.sh`: rebuild 参数、顺序和失败传播。
- `tests/repository-policy.sh`: flake、Homebrew tap 和单实例约束。
- `tests/sing-box-config.sh`: sing-box JSON 模板、路由、DNS 和 secret map。
- `tests/render-sing-box-config.sh`: Node 渲染器和 sops-nix 模板元数据。
- `tests/publish-sing-box-config.sh`: 配置发布的权限、原子替换和 activation 顺序。
- `tests/run.sh`: 按固定顺序运行全部测试并显示测试名称。

## 约束

- 删除旧的 `tests/sing-box-static.sh`，不保留含义失真的兼容入口。
- 保留全部现有断言、临时目录隔离和失败退出行为。
- 每个测试脚本可从任意工作目录独立运行。
- 不引入测试框架、共享控制层或额外依赖。
- 不提交无关的 `flake.lock`、Claude 设置和备份文件。

## 验证

- 每个拆分脚本独立通过。
- `bash tests/run.sh` 通过。
- 从仓库外目录运行统一入口通过。
- 仓库不再存在对 `tests/sing-box-static.sh` 的活动命令引用。
