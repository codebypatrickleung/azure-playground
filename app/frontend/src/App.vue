<template>
  <div class="container">
    <h1 class="title">Azure Playground</h1>
    <form @submit.prevent="submitText" class="text-form">
      <textarea
        v-model="inputText"
        placeholder="Ask me a question"
        rows="8"
        required
      ></textarea>
      <button type="submit" :disabled="!inputText || loading">Process</button>
    </form>
    <div v-if="loading" class="loading">Processing...</div>
    <div v-if="error" class="error">{{ error }}</div>
    <div v-if="result" class="result">
      <h2>Processed Output</h2>
      <pre>{{ result }}</pre>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'

const inputText = ref('')
const result = ref('')
const error = ref('')
const loading = ref(false)
const LLM_SERVICE_URL = import.meta.env.VITE_LLM_SERVICE_URL || '/api'

async function submitText() {
  error.value = ''
  result.value = ''
  loading.value = true
  try {
    const response = await fetch(`${LLM_SERVICE_URL}/process-text`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: inputText.value }),
    })
    if (!response.ok) {
      let errMsg = `Failed to process text (status ${response.status})`
      try {
        const data = await response.json()
        if (data && data.error) {
          errMsg += `: ${data.error}`
        } else if (data && data.message) {
          errMsg += `: ${data.message}`
        }
      } catch {
        // ignore JSON parse errors
      }
      throw new Error(errMsg)
    }
    const data = await response.json()
    result.value = typeof data === 'string' ? data : JSON.stringify(data, null, 2)
  } catch (err) {
    error.value = err?.message || 'Unknown error'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.container {
  max-width: 600px;
  margin: 3rem auto;
  padding: 2rem;
  background: #fff;
  border-radius: 12px;
  box-shadow: 0 2px 16px rgba(0,0,0,0.08);
}
.title {
  text-align: center;
  color: #1976d2;
  margin-bottom: 2rem;
}
.text-form {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  margin-bottom: 2rem;
}
textarea {
  resize: vertical;
  padding: 1rem;
  font-size: 1rem;
  border-radius: 4px;
  border: 1px solid #b0bec5;
  min-height: 120px;
}
button {
  background: #1976d2;
  color: #fff;
  border: none;
  padding: 0.6rem 1.4rem;
  border-radius: 4px;
  font-size: 1rem;
  cursor: pointer;
  transition: background 0.2s;
  align-self: flex-end;
}
button:disabled {
  background: #b0bec5;
  cursor: not-allowed;
}
.loading {
  color: #1976d2;
  text-align: center;
  margin: 1rem 0;
}
.error {
  color: #d32f2f;
  text-align: center;
  margin: 1rem 0;
}
.result {
  margin-top: 2rem;
  background: #f4f4f4;
  padding: 1rem;
  border-radius: 6px;
}
pre {
  white-space: pre-wrap;
  word-break: break-all;
  font-size: 1rem;
  color: #333;
}
</style>