/** 
* 对话分类数据模型
* 对应一个聊天分类
* 用于：侧边栏分类筛选、分类管理页
*/
export class Category {
  id: string = ""; // UUID 分类ID
  name: string = ""; // 分类名称
  sortOrder: number = 0; // 排序序号
  createdAt: number = 0; // 创建时间戳（毫秒）

  constructor(id?: string, name?: string, sortOrder?: number) {
    if (id) this.id = id;
    if (name) this.name = name;
    if (sortOrder !== undefined) this.sortOrder = sortOrder;
    this.createdAt = Date.now();
  }
}
