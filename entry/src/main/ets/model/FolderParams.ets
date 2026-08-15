/**
 * FolderPage 路由参数（Navigation 传参专用）
 * ArkTS 限制（arkts-no-untyped-obj-literals）要求对象字面量对应显式类，故用类实例传参；
 * 由 HomePage / SideBarPage / FolderPage 共用
 */
export class FolderParams {
  folderId: string; // 目标文件夹 id
  folderName: string; // 目标文件夹名称（用于标题栏展示）

  constructor(folderId: string, folderName: string) {
    this.folderId = folderId;
    this.folderName = folderName;
  }
}
