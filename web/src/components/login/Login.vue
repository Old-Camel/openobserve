<!-- Copyright 2023 OpenObserve Inc.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
-->

<template>
  <div class="login-container">
    <!-- 不显示任何内容，直接进行后台登录 -->
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import authService from '@/services/auth'
import { useAuthStore } from '@/stores/auth'
import {Notify} from 'quasar'

const router = useRouter()
const authStore = useAuthStore()
const retryCount = ref(0)
const maxRetries = 3

const showError = (message: string) => {
  Notify.create({
    message: message,
    color: 'negative',
    position: 'top',
    timeout: 5000,
    actions: [
      {
        label: '关闭',
        color: 'white',
        handler: () => {}
      }
    ]
  })
}

const autoLogin = async () => {
  // 检查重试次数
  if (retryCount.value >= maxRetries) {
    showError('认证失败次数过多，请检查网络连接或联系管理员');
    return;
  }

  try {
    // 调用CAS验证接口
    const currentUrl = encodeURIComponent(window.location.href);
    const response = await authService.validateCasToken(currentUrl);
    
    if (response.errcode === 2001) {
      // 需要回跳，清除本地存储并跳转
      console.log('Need to redirect to CAS login');
      localStorage.removeItem('oauth2_token');
      sessionStorage.clear();
      window.open(response.msg, '_self');
      return;
    } 
    // 登录成功
    else if (response.errcode === 2000) {
      console.log('CAS validation successful');
      // 重置重试计数
      retryCount.value = 0;
      // 获取token并存储
      localStorage.setItem('oauth2_token', JSON.stringify(response.data));
      
      // 使用获取到的token进行OAuth2登录
      try {
        const oauth2Response = await authService.oauth2_login_with_token(response.data.access_token || response.data.token);
        if (oauth2Response.success) {
          authStore.setUser(oauth2Response.data);
          router.push('/');
        } else {
          console.error('OAuth2 login failed:', oauth2Response.message);
          // 检查是否是权限不足的错误
          if (oauth2Response.message && oauth2Response.message.includes('没有访问权限')) {
            showError('没有访问权限');
            return; // 权限不足不重试
          } else {
            showError('登录失败，请稍后重试');
          }
          // 清除无效的token
          localStorage.removeItem('oauth2_token');
          // 增加重试计数并重试
          retryCount.value++;
          setTimeout(() => {
            autoLogin();
          }, 3000);
        }
      } catch (error: any) {
        console.error('OAuth2 login error:', error);
        // 检查是否是403权限不足错误
        if (error.response && error.response.status === 403) {
          showError('没有访问权限');
          return; // 权限不足不重试
        } else {
          showError('登录失败，请稍后重试');
        }
        localStorage.removeItem('oauth2_token');
        // 增加重试计数并重试
        retryCount.value++;
        setTimeout(() => {
          autoLogin();
        }, 3000);
      }
    } else {
      // 认证出错
      console.error('CAS validation failed:', response.msg);
      localStorage.removeItem('oauth2_token');
      sessionStorage.clear();
      showError('用户认证出错! 请稍后重试');
      // 增加重试计数并重试
      retryCount.value++;
      setTimeout(() => {
        autoLogin();
      }, 3000);
    }
  } catch (error) {
    console.error('CAS validation error:', error);
    localStorage.removeItem('oauth2_token');
    sessionStorage.clear();
    showError('认证服务连接失败，请稍后重试');
    // 增加重试计数并重试
    retryCount.value++;
    setTimeout(() => {
      autoLogin();
    }, 3000);
  }
}

onMounted(() => {
  // 页面加载完成后自动开始认证
  autoLogin()
})
</script>

<style lang="scss">
.login-container {
  display: none; /* 隐藏整个登录容器 */
}
</style>

<style lang="scss">
.login-inputs {
  .q-field__label {
    font-weight: normal !important;
    font-size: 12px;
    transform: translate(-0.75rem, -155%);
    color: #3a3a3a;
  }
}
</style>
