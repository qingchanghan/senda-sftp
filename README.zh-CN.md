# Senda

**A path for your files.** 免费、原生的 macOS SFTP 文件传输工具，直接沿用现有 SSH 配置，支持 `ProxyCommand` 和 `ProxyJump`。

[下载](https://github.com/qingchanghan/senda-sftp/releases/latest) · [English](README.md) · [贡献指南](CONTRIBUTING.md) · [更新记录](CHANGELOG.md) · [MIT 许可](LICENSE)

![Senda 文件工作台：目录整体进度与实时下载速度](docs/images/transfer-speed-light.png)

<details>
<summary>Dark appearance / 深色外观</summary>

![Senda dark workspace](docs/images/transfer-speed-dark.png)

</details>

## 功能

- 本地与远程双栏浏览；支持 Finder 拖入上传、拖到 Finder/桌面下载。
- ⌘ 点选、⇧ 连选、全选；文件与目录可混合批量传输。
- **文件直达**：在任一地址栏粘贴文件路径并回车，查看文件信息后一键上传或下载。
- **目录整体进度**：先统计全部普通文件，再累计字节数；切换子文件不会重置进度条。
- **实时传输速度**：队列和详情展示下载/上传速度，自动切换 B/s、KB/s、MB/s、GB/s。
- 每条任务可查看源机器/路径、目标机器/路径，并复制详情。重名自动保留两份，显示实际改名后的目标。
- 原生虚拟化文件列表、连接复用、进度局部刷新；传输时仍可浏览目录。
- 明暗主题统一使用 [Beautiful UI](https://www.beautifului.dev/) 的全局令牌。[组件来源与许可](THIRD_PARTY_NOTICES.md)。

## 下载

在 [GitHub Releases](https://github.com/qingchanghan/senda-sftp/releases/latest) 下载 `Senda-macOS-arm64.dmg`。
双击打开，把 `Senda.app` 拖到 `Applications`，完成后推出磁盘映像。
需要 Apple silicon 和 macOS 13+；也提供 ZIP 下载。
当前安装包使用 ad hoc 签名，尚未经过 Apple 公证。
Intel 用户可以从源码构建；尚未在 Intel 硬件上验证。

## 构建运行

需要 macOS 13+、含 Swift 5.9+ 的 Apple Command Line Tools（或 Xcode），以及用于检查设计令牌的 Python 3。没有 Node/Electron 或第三方运行时依赖。

```bash
xcode-select --install  # 已安装则跳过
git clone https://github.com/qingchanghan/senda-sftp.git
cd senda-sftp
./scripts/build-app.sh
open dist/Senda.app
```

构建脚本限制两个任务，输出 `dist/Senda.app` 和当前架构的 DMG、ZIP；可把应用拖到「应用程序」。本机构建使用 ad hoc 签名，尚未做 Developer ID 签名和公证；已验证 Apple silicon，Intel 尚未验证。

从 Harbor 升级会一次性迁移已保存的主机、路径、隐藏文件和代理 PATH 设置，原偏好设置仍保留。

## 连接与使用

先在终端确认 `ssh dev-box` 可用。SSH 配置示例：

```sshconfig
Host dev-box
    HostName dev.example.com
    User developer
    ProxyCommand /absolute/path/to/your-proxy %h %p
```

在侧栏选择主机，或在顶部输入别名。首次连接进入远程登录目录，后续恢复上次有效目录。系统 `/usr/bin/ssh` 处理认证、代理、密钥、主机校验以及完整 SSH 规则；Senda 不修改 SSH 配置，也不保存密码。代理依赖特定 Python 环境时，在设置中填入其 `bin` 目录；已自动补全常用 Conda、Homebrew、`~/.local/bin` 路径。

左栏是本地，右栏是远程；双击目录进入，路径栏回车跳转。选中多个项目后拖拽或使用上传/下载按钮。拖到目录行会传入该目录；双击远程普通文件会下载到当前本地目录。

地址栏也支持**具体文件的完整路径**。粘贴并回车后，面板会展示文件名、大小和目标目录，点击「上传此文件」或「下载此文件」即可传输；点击「所在文件夹」回到浏览。仅解析地址不会自动开始传输。

目标始终是对侧面板的当前文件夹；如果对侧也处于文件直达状态，则使用该文件的父目录。重名仍会自动保留两份。相对路径以当前文件夹为基准，本地支持 `file://` 和 `~`，远程 `~/` 指向远程登录目录。显式指定隐藏文件不需要打开「显示隐藏文件」，也不要求父目录可列出；文件符号链接和特殊文件仍不支持传输。

![文件直达：文件信息、传输目标与上传下载按钮](docs/images/file-address-light.png)

<details>
<summary>文件直达的深色外观</summary>

![深色文件直达](docs/images/file-address-dark.png)

</details>

| 快捷键 | 操作 |
| --- | --- |
| ⌘K | 连接 |
| ⌘R | 刷新 |
| ⌘O | 选择本地目录 |
| ⇧⌘. | 显示/隐藏文件 |
| ⌘A / ⇧⌘A | 文件列表全选 / 取消选择 |
| Return | 打开选中目录 |

目录任务会先显示「计算大小」，然后展示整棵目录的累计字节和百分比；每个队列任务单独统计。队列详情保留到清除队列或退出应用。

传输中会在进度条下方及详情中显示实时速度，单位按 B/s、KB/s、MB/s、GB/s 自动切换（1 KB = 1,000 B）。速度按最近约 2 秒实际传输的字节计算，每半秒刷新；停滞时降到 0 B/s，完成或取消后停止显示。下载目录时，切换子文件不会重置速度统计。

![传输详情：实时速度与源、目标路径](docs/images/transfer-speed-details.png)

## 传输边界

- 支持 SFTP v3 和 UTF-8 文件名，服务器需启用 SFTP 子系统。
- 统计后发现文件大小变化会报错；目录扫描不是文件系统快照，也不做同步或校验和验证。
- 目录内符号链接会跳过，单独传输符号链接或特殊文件会报错。普通文件传递权限，但不保留所有者、时间戳、扩展属性或 ACL。
- 取消/失败可能留下已完成的子文件与目录；断网或强制退出可能留下 `.senda-<UUID>.part`。暂不支持续传、目录合并、删除或同步。
- 队列顺序执行，同主机任务复用连接；单文件采用 16 × 32 KiB 请求窗口。

## 开发与检查

```bash
swift build --product Senda -j 2
./scripts/check.sh
# 可选：只在远程 /tmp 随机目录中测试，结束自动清理
.build/debug/Senda --batch-checks dev-box
# 只读诊断
.build/debug/Senda --probe dev-box /remote/path
# 离线演示数据，不读取 SSH 配置和用户文件
open dist/Senda.app --args --demo
# 文件直达界面；加 --dark 查看深色外观
open dist/Senda.app --args --demo --demo-file
# 持续更新速度的离线演示
open dist/Senda.app --args --demo --demo-speed
```

更多信息：[架构与全局令牌](docs/architecture.md)、[验证记录](docs/verification.md)、[发布说明](docs/releasing.md)。本地协议检查使用 macOS 自带的 SFTP server，不需要开启「远程登录」。

MIT 开源；截图全部使用虚构主机、路径和任务。
