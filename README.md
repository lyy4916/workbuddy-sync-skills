# WorkBuddy 多设备同步技能

三个 Skill 帮你在多台 Mac 之间同步 WorkBuddy 的身份、记忆、技能和配置。

## 技能列表

| Skill | 适用场景 | 同步后端 | 特点 |
|-------|---------|---------|------|
| `workbuddy-multi-device-sync` | 2 台 Mac | GitHub | 最简单，Token 认证，一行命令设置第二台 |
| `workbuddy-icloud-sync` | 2 台 Mac | iCloud Drive | 无需任何外部账号，同一 Apple ID 即可 |
| `workbuddy-multi-machine-sync` | 3+ 台 Mac | GitHub 或 iCloud | 机器命名、注册表、状态查看、增强冲突处理 |

## 快速开始

### 方式一：在 WorkBuddy 中安装

在 WorkBuddy 对话中输入：

```
帮我安装 workbuddy-sync 技能
```

或使用 find-skills 搜索：

```
找一个多设备同步的技能
```

### 方式二：手动安装

将技能文件夹复制到 `~/.workbuddy/skills/`：

```bash
git clone https://github.com/lyy4916/workbuddy-sync-skills.git
cp -r workbuddy-sync-skills/workbuddy-multi-device-sync ~/.workbuddy/skills/
# 或安装 iCloud 版 / 多机版
```

## 各方案对比

### GitHub 双机版 (`workbuddy-multi-device-sync`)

- 使用 GitHub 私有仓库作为同步后端
- 后台守护进程每 5 分钟自动同步
- Mac B 设置：一行命令搞定
- 适合：有 GitHub 账号的用户

### iCloud 双机版 (`workbuddy-icloud-sync`)

- 使用 iCloud Drive 中的 Git bare repo
- 无需任何外部服务或账号
- 同一 Apple ID 的 Mac 自动可用
- 适合：所有 Mac 用同一个 Apple ID 的用户

### 多机版 (`workbuddy-multi-machine-sync`)

- 支持 3 台以上 Mac 同时同步
- 机器命名 + 注册表（machines.json）
- `wbstatus` 命令查看所有机器状态
- 增强冲突处理（stash → pull → pop）
- 适合：工作室、办公室多设备场景

## 同步内容

- 身份文件：SOUL.md、IDENTITY.md、USER.md
- 记忆：MEMORY.md、memory/ 目录
- 技能：skills/ 目录
- 配置：settings.json

## 不同步的内容

- binaries/（各机独立安装）
- workbuddy.db（SQLite，并发会损坏）
- .mcp.json（localhost 端口各机不同）
- sessions/、logs/、traces/

## 技术架构

每个 Skill 包含：

```
skill-name/
├── SKILL.md                      # 工作流指南
├── scripts/
│   ├── auto-sync.sh              # 自动同步脚本
│   ├── start-sync-daemon.sh      # 守护进程启动器
│   └── setup-mac-b.sh.template   # 第二台机器设置模板
└── references/
    ├── gitignore-template        # .gitignore 模板
    └── sync-architecture.md      # 架构说明 + 故障排查
```

## 许可

MIT License - 自由使用和分发。
