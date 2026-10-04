import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// base: './' にしておくと GitHub Pages などのサブパスにそのまま置ける
export default defineConfig({
  base: './',
  plugins: [react(), tailwindcss()],
})
