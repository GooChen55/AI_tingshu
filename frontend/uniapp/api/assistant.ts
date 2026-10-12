import { useUserStore } from "../stores/user"

// H5 联调端口；真机运行需改为开发机局域网地址并配置小程序合法域名。
export const ASSISTANT_BASE_URL = "http://127.0.0.1:18083"

export function assistantChat(text: string, sessionId: string | null): Promise<any> {
  return new Promise((resolve, reject) => {
    uni.request({
      url: ASSISTANT_BASE_URL + "/api/assistant/chat",
      method: "POST",
      header: { token: useUserStore().token || "", "Content-Type": "application/json" },
      data: { text, session_id: sessionId },
      timeout: 120000,
      success: res => {
        const body = res.data as any
        if (res.statusCode >= 200 && res.statusCode < 300) resolve(body)
        else reject(new Error(body.detail || "助手暂时不可用"))
      },
      fail: () => reject(new Error("无法连接助手，请检查服务地址"))
    })
  })
}
