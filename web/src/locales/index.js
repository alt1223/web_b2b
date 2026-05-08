import zh from './zh';
import en from './en';

const dicts = { en, zh };
export const SUPPORTED = ['en', 'zh'];
export const DEFAULT_LANG = 'en';
export const LANG_COOKIE = 'lang';

// 读取当前语言代码
function resolveLangCode() {
    if (typeof document !== 'undefined') {
        // 客户端：从 cookie 读取
        const m = document.cookie.match(/(?:^|;\s*)lang=([^;]+)/);
        const v = m && decodeURIComponent(m[1]);
        return SUPPORTED.includes(v) ? v : DEFAULT_LANG;
    }
    // 服务端：从 next/headers cookies 读取（仅在请求渲染上下文中可用）
    try {
        // 动态 require 避免在客户端打包时报错
        const { cookies } = require('next/headers');
        const v = cookies().get(LANG_COOKIE)?.value;
        return SUPPORTED.includes(v) ? v : DEFAULT_LANG;
    } catch (e) {
        return DEFAULT_LANG;
    }
}

// 通过 Proxy 在每次属性访问时动态返回当前语言对应的文案
const lang = new Proxy({}, {
    get(_t, key) {
        if (key === Symbol.toPrimitive || key === 'toString') return () => '';
        const code = resolveLangCode();
        const dict = dicts[code] || dicts[DEFAULT_LANG];
        if (key in dict) return dict[key];
        // 兜底用英文
        return dicts[DEFAULT_LANG][key] ?? '';
    },
    has(_t, key) {
        const code = resolveLangCode();
        return key in (dicts[code] || dicts[DEFAULT_LANG]);
    },
    ownKeys() {
        return Reflect.ownKeys(dicts[DEFAULT_LANG]);
    },
    getOwnPropertyDescriptor(_t, key) {
        return { enumerable: true, configurable: true, value: this.get(_t, key) };
    }
});

export default lang;
