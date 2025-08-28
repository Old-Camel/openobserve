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
import { useStore } from "vuex";

import { useRouter } from 'vue-router'
import authService from '@/services/auth'
import { useAuthStore } from '@/stores/auth'
import {Notify} from 'quasar'
import {
  getBasicAuth,
  b64EncodeStandard,
  useLocalUserInfo,
  useLocalCurrentUser,
  useLocalOrganization,
  getImageURL,
} from "@/utils/zincutils";
import { redirectUser } from "@/utils/common";
import organizationsService from '@/services/organizations'
import { openobserveRum } from "@openobserve/browser-rum";

const router = useRouter()
const authStore = useAuthStore()
const retryCount = ref(0)
const maxRetries = 3
const selectedOrg = ref({})
const orgOptions = ref([])
const store = useStore();
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
    const resp = await authService.validateCasToken(currentUrl);
    let response = resp.data;
    
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
        if (oauth2Response.data.status) {
          // ✅ 1. 构造完整的用户信息
          const userInfo = {
            given_name: oauth2Response.data.user.first_name || oauth2Response.data.user.email,
            name: oauth2Response.data.user.first_name || oauth2Response.data.user.email,
            email: oauth2Response.data.user.email,
            role: oauth2Response.data.user.role,
            auth_time: Math.floor(Date.now() / 1000),
            exp: Math.floor((new Date().getTime() + 1000 * 60 * 60 * 24 * 30) / 1000),
            family_name: oauth2Response.data.user.last_name || "",
          };
          
          // ✅ 2. 编码并存储到localStorage & store
          const encodedUserInfo = b64EncodeStandard(JSON.stringify(userInfo));
          useLocalUserInfo(encodedUserInfo);
          store.dispatch("setUserInfo", encodedUserInfo);

          useLocalCurrentUser(JSON.stringify(userInfo));
          store.dispatch("setCurrentUser", userInfo);

          // ✅ 3. 设置RUM用户（如果有）
          if(store.state.zoConfig?.rum?.enabled) {
            openobserveRum.setUser({
              name: userInfo.given_name + " " + userInfo.family_name,
              email: userInfo.email,
            });
          }

          // ✅ 4. 检查重定向URI
          const redirectURI = window.sessionStorage.getItem("redirectURI");
          window.sessionStorage.removeItem("redirectURI");

          // ✅ 5. 检查组织信息存储的localStorage中的邮箱
          // 如果邮箱不同，清除组织信息
          const localOrg: any = useLocalOrganization();
          let tempDefaultOrg = {};
          let localOrgFlag = false;
          if (
            Object.keys(localOrg.value).length > 0 &&
            localOrg.value != null &&
            localOrg.value.user_email !== userInfo.email
          ) {
            localOrg.value = null;
            useLocalOrganization("");
          }

          // 如果组织信息在localStorage中不可用，从后端获取所有组织
          // 并设置第一个组织为选中的组织
          if (localOrg.value) {
            selectedOrg.value = localOrg.value;
            useLocalOrganization(selectedOrg.value);
            store.dispatch("setSelectedOrganization", selectedOrg.value);
          } else {
            await organizationsService
              .os_list(0, 100000, "id", false, "", "default")
              .then((res: any) => {
                orgOptions.value = res.data.data.map(
                  (data: {
                    id: any;
                    name: any;
                    type: any;
                    identifier: any;
                    UserObj: any;
                    ingest_threshold: any;
                    search_threshold: any;
                    CustomerBillingObj: any;
                    status: any;
                  }) => {
                    let optiondata: any = {
                      label: data.name,
                      id: data.id,
                      identifier: data.identifier,
                      user_email: store.state.userInfo.email,
                      ingest_threshold: data.ingest_threshold,
                      search_threshold: data.search_threshold,
                      subscription_type: data.hasOwnProperty(
                        "CustomerBillingObj",
                      )
                        ? data.CustomerBillingObj.subscription_type
                        : "",
                      status: data.status,
                      note: data.hasOwnProperty("CustomerBillingObj")
                        ? data.CustomerBillingObj.note
                        : "",
                    };

                    if (
                      (Object.keys(selectedOrg.value).length == 0 &&
                        (data.type == "default" || data.id == "1") &&
                        store.state.userInfo.email ==
                          data.UserObj.email) ||
                      res.data.data.length == 1
                    ) {
                      localOrgFlag = true;
                      selectedOrg.value = localOrg.value
                        ? localOrg.value
                        : optiondata;
                      useLocalOrganization(selectedOrg.value);
                      store.dispatch(
                        "setSelectedOrganization",
                        selectedOrg.value,
                      );
                    }

                    if (data.type == "default") {
                      tempDefaultOrg = optiondata;
                    }

                    return optiondata;
                  },
                );

                if (localOrgFlag == false) {
                  selectedOrg.value = tempDefaultOrg;
                  useLocalOrganization(tempDefaultOrg);
                  store.dispatch(
                    "setSelectedOrganization",
                    tempDefaultOrg,
                  );
                }
              });
          }

          // ✅ 6. 重定向用户
          redirectUser(redirectURI);
          
          return; // ✅ 成功后直接返回，避免重试循环
        } else {
          console.error('OAuth2 login failed:', oauth2Response.message);
          
          // 清除无效的token
          localStorage.removeItem('oauth2_token');
          
          // 检查是否是权限不足的错误
          if (oauth2Response.data.message && oauth2Response.data.message.includes('没有访问权限')) {
            showError('没有访问权限');
            return; // 权限不足不重试
          } else {
            showError('登录失败，请稍后重试');
            return; // 其他失败也不重试
          }
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
