# Flutter 项目分包规范（Architecture & Package Structure）

> 本文档定义了一套可复用的 Flutter 分包风格与目录结构，适用于从零搭建新项目，或统一既有团队的分包约定。
> 核心思路：**「按职责分层 + 按业务/功能分包」**，保证高内聚、低耦合、依赖方向单向清晰。

---

## 一、设计理念

1. **职责分层（纵向）**：把「网络传输 → 数据模型 → 状态管理 → 页面 → 组件 → 基础设施」拆成互不越界的层，每层只做一件事。
2. **按业务分包（横向）**：同一业务（如 `pay`、`question`、`hospital`）的相关文件放在一起，新增/删除某个业务模块时只动一个目录。
3. **单向依赖**：上层依赖下层，下层绝不反向依赖上层（详见「六、依赖规则」）。
4. **约定大于配置**：通过统一的命名后缀（`Page` / `Component` / `Req` / `Vo`）让成员「看文件名就知道是干什么的」。

---

## 二、目录结构总览

```
lib/
├── main.dart                      # 入口：只负责 runApp，保持极薄
├── api/                           # 网络接口层：按业务模块导出顶层函数
│   ├── LoginApi.dart
│   ├── QuestionApi.dart
│   └── PayApi.dart
├── domain/                        # 领域模型（数据传输对象 DTO）
│   ├── PageResult.dart            #   通用泛型分页结果
│   ├── req/                       #   请求参数对象（入参）
│   │   ├── LoginReq.dart
│   │   ├── answer/                #   → 按业务再分子包
│   │   ├── chat/
│   │   └── pay/
│   ├── vo/                        #   响应对象（出参）
│   │   ├── login/
│   │   ├── pay/
│   │   └── question/
│   ├── home/                      #   业务实体/展示模型（非 req/vo 类）
│   │   ├── QuestionnaireItem.dart
│   │   └── TopBannerItem.dart
│   └── hospital/
│       └── DepartmentItem.dart
├── model/                         # 本地业务实体模型
│   └── answer/
│       ├── AnswerRecord.dart
│       └── AnswerSheetVo.dart
├── pages/                         # 页面：每个页面一个文件，按业务分包
│   ├── login/
│   ├── home/
│   ├── question/
│   ├── hospital/
│   ├── pay/
│   └── mine/
│       └── account/               # → 支持多级子包
├── components/                    # 可复用 UI 组件：按业务/页面分包
│   ├── main/
│   ├── chat/
│   ├── question/
│   └── hospital/
├── stores/                        # 状态管理与持久化
│   ├── TokenManager.dart          #   单例 + 本地持久化
│   └── UserInfoStoreController.dart
├── routes/
│   └── index.dart                 # 统一路由表 + 主题配置
├── contants/                      # 常量（注意：沿用历史拼写 contants）
│   ├── DioContants.dart           #   BaseUrl / 超时 / 接口路径
│   └── CommonConstant.dart        #   共享存储 key 等
├── utils/                         # 基础设施工具类
│   ├── DioUtil.dart               #   网络单例封装
│   ├── FontUtil.dart
│   ├── ToastUtil.dart
│   └── ShowDialogUtil.dart
└── assets/                        # 静态资源（图片等）
```

---

## 三、各层职责与规范

### 1. `api/` — 网络接口层

**职责**：封装 HTTP 请求，对上层暴露「业务语义」的顶层函数；页面只调用这里，不直接碰 Dio。

**规范**：
- 按业务模块命名文件：`XxxApi.dart`。
- 每个接口写一个**顶层函数**，函数名见名知义（`getPayOrderPage` / `closeOrder` / `PayRefundApply`）。
- 入参接收 `domain/req` 对象，返回值是 `domain/vo` 或 `PageResult<T>`。
- 统一通过 `DioRequest()` 单例发请求，禁止各自 `new Dio()`。
- 错误处理：失败时 `throw Exception(msg)`，由调用方 catch 并 Toast 提示。

```dart
// api/PayApi.dart（示例）
Future<PageResult<PayOrderVo>> getPayOrderPage(PayOrderPageReq req) async {
  final response = await DioRequest().post(ApiConstants.PayOrderPage, data: req.toJson());
  if (response['code'] == 200 && response['data'] != null) {
    return PageResult.fromJson(response['data'], (item) => PayOrderVo.fromJson(item));
  }
  throw Exception(response['msg'] ?? '获取订单列表失败');
}
```

### 2. `domain/` — 领域模型（DTO）

**职责**：与后端接口直接对应的传输对象，是「网络边界」的数据契约。

| 子目录 | 角色 | 关键方法 |
|--------|------|----------|
| `req/` | 请求入参对象 | `toJson()` 序列化 |
| `vo/` | 响应出参对象 | `fromJson()` 反序列化（`factory`），可选格式化 getter |
| 其他（`home/`、`hospital/`） | 业务实体 / 展示模型 | 按需 |

**规范**：
- 命名后缀严格区分：请求 `XxxReq`，响应 `XxxVo`。
- 字段用 `final`（不可变），构造器用命名参数 + `required` 区分必选/可选。
- 响应对象建议加「展示格式化 getter」而不是在页面里算（如金额分→元、时间 T 分隔）。

```dart
// domain/vo/pay/PayOrderVo.dart（示例）
class PayOrderVo {
  final num totalAmount;        // 后端单位为「分」
  final String createTime;
  // ...
  factory PayOrderVo.fromJson(Map<String, dynamic> json) { /* ... */ }
  String get formattedAmount => (totalAmount / 100).toStringAsFixed(2);
}
```

> ⚠️ 约定：DTO 里的金额用 `num`，金额换算放在 `Vo` 的 getter 中，不要在页面散落魔法计算。

### 3. `model/` — 本地业务实体模型

**职责**：与前端展示/业务逻辑强相关的实体（例如 `AnswerRecord`），通常与 `domain` 概念相近但更偏「业务实体」而非纯传输契约。

> 说明：实践中 `domain/` 与 `model/` 存在概念重叠（如 `AnswerSheetVo` 同时出现在两处）。**新项目建议二选一**：
> - 若接口 DTO 与业务实体基本一致 → 只保留 `domain/`。
> - 若存在「传输对象」与「本地实体」明显分野 → 保留两者并明确边界：`domain` 承载网络传输，`model` 承载本地业务建模。

### 4. `pages/` — 页面层

**职责**：一个页面一个文件，负责组合 `components`、调用 `api`、管理本页 `State`。

**规范**：
- 文件命名 `XxxPage.dart`（如 `MyOrdersPage.dart`）。
- 按业务分包，业务复杂时再分子包（如 `mine/account/`）。
- 页面负责「编排」：拉数据 → `setState` → 渲染；重逻辑尽量下沉到 `api`/`stores`。
- 状态管理：页面私有状态用 `StatefulWidget + setState`；跨页共享状态用 `stores/` 的 GetX Controller。

### 5. `components/` — 可复用 UI 组件

**职责**：可被多个页面复用的「纯展示 + 回调」组件，不直接发请求。

**规范**：
- 文件命名 `XxxComponent.dart` / `XxxCard.dart`（如 `AnswerCard.dart`、`ReserverDetailComponent.dart`）。
- 按业务/所属页面分包。
- 数据通过**构造器传入**，事件通过**回调 `Function` 传出**，保持无状态（`StatelessWidget`）优先。

```dart
// components/main/AnswerCard.dart（示例）
class AnswerCardComponent extends StatelessWidget {
  final List<QuestionnaireItem> questionnaires;
  final Function(QuestionnaireItem)? onQuestionnaireTap;   // 事件回调上抛
  // ...
}
```

### 6. `stores/` — 状态管理与持久化

**职责**：跨页共享的状态 + 本地持久化（token、用户信息等）。

**规范**：
- 全局单例：`final tokenManager = TokenManager();`（文件底部导出单例，无需依赖注入）。
- 响应式状态：继承 `GetxController`，用 `.obs` 包装可观察对象，组件用 `Obx` 订阅。
- 需要启动时初始化（如 `TokenManager.init()`），在 `main.dart` 或首屏前调用。

### 7. `routes/` — 路由

**职责**：统一管理命名路由表 + 全局主题。

**规范**：
- `index.dart` 导出 `getRootWidget()` 根组件 + `getRootRoutes` 路由 Map。
- 新页面必须在此注册路由（`/feature/page` 命名风格，注释说明用途）。
- 全局字体/主题统一在此配置。

### 8. `contants/` — 常量

**职责**：集中管理全局常量，**禁止魔法值散落代码**。

| 文件 | 内容 |
|------|------|
| `DioContants.dart` | `GlobalConstants`（BaseUrl/超时/成功码）+ `ApiConstants`（接口路径，用 getter 统一） |
| `CommonConstant.dart` | 共享存储 key（如 `tokenKey`） |

> 说明：`contants` 为历史拼写（应为 `constants`），为保持一致性沿用原目录名。

### 9. `utils/` — 基础设施工具类

**职责**：与业务无关的通用能力（网络、字体、Toast、弹窗、安全区等）。

**规范**：
- 单例网络封装 `DioUtil.dart`：拦截器统一注入 `Authorization`、统一错误处理、大整数精度保护。
- 弹窗统一走 `ShowDialogUtil`，Toast 统一走 `ToastUtil.showSnackBar`。

---

## 四、命名规范（约定大于配置）

| 类型 | 文件命名 | 类命名 | 示例 |
|------|----------|--------|------|
| 页面 | `XxxPage.dart` | `XxxPage` | `MyOrdersPage` |
| 组件 | `XxxComponent.dart` / `XxxCard.dart` | `XxxComponent` / `XxxCard` | `AnswerCardComponent` |
| 请求对象 | `XxxReq.dart` | `XxxReq` | `PayOrderReq` |
| 响应对象 | `XxxVo.dart` | `XxxVo` | `PayOrderVo` |
| 业务实体 | `XxxItem.dart` | `XxxItem` | `QuestionnaireItem` |
| API 层 | `XxxApi.dart` | 顶层函数（无类） | `getPayOrderPage` |
| 常量 | `XxxContants.dart` / `XxxConstant.dart` | `XxxConstants` / `XxxConstant` | `ApiConstants` |
| Store | `XxxManager.dart` / `XxxController.dart` | `XxxManager` / `XxxController` | `TokenManager` |

---

## 五、一次请求的完整数据流

```
Page (触发) 
  → 构造 Req 对象 (domain/req)
  → 调用 Api 顶层函数 (api/)
    → DioRequest().post() (utils/DioUtil.dart)
      → 拦截器注入 token / 解析 envelope
  → 反序列化为 Vo (domain/vo)
  → 回传 Page 渲染 (setState / Obx)
  → 跨页共享数据写入 stores/
```

---

## 六、依赖规则（单向依赖）

```
pages ──┐
        ├──> components ──> domain/model
        ├──> api ─────────> domain/model, utils, contants
        ├──> stores ──────> domain/model, utils, contants
        └──> utils / contants（基础设施，无业务依赖）

禁止反向：utils/contants 不得依赖 pages/components/stores
禁止越层：components 不得直接发请求；api 不得引用页面
```

---

## 七、新增一个业务模块的标准流程

以新增「订单（Order）」模块为例：

1. **定义 DTO**：在 `domain/req/order/` 建 `OrderPageReq.dart`，在 `domain/vo/order/` 建 `OrderVo.dart`。
2. **定义接口路径**：在 `contants/DioContants.dart` 的 `ApiConstants` 中添加 `OrderPage` 路径。
3. **写 API 层**：在 `api/` 建 `OrderApi.dart`，暴露 `getOrderPage()` 等顶层函数。
4. **写状态（如需要）**：在 `stores/` 建共享 Controller。
5. **写页面**：在 `pages/order/` 建 `OrderListPage.dart`，调用 `api` 编排数据。
6. **抽组件**：列表项等可复用部分抽到 `components/order/`。
7. **注册路由**：在 `routes/index.dart` 的 `getRootRoutes` 注册 `/order/list`。

---

## 八、团队约定速查（Checklist）

- [ ] 页面放 `pages/<业务>/`，组件放 `components/<业务>/`
- [ ] 请求/响应对象分别用 `Req` / `Vo` 后缀，`final` 字段 + 命名构造器
- [ ] 所有网络请求走 `DioRequest()` 单例，不裸用 `Dio`
- [ ] 所有弹窗走 `ShowDialogUtil`，所有提示走 `ToastUtil`
- [ ] 无魔法值：URL、超时、成功码、存储 key 全部进 `contants/`
- [ ] 金额/时间格式化放在 `Vo` getter 中，不散落页面
- [ ] 大整数（订单号等）用 `BigInt`/字符串保护，避免 JS 精度截断
- [ ] 新页面在 `routes/index.dart` 注册路由
- [ ] 遵循不可变原则：不原地修改对象，创建新对象返回
