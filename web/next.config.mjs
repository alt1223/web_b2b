/** @type {import('next').NextConfig} */

const nextConfig = {
    basePath: '', // 设置统一前缀如/en
    assetPrefix: '', // 静态资源前缀
    reactStrictMode: false,
    eslint: {
        ignoreDuringBuilds: true, // build时跳过eslint
    },
    env: {
        NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME: "da9h8exvs",
        NEXT_PUBLIC_CLOUDINARY_PRESET_NAME: "fi0lxkc1",
    },
    images: {
        domains: [process.env.NEXT_PUBLIC_HOST],
    },
    swcMinify: true,
    compiler: {
        removeConsole: process.env.NODE_ENV === 'production',
    },
    headers: async () => [
        {
            source: '/:path*',
            headers: [
                {
                    key: 'X-DNS-Prefetch-Control',
                    value: 'on'
                },
                {
                    key: 'Strict-Transport-Security',
                    value: 'max-age=63072000; includeSubDomains; preload'
                },
                {
                    key: 'X-XSS-Protection',
                    value: '1; mode=block'
                },
                {
                    key: 'X-Frame-Options',
                    value: 'SAMEORIGIN'
                },
                {
                    key: 'X-Content-Type-Options',
                    value: 'nosniff'
                }
            ]
        }
    ],
    poweredByHeader: false,
    compress: true,
    async rewrites() {
        return [
            { source: '/myapp/:path*', destination: 'http://127.0.0.1:8000/myapp/:path*' },
            { source: '/upload/:path*', destination: 'http://127.0.0.1:8000/upload/:path*' },
        ];
    },
};

export default nextConfig;
