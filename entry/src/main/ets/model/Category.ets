/**
 * 对话分类数据模型
 * 对应一个聊天分类
 * 用于：侧边栏分类筛选、分类管理页
 */
// @Observed：使类的属性变化可被 @ObjectLink 深观察（列表实时刷新重命名/改色）
import { generateId } from "../common/Utils";

@Observed
export class Category {
  id: string = ""; // UUID 分类ID
  name: string = ""; // 文件夹名称
  parentId: string = ""; // 父文件夹 ID，空串 = 顶级文件夹
  color: string = "#FF9F0A"; // 文件夹图标颜色（默认橙色）
  sortOrder: number = 0; // 排序序号
  createdAt: number = 0; // 创建时间戳（毫秒）

  constructor(id?: string, name?: string, parentId?: string, color?: string, sortOrder?: number) {
    this.id = id && id.length > 0 ? id : generateId();
    if (name) this.name = name;
    if (parentId) this.parentId = parentId;
    if (color) this.color = color;
    if (sortOrder !== undefined) this.sortOrder = sortOrder;
    this.createdAt = Date.now();
  }
}
