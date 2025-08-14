// Copyright 2023 OpenObserve Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

/* eslint-disable @typescript-eslint/no-explicit-any */
import http from "./http";

const auth = {
  // 替换原有的用户名密码登录为OAuth2登录
  sign_in_user: (payload: { token: string }) => {
    return http().post(`/auth/oauth2-login`, payload);
  },

  // 添加OAuth2登录方法
  oauth2_login: () => {
    return http().post(`/auth/oauth2-login`);
  },

  // 带token的OAuth2登录方法
  oauth2_login_with_token: (token: string) => {
    return http().post(`/auth/oauth2-login?access_token=${token}`);
  },

  // CAS token验证方法
  validateCasToken: (callback: string) => {
    return http().get(`/backstage/cas-proxy/app/validate_full?callback=${callback}`);
  },

  // 通过token获取用户信息
  get_user_by_token: (token: string) => {
    return http().get(`/auth/userinfo?access_token=${token}`);
  },

  // 其他方法保持不变
  get_dex_login: async () => {
    const res = await http().get("/config/dex_login");
    return res.data;
  },
  
  refresh_token: async () => {
    const res = await http().get("/config/dex_refresh");
    return res.data;
  }
};

export default auth;
