/**
 * 博查 AI Web Search 搜索 Provider
 * 基于博查 AI Web Search API，国内直连、免费、无需服务器，
 * 仅测试用，后续改为可替换其他 API
 * 阶段五：服务层接口抽象 — 实现 SearchProvider 接口
 *
 * 使用前提：open.bochaai.com 注册获取 Key，填入 AppConfig.searchApiKey
 * 返回结构：标题/链接/长摘要（summary），更适合 LLM 直接使用
 *
 * 与 LLM 解耦：换任何 LLM 都不影响此服务
 */

import { http } from "@kit.NetworkKit";
import { AppConfig } from "../../config/AppConfig";
import { SearchProvider } from "./SearchProvider";

// 搜索结果条目
interface BochaResult {
  name: string;
  url: string;
  snippet: string;
  summary: string;
}

// 网页结果列表
interface BochaWebPages {
  value: BochaResult[];
}

// 响应 data 字段
interface BochaData {
  webPages: BochaWebPages;
}

// 响应体（兼容 data 包裹与顶层 webPages 两种结构）
interface BochaResponse {
  code?: number | string;
  message?: string;
  data?: BochaData;
  webPages?: BochaWebPages;
}

// 请求头
interface SearchHeader {
  "Content-Type": string;
  Authorization: string;
}

// 请求体
interface SearchBody {
  query: string;
  summary: boolean;
  count: number;
}

export class BochaSearchProvider implements SearchProvider {
  private static instance: BochaSearchProvider;

  private constructor() {}

  static getInstance(): BochaSearchProvider {
    if (!BochaSearchProvider.instance) {
      BochaSearchProvider.instance = new BochaSearchProvider();
    }
    return BochaSearchProvider.instance;
  }

  /**
   * 搜索渠道是否已配置（URL 和 Key 都非空）
   * 配置不齐时不显示"正在搜索"，直接走普通对话
   */
  isAvailable(): boolean {
    const url = AppConfig.getInstance().getSearchBaseUrl();
    const key = AppConfig.getInstance().getSearchApiKey();
    return url.length > 0 && key.length > 0;
  }

  /**
   * 执行联网搜索（博查）
   * @param query 搜索关键词（通常取用户最新一条消息）
   * @returns 搜索结果的 Markdown 摘要；失败返回空串
   */
  async search(query: string): Promise<string> {
    const httpRequest = http.createHttp();
    try {
      const searchBaseUrl = AppConfig.getInstance().getSearchBaseUrl();
      if (searchBaseUrl.length === 0) {
        return ""; // 未配置地址
      }
      const searchKey = AppConfig.getInstance().getSearchApiKey();
      if (searchKey.length === 0) {
        return ""; // 未配置 Key
      }

      const header: SearchHeader = {
        "Content-Type": "application/json",
        Authorization: `Bearer ${searchKey}`,
      };

      const body: SearchBody = {
        query: query,
        summary: true, // 返回长摘要，更适合 LLM
        count: 5, // 返回 5 条结果
      };

      const resp = await httpRequest.request(searchBaseUrl, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.STRING,
      });

      if (resp.responseCode >= 400) {
        return ""; // HTTP 层失败，静默降级
      }

      const jsonStr = (resp.result as string) || "";
      if (jsonStr.length === 0) {
        return "";
      }

      const parsed = JSON.parse(jsonStr) as BochaResponse;
      // 业务错误码校验（HTTP 200 时 body.code 也可能非 200）
      if (parsed.code !== undefined && parsed.code !== 200) {
        return "";
      }

      // 兼容两种返回结构：data.webPages 或顶层 webPages
      const pages = parsed.data?.webPages ?? parsed.webPages;
      if (!pages || pages.value.length === 0) {
        return "";
      }

      // 拼接为 LLM 友好的 Markdown（每条摘要截断，控制 token）
      let markdown = `针对「${query}」的搜索结果：\n\n`;
      const maxResults = pages.value.length > 5 ? 5 : pages.value.length;
      for (let i = 0; i < maxResults; i++) {
        const item = pages.value[i];
        markdown += `### ${i + 1}. ${item.name}\n`;
        markdown += `来源: ${item.url}\n`;
        // 优先长摘要，缺省时用短摘要
        const content = item.summary.length > 0 ? item.summary : item.snippet;
        const clipped = content.length > 800 ? content.substring(0, 800) : content;
        markdown += `${clipped}\n\n`;
      }
      return markdown;
    } catch (e) {
      return ""; // 异常时静默降级为普通对话
    } finally {
      httpRequest.destroy();
    }
  }
}
