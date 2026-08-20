# JsonLayer

> 一个基于 **Flutter** 打造的轻量级桌面端 JSON 工作空间编辑器 · 双击即用 · 双模式编辑 · 可换肤

<p align="center">
  <img src="https://bigbang-1394008819.cos.ap-beijing.myqcloud.com/JsonLayer.png" width="140" alt="JsonLayer Logo" />
</p>

<p align="center">
  <a href="#特性"><strong>特性</strong></a> ·
  <a href="#快速开始"><strong>快速开始</strong></a> ·
  <a href="#快捷键"><strong>快捷键</strong></a> ·
  <a href="#项目结构"><strong>结构</strong></a> ·
  <a href="#开源协议"><strong>协议</strong></a>
</p>

---

## ✨ 特性

- 🗂 **工作空间文件树** —— 文件夹 / JSON 文档 / LOG 文档统一管理，支持外部 JSON 文件直接拖入导入、右键菜单（新建 · 重命名 · 删除 · 在资源管理器中打开）
- 📑 **多标签页编辑** —— 右键「关闭其他 / 关闭所有 / 定位」，标签过多时可用 **鼠标滚轮** 切换，带 3 秒高亮定位动画
- 🔀 **JSON / 对象树双模式** —— 源码模式提供**格式化 / 压缩**，对象树模式完整展示 `{}` 结构并支持整段文本选择，切换时保留各自状态不重新渲染
- 🔍 **全局搜索 & 高亮** —— `Ctrl+F` 呼出，**双击选中文字后再按 Ctrl+F 自动填充**，支持独立撤销栈（`Ctrl+Z` 焦点在搜索栏时只回退搜索词）
- 💾 **全局保存** —— `Ctrl+S` 无论焦点在顶部、侧边栏或内容区都能保存当前活跃文档，不强制点内容区
- 🏷 **智能重命名** —— `.json / .log` 后缀自动隐藏不参与编辑，确认时自动追加原始扩展名，杜绝手滑改错后缀
- 🎨 **三种皮肤模式** —— 亮色模式 / 内置背景（bgTwo.jpg，顶栏侧栏毛玻璃）/ 自定义上传背景，打开文件时内容编辑区保持原底色不被背景影响
- 🛡 **Toast 幂等去重** —— 高频点击不会连环弹相同提示（1.5s 窗口 + 业务语义 key）

## 🎯 平台支持

| 平台 | 状态 | 说明 |
| :--- | :--: | :--- |
| **Windows** | ✅ 主支持 | x64，已提供 Inno Setup 安装脚本（`installer/json_layer.iss`） |
| Web | ❌ 暂不支持 | 当前实现依赖 `dart:io` 本地文件系统能力 |
| macOS / Linux | 🔧 未验证 | 当前文件路径处理依赖 Windows 路径分隔符 |

## 🖼 截图
 
- 工作空间 + 对象树模式（自定义背景）
  https://bigbang-1394008819.cos.ap-beijing.myqcloud.com/%E9%A6%96%E9%A1%B5.png
- JSON 源码模式 + 搜索高亮
  https://bigbang-1394008819.cos.ap-beijing.myqcloud.com/%E4%BB%8B%E7%BB%8D.png
- 对象模式
  https://bigbang-1394008819.cos.ap-beijing.myqcloud.com/%E4%BB%8B%E7%BB%8D2.png

## ⚡ 快速开始

### 环境要求

- **Flutter SDK**：稳定版（建议 3.24+，最低支持 Dart `^3.11.5`）
- **Windows 构建工具**：Visual Studio 2022（带「使用 C++ 的桌面开发」工作负载）
- Dart 3.0+ 空安全已默认启用

### 1. 克隆 & 安装依赖

```bash
git clone https://github.com/<你的用户名>/json_layer.git
cd json_layer
flutter pub get
```

### 2. 本地运行

> ⚠️ 本项目默认桌面 Windows 为目标平台，**不会自动执行** `yarn winServe`。

```bash
flutter run -d windows
```

首次启动会进入欢迎页，选择一个磁盘目录作为**工作空间**，程序会在该目录下生成 `JsonLayer` 文件夹用于存放所有文档。

### 3. 打包发布

**Windows 可执行文件：**

```bash
flutter build windows --release
# 产物路径：build/windows/x64/runner/Release/
```

**打包成安装程序（可选）：**

项目已提供 Inno Setup 脚本，安装 [Inno Setup](https://jrsoftware.org/isdl.php) 后编译：

```
installer/json_layer.iss
```

## ⌨️ 快捷键

| 快捷键 | 作用 | 生效范围 |
| :--- | :--- | :--- |
| `Ctrl + S` | 保存当前活跃文档 | **全局**（无需点内容区） |
| `Ctrl + F` | 打开搜索栏；如有选中文本自动填入 | 编辑器打开时 |
| `Ctrl + Z` | 撤销；搜索栏打开时优先撤销搜索词 | 全局按焦点判断 |
| `Enter` | 所有弹窗（重命名 / 设置 / 警告）回车确认 | 任意弹窗 |
| **鼠标滚轮** | 标签栏标签过多时，滚轮切换当前标签 | 悬停在标签栏 |
| 双击选词 | 连字符 `-` 视为单词的一部分，不会中断选中 | 编辑器内容区 |

## 📁 项目结构

```
lib/
├── main.dart                      # 入口：窗口初始化、主题、路由、皮肤背景壳
├── routes/index.dart              # 路由表（欢迎页 / 首页）
├── pages/
│   ├── welcome/WelcomePage.dart   # 首次启动：选择工作空间路径
│   └── home/HomePage.dart         # 主页面：AppBar + 左侧树 + 标签 + 编辑器 + 右侧面板
├── components/
│   ├── common/                    # 通用组件
│   │   ├── SafeSnackBar.dart      # ✨ 幂等 toast（核心去重工具）
│   │   ├── SearchBar.dart         # 搜索栏（独立 Ctrl+Z 撤销）
│   │   └── SearchHighlight.dart   # 搜索结果高亮工具
│   └── home/                      # 主页业务组件
│       ├── WorkspaceTree.dart     # 文件/目录树（拖拽 · 右键 · 重命名隐藏后缀）
│       ├── DocumentTabs.dart      # 多标签 + 滚轮切换 + 右键菜单
│       ├── JsonEditor.dart        # JSON 源码模式（格式化/压缩/搜索）
│       ├── ObjectTreeEditor.dart  # 对象树模式（{} 完整渲染 + SelectionArea）
│       └── RequestResponsePanel.dart
├── stores/                        # Provider 状态管理
│   ├── ThemeStore.dart            # 皮肤三态（亮 / 内置背景 / 自定义背景）
│   ├── TabStore.dart              # 标签页、脏标记、活跃文档
│   ├── WorkspaceStore.dart        # 工作空间路径、持久化
│   └── EditorStore.dart           # 编辑器内部状态
├── services/                      # 基础设施层
│   ├── WorkspaceService.dart      # 工作空间抽象接口
│   └── FileWorkspaceService.dart  # 磁盘文件实现（实际读写目录/文档）
├── model/DocumentItem.dart        # 文档 / 文件夹业务模型
├── contants/CommonConstant.dart   # 颜色、尺寸、主色 #6366F1 等全局常量
└── utils/JsonUtil.dart            # JSON 解析 / 格式化 / 压缩工具
```

## 🛠 主要依赖

| 包 | 用途 |
| :--- | :--- |
| `provider` | 状态管理（ThemeStore / TabStore / WorkspaceStore / EditorStore） |
| `shared_preferences` | 工作空间路径、皮肤模式、背景图本地持久化 |
| `path_provider` | 自定义背景图本地存储路径 |
| `file_picker` | 工作空间目录选择、自定义背景图片上传 |
| `desktop_drop` | 外部文件拖入左侧树直接导入 JSON |
| `window_manager` | 窗口初始化、显示与聚焦 |
| `flutter_code_editor` + `highlight` | JSON 源码高亮基础能力 |
| `font_awesome_flutter` | 侧栏与工具栏图标 |
| `url_launcher` | 跳转到 GitHub、文档链接 |

## 🤝 贡献

欢迎任何形式的 PR！建议流程：

1. Fork → 创建 feature 分支
2. 跑 `flutter analyze` 无警告
3. 改动涉及用户交互时，同步更新 [ARCHITECTURE.md](ARCHITECTURE.md) 分包规范说明
4. 提 PR 时简单描述改动点 + 对应 Issue（如无则直接写改动动机）

## 📄 开源协议

本项目采用 **MIT License**，你可以自由地用于个人、商业、二开衍生项目，只需保留原始版权声明即可。

---

<p align="center">
  Made with 💙 by 波仔 · JsonLayer
</p>
