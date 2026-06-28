import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    environment: 'node',
    env: {
      AI_ENGINE_URL: 'http://ai-engine:3003',
      AI_SERVICE_TOKEN: 'test-token-secret',
    },
  },
})
