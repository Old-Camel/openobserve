// 轻量封装，兼容 Login.vue 中的 useAuthStore 调用
// 实际委托给 Vuex store（web/src/stores/index.ts）

import store from './index';

type UserInfo = Record<string, any>;

export function useAuthStore() {
    return {
        setUser(user: UserInfo) {
            try {
                // 设置用户信息并标记为已登录
                store.commit('setUserInfo', user);
                store.commit('login', { loginState: true, userInfo: user });
            } catch (e) {
                // 兜底：仅设置用户信息
                store.commit('setUserInfo', user);
            }
        },
    };
}


