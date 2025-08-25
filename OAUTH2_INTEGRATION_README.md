# OpenObserve OAuth2 集成说明

本项目已经完全替换了OpenObserve的原有用户名密码登录系统，集成了OAuth2认证。所有通过OAuth2登录的用户都会被设置为root角色，具有完整的系统访问权限。

## 主要修改内容

### 后端修改

#### 1. 认证验证器 (`src/handler/http/auth/validator.rs`)
- 添加了OAuth2User结构体
- 添加了Authority结构体
- 添加了validate_oauth2_token函数
- 添加了check_user_authorities函数

#### 2. 用户管理服务 (`src/service/oauth2_user.rs`) (新建)
- 根据OAuth2返回的用户信息自动创建或更新用户
- 设置用户角色为root
- 生成用户邮箱格式：account@tenantId.com
- 使用固定密码"oldcamel"和固定盐值

#### 3. 用户API (`src/handler/http/request/users/mod.rs`)
- 修改了authentication函数，改为OAuth2 token验证
- 添加了新的oauth2_login端点
- 支持通过Authorization header或access_token参数传递token

#### 4. 路由配置 (`src/handler/http/router/mod.rs`)
- **修改内容**: 在auth scope中添加了oauth2_login服务

#### 5. 服务模块 (`src/service/mod.rs`)
- **修改内容**: 添加了oauth2_user模块

#### 6. 配置管理 (`src/config/src/config.rs`)
- **修改内容**: 添加了ZO_OAUTH2_USERINFO_URL配置项

### 前端修改

#### 1. 认证服务 (`web/src/services/auth.ts`)
- 添加了OAuth2登录方法
- 修改了sign_in_user方法

#### 2. 登录组件 (`web/src/components/login/Login.vue`)
- 移除了用户名和密码输入框
- 改为单一的OAuth2登录按钮
- 通过CAS回调进行认证

## 环境变量配置

### 必需的环境变量

```bash
# OAuth2角色权限配置 - 现在默认使用root
ZO_OAUTH2_ALLOWED_ROLES=ROLE_ADMIN

# OAuth2用户信息接口地址 - 请替换为您的实际OAuth2服务器地址
ZO_OAUTH2_USERINFO_URL=http://your-oauth2-server/userinfo

# 其他配置
ZO_BASE_URI=/openobserve
```

### 重要说明

- **ZO_OAUTH2_USERINFO_URL**: 这是获取OAuth2用户信息的接口地址，必须配置为您的实际OAuth2服务器地址
- **ZO_OAUTH2_ALLOWED_ROLES**: 控制允许访问的角色，默认设置为"ROLE_ADMIN"

## 使用方法

### 1. CAS回调登录（推荐）
- 用户通过CAS系统重定向到OpenObserve
- 系统自动处理OAuth2认证流程
- 无需手动输入任何凭据

### 2. 配置说明
- 确保 `ZO_OAUTH2_USERINFO_URL` 指向正确的OAuth2用户信息接口
- 该接口应返回包含用户信息的JSON响应
- 通过环境变量 `ZO_OAUTH2_ALLOWED_ROLES` 控制允许的角色




