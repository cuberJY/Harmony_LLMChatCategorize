/**
 * FolderPage 路由参数（Navigation 传参专用）
 * ArkTS 限制：对象字面量必须对应显式声明的类（arkts-no-untyped-obj-literals），
 * 因此路由参数用类实例传递，替代 { key: value } 字面量。
 * 由 HomePage / SideBarPage / FolderPage 三处共用。
 */
export class FolderParams {
  folderId: string; // 目标文件夹 id
  folderName: string; // 目标文件夹名称（用于标题栏展示）

  constructor(folderId: string, folderName: string) {
    this.folderId = folderId;
    this.folderName = folderName;
  }
}
