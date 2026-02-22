// @ts-check
import { defineConfig } from 'astro/config';

import tailwindcss from '@tailwindcss/vite';

// https://astro.build/config
export default defineConfig({
  site: 'https://mydia.dev',
  vite: {
    plugins: [tailwindcss()],
    server: {
      allowedHosts: ['.ts.net']
    }
  }
});
