// vite.config.ts
import { defineConfig } from 'vite'
import path from 'path'

export default defineConfig(async ({ command }) => {
  const plugins = []
  if (command !== 'build') {
    try {
      const basicSsl = (await import('@vitejs/plugin-basic-ssl')).default
      plugins.push(basicSsl())
    } catch {
      // Dev/preview will run without HTTPS if the plugin isn't installed
    }
  }

  return {
    root: 'src/client',
    server: {
      host: '127.0.0.1',
      https: true,
      headers: {
        'Cross-Origin-Opener-Policy': 'same-origin',
        'Cross-Origin-Embedder-Policy': 'require-corp',
        'Cross-Origin-Resource-Policy': 'same-origin',
      },
    },
    preview: {
      https: true,
      headers: {
        'Cross-Origin-Opener-Policy': 'same-origin',
        'Cross-Origin-Embedder-Policy': 'require-corp',
        'Cross-Origin-Resource-Policy': 'same-origin',
      },
    },
    plugins,
    build: {
      rollupOptions: {
        input: { main: path.resolve(__dirname, 'src/client/index.html') },
      },
    },
  }
})
