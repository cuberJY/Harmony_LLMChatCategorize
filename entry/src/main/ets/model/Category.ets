/**
 * 对话分类数据模型（状态管理 V2）
 * 对应一个聊天分类
 * 用于：侧边栏分类筛选、分类管理页
 *
 * @ObservedV2 + @Trace：属性级观察。
 * 重命名/改色等操作直接修改 @Trace 属性即可驱动列表项实时刷新（无需 listVersion 强刷）
 */
import { generateId } from "../common/Utils";

@ObservedV2
export class Category {
  @Trace id: string = ""; // UUID 分类ID
  @Trace name: string = ""; // 文件夹名称
  @Trace parentId: string = ""; // 父文件夹 ID，空串 = 顶级文件夹
  @Trace color: string = "#FF9F0A"; // 文件夹图标颜色（默认橙色）
  @Trace sortOrder: number = 0; // 排序序号
  @Trace createdAt: number = 0; // 创建时间戳（毫秒）

  constructor(id?: string, name?: string, parentId?: string, color?: string, sortOrder?: number) {
    this.id = id && id.length > 0 ? id : generateId();
    if (name) this.name = name;
    if (parentId) this.parentId = parentId;
    if (color) this.color = color;
    if (sortOrder !== undefined) this.sortOrder = sortOrder;
    this.createdAt = Date.now();
  }
}
