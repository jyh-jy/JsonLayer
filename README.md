# JsonLayer

> 一个基于 **Flutter** 打造的轻量级桌面端 JSON 工作空间编辑器 · 双击即用 · 双模式编辑 · 可换肤

<p align="center">
  <img src="images/JsonLayer.png" width="140" alt="JsonLayer Logo" />
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
| macOS / Linux | ⚗️ 未验证 | 当前文件路径处理依赖 Windows 路径分隔符 |

## 🖼 截图

- 工作空间 + 对象树模式（自定义背景）  
  ![工作空间对象树](https://bigbang-1394008819.cos.ap-beijing.myqcloud.com/%E9%A6%96%E9%A1%B5.png)

- JSON 源码模式 + 搜索高亮  
  ![JSON源码搜索高亮](https://bigbang-1394008819.cos.ap-beijing.myqcloud.com/%E4%BB%8B%E7%BB%8D.png)

- 对象模式  
  ![对象模式视图](https://bigbang-1394008819.cos.ap-beijing.myqcloud.com/%E4%BB%8B%E7%BB%8D2.png)

## ⚡ 快速开始

### 环境要求

- **Flutter SDK**：稳定版（建议 3.24+）
- **Dart**：`^3.5.0`
- **Windows 构建工具**：Visual Studio 2022（带「使用 C++ 的桌面开发」工作负载）
- Dart 3.0+ 空安全已默认启用

### 提建议可以加群聊
  <img src="images/group.png" width="140" alt="JsonLayer Group" />



### 1. 克隆 & 安装依赖

```bash
git clone https://github.com/你的用户名/json_layer.git
cd json_layer
flutter pub get

