/**
 * OOXML 文本提取器（docx / pptx / xlsx）—— 阶段3b
 *
 * 三个格式均为 ZIP 包 + OOXML XML 结构，共用一套基础设施：
 *  1. @ohos/jszip：解析 ZIP，按路径读取目标 entry 的二进制内容（阶段3a 已验证）
 *  2. @ohos.xml XmlPullParser：流式解析 XML（标签事件 + 属性回调）
 *
 * 输出统一为 Markdown 文本（走 input_text 文本通道，所有模型可用）：
 *  - docx：段落 / 标题（HeadingN → #）/ 表格（| 单元格 |）
 *  - pptx：每页 `## 第 N 页` + 段落文本
 *  - xlsx：每个工作表 Markdown 表格（sharedStrings 还原共享字符串）
 *
 * 说明：
 *  - OOXML 标签/属性带命名空间前缀（w:、a:、p: 等），本实现统一按 localName 匹配，
 *    不依赖前缀；解析前剥离前缀与 xmlns 声明（stripNamespaces），避免 XmlPullParser
 *    对未声明前缀抛 "Undefined Prefix" 错误。
 *  - 旧格式 .doc/.ppt/.xls（OLE 二进制）无法用 ZIP 解压，不支持（已在文件选择器过滤）。
 */

import JSZip from "@ohos/jszip";
import { util, xml } from "@kit.ArkTS";

/* XML 标签事件回调（流式）：attrs 为 END_TAG 时该标签已闭合的属性集合 */
class XmlTagVisitor {
  onStart: (name: string) => void;
  onText: (text: string) => void;
  onEnd: (name: string, attrs: Map<string, string>) => void;

  constructor(onStart: (name: string) => void, onText: (text: string) => void, onEnd: (name: string, attrs: Map<string, string>) => void) {
    this.onStart = onStart;
    this.onText = onText;
    this.onEnd = onEnd;
  }
}

/* 工作表引用（xlsx）：名称 + rId（经 workbook.xml.rels 映射到实际文件路径） */
interface SheetRef {
  name: string;
  rId: string;
}

export class OoxmlParser {
  /* ============================== 对外入口 ============================== */

  /** docx → Markdown（段落/标题/表格） */
  static async parseDocx(buffer: ArrayBuffer): Promise<string> {
    const zip = await JSZip.loadAsync(buffer);
    const docBuf = await OoxmlParser.readEntry(zip, "word/document.xml");
    if (docBuf === null) {
      return "（未找到 docx 正文 word/document.xml）";
    }
    return OoxmlParser.extractDocx(docBuf);
  }

  /** pptx → Markdown（每页 ## 标题 + 段落文本） */
  static async parsePptx(buffer: ArrayBuffer): Promise<string> {
    const zip = await JSZip.loadAsync(buffer);
    /* 收集幻灯片路径并按编号排序，保证页面顺序 */
    const slidePaths: string[] = [];
    zip.forEach((path: string, entry: JSZip.JSZipObject) => {
      if (path.startsWith("ppt/slides/slide") && path.endsWith(".xml")) {
        slidePaths.push(path);
      }
    });
    slidePaths.sort((a: string, b: string) => OoxmlParser.slideNum(a) - OoxmlParser.slideNum(b));
    if (slidePaths.length === 0) {
      return "（未找到 pptx 幻灯片）";
    }
    const parts: string[] = [];
    for (let i = 0; i < slidePaths.length; i++) {
      const slideBuf = await OoxmlParser.readEntry(zip, slidePaths[i]);
      if (slideBuf === null) {
        continue;
      }
      const pageText: string = OoxmlParser.extractSlide(slideBuf);
      parts.push(`## 第 ${i + 1} 页\n\n${pageText}`.trim());
    }
    return parts.join("\n\n");
  }

  /** xlsx → Markdown（每个工作表一个表格） */
  static async parseXlsx(buffer: ArrayBuffer): Promise<string> {
    const zip = await JSZip.loadAsync(buffer);

    /* 1. 共享字符串表（单元格 t="s" 时值为其索引） */
    const sstBuf = await OoxmlParser.readEntry(zip, "xl/sharedStrings.xml");
    const shared: string[] = sstBuf !== null ? OoxmlParser.parseSharedStrings(sstBuf) : [];

    /* 2. 工作表清单（name + rId） */
    const wbBuf = await OoxmlParser.readEntry(zip, "xl/workbook.xml");
    const sheets: SheetRef[] = [];
    if (wbBuf !== null) {
      OoxmlParser.parseWorkbookSheets(wbBuf, sheets);
    }

    /* 3. rId → 工作表文件路径 映射 */
    const relsBuf = await OoxmlParser.readEntry(zip, "xl/_rels/workbook.xml.rels");
    const relMap: Map<string, string> = new Map();
    if (relsBuf !== null) {
      OoxmlParser.parseWorkbookRels(relsBuf, relMap);
    }

    /* 4. 逐工作表提取 Markdown 表格 */
    const parts: string[] = [];
    for (const s of sheets) {
      const target = relMap.get(s.rId);
      if (target === undefined) {
        continue;
      }
      const sheetPath: string = target.startsWith("xl/") ? target : `xl/${target}`;
      const sheetBuf = await OoxmlParser.readEntry(zip, sheetPath);
      if (sheetBuf === null) {
        continue;
      }
      const md: string = OoxmlParser.parseSheet(sheetBuf, shared);
      parts.push(`### 工作表：${s.name}\n\n${md}`.trim());
    }
    if (parts.length === 0) {
      return "（未提取到工作表数据）";
    }
    return parts.join("\n\n");
  }

  /* ============================== ZIP 工具 ============================== */

  /** 读取 zip 内指定路径 entry 的二进制；不存在返回 null */
  private static async readEntry(zip: JSZip, path: string): Promise<ArrayBuffer | null> {
    const entry = zip.file(path);
    if (entry === null) {
      return null;
    }
    return await entry.async("arraybuffer");
  }

  /* ============================== XML 工具 ============================== */

  /**
   * 流式解析 XML：驱动 XmlPullParser，将标签事件与属性收集转成结构化回调。
   * 属性在 END_TAG 时随事件提供（该标签已闭合，属性齐全）。
   */
  private static parseXmlEvents(buffer: ArrayBuffer, visitor: XmlTagVisitor): void {
    /* 预处理：剥离命名空间前缀与 xmlns 声明。
     * OOXML 内存在未声明的前缀（如 r:id）时 XmlPullParser 会抛 "Undefined Prefix" 错误；
     * 本提取器按 localName 匹配标签/属性（见 tagName/attrLocal），剥离前缀后完全兼容。 */
    const decoder = util.TextDecoder.create("utf-8");
    const stripped: string = OoxmlParser.stripNamespaces(decoder.decodeToString(new Uint8Array(buffer)));
    const encoder = new util.TextEncoder();
    const u8: Uint8Array = encoder.encodeInto(stripped);
    const cleanBuf: ArrayBuffer = new ArrayBuffer(u8.byteLength);
    new Uint8Array(cleanBuf).set(u8);

    const parser = new xml.XmlPullParser(cleanBuf, "utf-8");
    const attrStack: Map<string, string>[] = [];
    parser.parseXml({
      supportDoctype: true,
      tokenValueCallbackFunction: (eventType: xml.EventType, info: xml.ParseInfo): boolean => {
        if (eventType === xml.EventType.START_TAG) {
          attrStack.push(new Map<string, string>());
          visitor.onStart(info.getName());
        } else if (eventType === xml.EventType.TEXT) {
          visitor.onText(info.getText());
        } else if (eventType === xml.EventType.END_TAG) {
          const attrs: Map<string, string> = attrStack.pop() as Map<string, string>;
          visitor.onEnd(info.getName(), attrs);
        }
        return true;
      },
      attributeWithTagCallbackFunction: (tagName: string, key: string, value: string): boolean => {
        const top = attrStack[attrStack.length - 1];
        if (top !== undefined) {
          top.set(key, value);
        }
        return true;
      },
    });
  }

  /**
   * 剥离 XML 文本中的命名空间前缀与 xmlns 声明。
   * 处理三类目标（不触碰文本节点/属性值，避免误伤内容）：
   *  1. xmlns:xxx="..." 与默认 xmlns="..." 声明 → 删除
   *  2. 标签名前缀：<w:p → <p；</w:p → </p
   *  3. 属性名前缀：r:id=" → id="
   */
  private static stripNamespaces(xmlText: string): string {
    let t: string = xmlText;
    /* 1. 删除命名空间声明（含默认命名空间 xmlns） */
    t = t.replace(/\sxmlns(?::[a-zA-Z0-9_]+)?="[^"]*"/g, "");
    /* 2. 标签名去前缀 */
    t = t.replace(/(<\/?)[a-zA-Z0-9_]+:/g, "$1");
    /* 3. 属性名去前缀（仅匹配属性赋值形式 name=，属性值不受影响） */
    t = t.replace(/\s[a-zA-Z0-9_]+:([a-zA-Z0-9_]+)=/g, " $1=");
    return t;
  }

  /** 提取标签 localName（兼容带/不带命名空间前缀） */
  private static tagName(name: string): string {
    const idx = name.lastIndexOf(':');
    return idx >= 0 ? name.substring(idx + 1) : name;
  }

  /** 按 localName 读属性（兼容属性名带前缀，如 w:val） */
  private static attrLocal(attrs: Map<string, string>, localName: string): string {
    let found: string = "";
    attrs.forEach((value: string, key: string) => {
      if (found === "") {
        const idx = key.lastIndexOf(':');
        const ln: string = idx >= 0 ? key.substring(idx + 1) : key;
        if (ln === localName) {
          found = value;
        }
      }
    });
    return found;
  }

  /* ============================== docx ============================== */

  /**
   * docx 正文提取：段落文本、标题（w:pStyle HeadingN → #）、表格（w:tbl）
   * 提取粒度以段落为单位，单元格内文本拼入表格单元格。
   */
  private static extractDocx(buffer: ArrayBuffer): string {
    const lines: string[] = [];
    let paraBuf: string[] = [];    // 当前段落文本片段
    let paraHeading: number = 0;   // 当前段落标题级别（0=正文）
    let inPara: boolean = false;
    let inPPr: boolean = false;    // 是否处于段落属性区（识别 pStyle 标题）
    let cellActive: boolean = false;
    let curRow: string[] = [];
    let curCell: string[] = [];
    const tableRows: string[][] = [];

    const visitor: XmlTagVisitor = new XmlTagVisitor(
      (name: string): void => {
        const n: string = OoxmlParser.tagName(name);
        if (n === "p") {
          inPara = true;
          paraBuf = [];
          paraHeading = 0;
        } else if (n === "pPr") {
          inPPr = true;
        } else if (n === "tbl") {
          tableRows.length = 0;
        } else if (n === "tr") {
          curRow = [];
        } else if (n === "tc") {
          curCell = [];
          cellActive = true;
        }
      },
      (text: string): void => {
        if (cellActive) {
          curCell.push(text);
        } else if (inPara) {
          paraBuf.push(text);
        }
      },
      (name: string, attrs: Map<string, string>): void => {
        const n: string = OoxmlParser.tagName(name);
        if (n === "pStyle" && inPPr) {
          paraHeading = OoxmlParser.headingLevel(OoxmlParser.attrLocal(attrs, "val"));
        } else if (n === "pPr") {
          inPPr = false;
        } else if (n === "tc") {
          curRow.push(curCell.join("").replace(/\s+/g, " ").trim());
          cellActive = false;
        } else if (n === "tr") {
          tableRows.push(curRow);
        } else if (n === "tbl") {
          const md: string = OoxmlParser.tableMarkdown(tableRows);
          if (md.length > 0) {
            lines.push(md);
          }
        } else if (n === "p" && inPara && !cellActive) {
          const text: string = paraBuf.join("").trim();
          if (text.length > 0) {
            lines.push(paraHeading > 0 ? `${"#".repeat(paraHeading)} ${text}` : text);
          }
          inPara = false;
        }
      },
    );
    OoxmlParser.parseXmlEvents(buffer, visitor);
    return lines.join("\n");
  }

  /** 解析段落样式值 → 标题级别（Heading1~9 / 1~9 / Title → 1；非标题返回 0） */
  private static headingLevel(styleVal: string): number {
    const s: string = styleVal.trim().toLowerCase();
    if (s === "title") {
      return 1;
    }
    const m1 = /^heading\s*([1-9])$/.exec(s);
    if (m1 !== null) {
      return Number(m1[1] as string);
    }
    const m2 = /^([1-9])$/.exec(s);
    if (m2 !== null) {
      return Number(m2[1] as string);
    }
    return 0;
  }

  /** 行数组 → Markdown 表格（首行作表头，空单元格补空串，0 列返回空串） */
  private static tableMarkdown(rows: string[][]): string {
    if (rows.length === 0) {
      return "";
    }
    let maxCols: number = 0;
    for (const r of rows) {
      if (r.length > maxCols) {
        maxCols = r.length;
      }
    }
    if (maxCols === 0) {
      return "";
    }
    const fmtRow = (r: string[]): string => {
      const cells: string[] = [];
      for (let i = 0; i < maxCols; i++) {
        cells.push(i < r.length ? r[i] : "");
      }
      return `| ${cells.join(" | ")} |`;
    };
    const out: string[] = [];
    out.push(fmtRow(rows[0]));
    const sep: string[] = [];
    for (let i = 0; i < maxCols; i++) {
      sep.push("---");
    }
    out.push(`| ${sep.join(" | ")} |`);
    for (let i = 1; i < rows.length; i++) {
      out.push(fmtRow(rows[i]));
    }
    return out.join("\n");
  }

  /* ============================== pptx ============================== */

  /** 解析 slide 路径中的页编号（ppt/slides/slide12.xml → 12） */
  private static slideNum(path: string): number {
    const m = /slide(\d+)\.xml$/.exec(path);
    return m !== null ? Number(m[1] as string) : 0;
  }

  /** 单页提取：收集段落（a:p）内文本（a:t），忽略形状/图片等非文本元素 */
  private static extractSlide(buffer: ArrayBuffer): string {
    const paraLines: string[] = [];
    let curPara: string[] = [];
    let inPara: boolean = false;

    const visitor: XmlTagVisitor = new XmlTagVisitor(
      (name: string): void => {
        if (OoxmlParser.tagName(name) === "p") {
          inPara = true;
          curPara = [];
        }
      },
      (text: string): void => {
        if (inPara) {
          curPara.push(text);
        }
      },
      (name: string, attrs: Map<string, string>): void => {
        if (OoxmlParser.tagName(name) === "p" && inPara) {
          const line: string = curPara.join("").trim();
          if (line.length > 0) {
            paraLines.push(line);
          }
          inPara = false;
        }
      },
    );
    OoxmlParser.parseXmlEvents(buffer, visitor);
    return paraLines.join("\n");
  }

  /* ============================== xlsx ============================== */

  /** sharedStrings.xml → 共享字符串数组（si 元素内所有 t 文本拼接） */
  private static parseSharedStrings(buffer: ArrayBuffer): string[] {
    const result: string[] = [];
    let inSi: boolean = false;
    let inT: boolean = false;
    let tBuf: string[] = [];

    const visitor: XmlTagVisitor = new XmlTagVisitor(
      (name: string): void => {
        const n: string = OoxmlParser.tagName(name);
        if (n === "si") {
          inSi = true;
          tBuf = [];
        } else if (n === "t" && inSi) {
          inT = true;
        }
      },
      (text: string): void => {
        if (inT) {
          tBuf.push(text);
        }
      },
      (name: string, attrs: Map<string, string>): void => {
        const n: string = OoxmlParser.tagName(name);
        if (n === "t" && inT) {
          inT = false;
        } else if (n === "si" && inSi) {
          result.push(tBuf.join(""));
          inSi = false;
        }
      },
    );
    OoxmlParser.parseXmlEvents(buffer, visitor);
    return result;
  }

  /** workbook.xml → 工作表清单（name + rId） */
  private static parseWorkbookSheets(buffer: ArrayBuffer, out: SheetRef[]): void {
    const visitor: XmlTagVisitor = new XmlTagVisitor(
      (name: string): void => {
      },
      (text: string): void => {
      },
      (name: string, attrs: Map<string, string>): void => {
        if (OoxmlParser.tagName(name) === "sheet") {
          const sheetName: string = OoxmlParser.attrLocal(attrs, "name");
          const rId: string = OoxmlParser.attrLocal(attrs, "id");
          if (sheetName.length > 0 && rId.startsWith("rId")) {
            out.push({ name: sheetName, rId: rId });
          }
        }
      },
    );
    OoxmlParser.parseXmlEvents(buffer, visitor);
  }

  /** workbook.xml.rels → rId → 工作表文件路径（仅 worksheet 类型） */
  private static parseWorkbookRels(buffer: ArrayBuffer, out: Map<string, string>): void {
    const visitor: XmlTagVisitor = new XmlTagVisitor(
      (name: string): void => {
      },
      (text: string): void => {
      },
      (name: string, attrs: Map<string, string>): void => {
        if (OoxmlParser.tagName(name) === "Relationship") {
          const id: string = OoxmlParser.attrLocal(attrs, "Id");
          const target: string = OoxmlParser.attrLocal(attrs, "Target");
          const type: string = OoxmlParser.attrLocal(attrs, "Type");
          if (id.startsWith("rId") && target.length > 0 && type.includes("worksheet")) {
            out.set(id, target);
          }
        }
      },
    );
    OoxmlParser.parseXmlEvents(buffer, visitor);
  }

  /**
   * sheetN.xml → Markdown 表格
   * 单元格：<c r="A1" t="s"><v>0</v></c>（t=s 时 v 为 sharedStrings 索引）；
   *         内联字符串 t="inlineStr" 的 <is><t>文本</t></is>；数字/bool 直接取 <v>。
   * 空行忽略；行按单元格引用列号补齐。
   */
  private static parseSheet(buffer: ArrayBuffer, shared: string[]): string {
    const rows: string[][] = [];
    let maxCols: number = 0;
    let rowCells: Map<number, string> = new Map<number, string>();
    let curCol: number = 0;
    let curText: string = "";
    let inV: boolean = false;
    let inIs: boolean = false;

    const visitor: XmlTagVisitor = new XmlTagVisitor(
      (name: string): void => {
        const n: string = OoxmlParser.tagName(name);
        if (n === "row") {
          rowCells = new Map<number, string>();
        } else if (n === "c") {
          curText = "";
          curCol = 0;
        } else if (n === "v") {
          inV = true;
        } else if (n === "is") {
          inIs = true;
        }
      },
      (text: string): void => {
        if (inV || inIs) {
          curText += text;
        }
      },
      (name: string, attrs: Map<string, string>): void => {
        const n: string = OoxmlParser.tagName(name);
        if (n === "v") {
          inV = false;
        } else if (n === "is") {
          inIs = false;
        } else if (n === "c") {
          const ref: string = OoxmlParser.attrLocal(attrs, "r");
          curCol = OoxmlParser.colIndexOf(ref);
          const t: string = OoxmlParser.attrLocal(attrs, "t");
          let cellText: string = curText.trim();
          if (t === "s") {
            const idx: number = Number(cellText);
            if (!Number.isNaN(idx) && idx >= 0 && idx < shared.length) {
              cellText = shared[idx];
            }
          } else if (t === "b") {
            cellText = cellText === "1" ? "TRUE" : "FALSE";
          }
          if (curCol > 0) {
            rowCells.set(curCol, cellText);
          }
          curText = "";
        } else if (n === "row") {
          if (rowCells.size > 0) {
            let last: number = 0;
            rowCells.forEach((value: string, key: number) => {
              if (key > last) {
                last = key;
              }
            });
            if (last > maxCols) {
              maxCols = last;
            }
            const rowArr: string[] = [];
            for (let i = 1; i <= last; i++) {
              const v = rowCells.get(i);
              rowArr.push(v === undefined ? "" : v);
            }
            rows.push(rowArr);
          }
        }
      },
    );
    OoxmlParser.parseXmlEvents(buffer, visitor);

    if (rows.length === 0) {
      return "（空表）";
    }
    /* 行已按引用列号补齐，此处用表格最大列对齐输出 */
    const fmtRow = (r: string[]): string => {
      const cells: string[] = [];
      for (let i = 0; i < maxCols; i++) {
        cells.push(i < r.length ? r[i] : "");
      }
      return `| ${cells.join(" | ")} |`;
    };
    const out: string[] = [];
    out.push(fmtRow(rows[0]));
    const sep: string[] = [];
    for (let i = 0; i < maxCols; i++) {
      sep.push("---");
    }
    out.push(`| ${sep.join(" | ")} |`);
    for (let i = 1; i < rows.length; i++) {
      out.push(fmtRow(rows[i]));
    }
    return out.join("\n");
  }

  /** 单元格引用 → 列号（A1 → 1，AA1 → 27）；非字母开头返回 0 */
  private static colIndexOf(ref: string): number {
    let col: number = 0;
    for (let i = 0; i < ref.length; i++) {
      const code: number = ref.charCodeAt(i);
      if (code >= 65 && code <= 90) {
        col = col * 26 + (code - 64);
      } else {
        break;
      }
    }
    return col;
  }
}
