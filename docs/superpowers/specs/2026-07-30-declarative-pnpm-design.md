# 声明式 pnpm 设计

## 目标

使用现有 Determinate Nix、nix-darwin 和 Home Manager 配置，在用户环境中
声明式安装 pnpm。新机器执行 `./rebuild.sh` 后应获得由 `flake.lock` 固定的
pnpm，不依赖 `npm install -g` 或 Corepack 产生的可变状态。

## 设计

在 `home.nix` 的“运行时依赖”区域，将 `pkgs.pnpm` 放在现有
`pkgs.nodejs_26` 与 `pkgs.bun` 之间，并继续由 `home.packages` 管理。

不增加 wrapper、activation script、npm prefix、Corepack 配置、额外 Flake
input 或独立模块。

## 验证

1. 修改前的配置求值结果不包含 pnpm，证明检查能够捕获缺失状态。
2. 修改后求值的 Home Manager 用户包包含 pnpm。
3. `nix flake check` 通过。
4. `nix build --no-link .#darwinConfigurations.mac.system` 通过。
5. 用户执行 `./rebuild.sh` 后，`pnpm --version` 成功。

## 文件范围

实现只修改 `home.nix`。设计规范和实现分别提交，便于审查与回滚。
