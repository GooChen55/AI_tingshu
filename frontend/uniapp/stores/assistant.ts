import { defineStore } from 'pinia'
import { reactive, watch } from 'vue'
import { useUserStore } from './user'
import { assistantChat } from '../api/assistant'

export const useAssistantStore = defineStore('listening-assistant', () => {
  const state = reactiveState()
  const user = useUserStore()
  let generation = 0
  watch(() => user.token, () => { generation++; reset() }, { flush: 'sync' })
  function reset() {
    state.messages = []
    state.sessionId = null
    state.draft = ''
    state.busy = false
    state.error = ''
  }
  async function send(prompt?: string) {
    const text = (prompt ?? state.draft).trim()
    if (!text || state.busy) return
    if (!user.token) { state.error = '登录听书账号后，即可开始对话。'; return }
    const current = generation
    state.draft = ''; state.error = ''; state.busy = true
    state.messages.push({ role: 'user', text })
    try {
      const result = await assistantChat(text, state.sessionId)
      if (generation !== current) return
      state.sessionId = result.session_id
      state.messages.push({ role: 'assistant', text: result.text, sources: result.sources || [] })
    } catch (error: any) {
      if (generation === current) { state.error = error.message || '请求失败，请稍后重试'; state.draft = text }
    } finally { if (generation === current) state.busy = false }
  }
  function newConversation() { if (!state.busy) { generation++; reset() } }
  return { state, send, newConversation }
})

function reactiveState() {
  return reactive({ open: false, full: false, draft: '', busy: false, error: '', sessionId: null as string | null, messages: [] as any[] })
}

export function openAssistant(full = false) {
  // #ifdef H5
  const assistant = useAssistantStore()
  assistant.state.open = true
  assistant.state.full = full
  return
  // #endif
  // #ifndef H5
  uni.navigateTo({ url: '/pages/assistant/assistant' })
  // #endif
}
