use crate::{
    service::db,
    common::utils::auth::get_hash,
};
use config::{
    get_config,
    meta::user::{DBUser, User, UserOrg, UserRole},
    utils::rand::generate_random_string,
};
use anyhow::Result;
use log;

// 根据OAuth2用户信息自动创建或更新用户
pub async fn create_or_update_oauth2_user(oauth2_user: &crate::handler::http::auth::validator::OAuth2User) -> Result<User> {
    // 生成email: account@tenantId.com (添加.com后缀)
    let email = format!("{}@{}.com", oauth2_user.account, oauth2_user.tenant_id);
    
    // 使用default组织
    let org_id = "default";
    
    // 检查用户是否已存在：将“未找到”视为 None，其他错误才中断
    let existing_user = match db::user::get(Some(org_id), &email).await {
        Ok(u) => u,
        Err(e) => {
            if is_not_found_error(&e) { None } else { return Err(e); }
        }
    };
    
    let user = if let Some(existing) = existing_user {
        // 用户已存在，更新信息
        log::info!("更新现有OAuth2用户: {}", email);
        update_existing_user(existing, oauth2_user).await?
    } else {
        // 用户不存在，创建新用户
        log::info!("创建新OAuth2用户: {}", email);
        create_new_user(oauth2_user).await?
    };
    
    Ok(user)
}

// 更新现有用户信息
async fn update_existing_user(mut existing_user: User, oauth2_user: &crate::handler::http::auth::validator::OAuth2User) -> Result<User> {
    // 更新用户信息
    existing_user.first_name = oauth2_user.realname.clone();
    existing_user.last_name = "".to_string(); // 可以根据需要设置
    existing_user.org = "default".to_string(); // 使用default组织
    
    // 更新到数据库 - 修复：使用正确的函数签名
    db::user::update(
        &existing_user.email,
        &existing_user.first_name,
        &existing_user.last_name,
        &existing_user.password,
        existing_user.password_ext.clone(),
    ).await?;
    
    // 更新组织用户信息
    db::org_users::update(
        "default",
        &existing_user.email,
        existing_user.role.clone(),
        &existing_user.token,
        existing_user.rum_token.clone(),
    ).await?;
    
    Ok(existing_user)
}

// 创建新用户
async fn create_new_user(oauth2_user: &crate::handler::http::auth::validator::OAuth2User) -> Result<User> {
    let email = format!("{}@{}.com", oauth2_user.account, oauth2_user.tenant_id);
    
    // 使用固定密码（OAuth2用户不需要随机密码）
    let password = "oldcamel".to_string();
    let salt = generate_fixed_salt();
    let hashed_password = get_hash(&password, &salt);
    
    // 生成token，使用配置中的固定rum_token
    let token = generate_random_string(16);
    let cfg = get_config();
    let rum_token = if !cfg.auth.fixed_rum_token.is_empty() {
        cfg.auth.fixed_rum_token.clone()
    } else {
        format!("rum{}", generate_random_string(16))
    };
    
    // 创建DBUser结构体，使用default组织
    let db_user = DBUser {
        email: email.clone(),
        first_name: oauth2_user.realname.clone(),
        last_name: "".to_string(),
        password: hashed_password.clone(),
        salt: salt.clone(),
        organizations: vec![UserOrg {
            name: "default".to_string(),
            token: token.clone(),
            rum_token: Some(rum_token.clone()),
            role: UserRole::Admin,
        }],
        is_external: true,
        password_ext: None,
    };
    
    // 保存到数据库
    db::user::add(&db_user).await?;
    
    // 返回User结构体
    let new_user = User {
        email: email.clone(),
        first_name: oauth2_user.realname.clone(),
        last_name: "".to_string(),
        password: hashed_password,
        role: UserRole::Root, // 设置为root角色
        org: "default".to_string(), // 使用default组织
        token,
        rum_token: Some(rum_token),
        salt,
        is_external: true, // 标记为外部用户
        password_ext: None, // 修复：password_ext应该是Option<String>类型
    };
    
    log::info!("成功创建OAuth2用户: {}", email);
    
    Ok(new_user)
}

// 生成固定盐值
fn generate_fixed_salt() -> String {
    "fixed_salt_for_oauth2_users".to_string()
}

// 将底层“未找到”错误统一识别为 not found，用于上层转 None
fn is_not_found_error(e: &anyhow::Error) -> bool {
    // 1) SeaORM 语义错误：RecordNotFound
    if let Some(db_err) = e.downcast_ref::<sea_orm::DbErr>() {
        if matches!(db_err, sea_orm::DbErr::RecordNotFound(_)) {
            return true;
        }
    }
    // 2) 字符串兜底匹配（兼容不同封装层）
    let s = format!("{e:#}");
    s.contains("Organization user not found")
        || s.contains("RecordNotFound")
        || s.contains("not found")
}

// 清理残留的OAuth2用户记录
pub async fn cleanup_oauth2_user(email: &str) -> Result<(), anyhow::Error> {
    log::info!("清理OAuth2用户记录: {}", email);
    
    // 删除 org_users 表中的记录
    match db::org_users::remove_by_user(email).await {
        Ok(_) => log::info!("成功删除 org_users 表中的记录"),
        Err(e) => log::warn!("删除 org_users 记录时出错: {}", e),
    }
    
    // 删除 users 表中的记录
    match db::user::delete(email).await {
        Ok(_) => log::info!("成功删除 users 表中的记录"),
        Err(e) => log::warn!("删除 users 记录时出错: {}", e),
    }
    
    Ok(())
}

// 检查并清理OAuth2用户冲突
pub async fn check_and_cleanup_oauth2_user(email: &str) -> Result<(), anyhow::Error> {
    // 检查用户是否存在
    match db::user::get_db_user(email).await {
        Ok(_) => {
            log::warn!("发现已存在的OAuth2用户: {}，正在清理...", email);
            cleanup_oauth2_user(email).await?;
        }
        Err(_) => {
            log::info!("OAuth2用户不存在: {}", email);
        }
    }
    
    Ok(())
}
