/**
 * 文件夹页（FolderPage）
 * 显示指定文件夹下的内容：子文件夹 + 该文件夹下的对话
 * 类似文件管理器进入目录：
 *   - 顶部：文件夹名称 + 返回
 *   - 内容：子文件夹列表（可继续进入）+ 该文件夹下的对话
 *   - 右下角：悬浮圆形 + 按钮 → 新建子文件夹
 * 交互：
 *   - 点击子文件夹 → 进入下一级 FolderPage
 *   - 点击对话 → 返回聊天页加载该对话
 *   - 长按子文件夹 → 重命名 / 删除（删除二次确认 + 级联）
 *   - 长按对话 → 移动到文件夹 / 重命名 / 删除
 */

import { router, promptAction } from "@kit.ArkUI";
import { DatabaseHelper } from "../database/DatabaseHelper";
import { Category } from "../model/Category";
import { Conversation } from "../model/Conversation";
import { FolderItem } from "../components/FolderItem";
import { ConversationItem } from "../components/ConversationItem";
import { EditFolderDialog } from "../components/EditFolderDialog";
import { FolderPickerDialog } from "../components/FolderPickerDialog";
import { AppConfig } from "../config/AppConfig";
import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";

// 新建/重命名文件夹对话框：预填名称，确认后回调
@CustomDialog
struct NewFolderDialog {
  controller?: CustomDialogController;
  title: string = "新建文件夹"; // 对话框标题（新建/重命名通用）
  onConfirm: (name: string) => void = (name: string) => {};
  @State inputValue: string = ""; // 输入框内容

  aboutToAppear(): void {
    this.inputValue = this.oldName; // 重命名时预填旧名
  }

  // 预填名称（仅重命名时使用）
  oldName: string = "";

  build() {
    Column({ space: SPACING.MD }) {
      Text(this.title)
        .fontSize(FONT_SIZES.BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width("100%")
        .textAlign(TextAlign.Start)
      TextInput({ placeholder: "请输入文件夹名称", text: this.inputValue })
        .defaultFocus(true)
        .fontSize(FONT_SIZES.INPUT)
        .fontColor(COLORS.TEXT_PRIMARY)
        .backgroundColor(COLORS.PAGE_BG)
        .borderRadius(8)
        .borderWidth(1)
        .borderColor(COLORS.INPUT_BORDER)
        .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.XS, bottom: SPACING.XS })
        .width("100%")
        .onChange((value: string) => {
          this.inputValue = value;
        })
      Row() {
        Text("取消")
          .fontSize(FONT_SIZES.BUTTON)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: SPACING.MD, bottom: SPACING.XS })
          .onClick(() => {
            this.controller?.close();
          })
        Text("确定")
          .fontSize(FONT_SIZES.BUTTON)
          .fontColor(COLORS.PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: SPACING.MD, bottom: SPACING.XS })
          .onClick(() => {
            if (this.inputValue.trim().length > 0) {
              this.onConfirm(this.inputValue.trim());
            } else {
              promptAction.showToast({ message: "名称不能为空" });
            }
            this.controller?.close();
          })
      }.width("100%")
    }
    .padding(SPACING.LG)
    .width("85%")
    .borderRadius(16)
    .backgroundColor(Color.White);
  }
}

@Entry
@Component
struct FolderPage {
  // 路由参数：当前文件夹 id 和名称（由 SideBarPage / 上级 FolderPage 传入）
  @State folderId: string = "";
  @State folderName: string = "";
  @State subFolders: Category[] = []; // 子文件夹列表
  @State convs: Conversation[] = []; // 该文件夹下的对话列表
  @State listVersion: number = 0; // 列表刷新版本号：重命名/改色等键不变的内容变更后自增，强制 ForEach 重建

  private newFolderController: CustomDialogController | null = null; // 新建/重命名对话框控制器
  private pickerController: CustomDialogController | null = null; // 移动选择器控制器

  aboutToAppear(): void {
    // 1. 读取路由参数
    const params = router.getParams() as Record<string, string>;
    if (params) {
      this.folderId = params.folderId ?? "";
      this.folderName = params.folderName ?? "";
    }
    // 2. 加载数据
    this.loadData();
  }

  build() {
    Column() {
      // 顶部栏
      Row() {
        // 返回按钮
        Row() {
          SymbolGlyph($r("sys.symbol.chevron_left"))
            .fontSize(FONT_SIZES.ICON_XL)
            .fontWeight(700)
            .fontColor([Color.Black])
        }
        .width(40)
        .justifyContent(FlexAlign.Start)
        .onClick(() => {
          router.back();
        })

        // 文件夹名称
        Text(this.folderName.length > 0 ? this.folderName : "文件夹")
          .fontSize(FONT_SIZES.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 右侧占位（保持对称）
        Row().width(40)
      }
      .width("100%")
      .height(SPACING.TITLE_BAR_HEIGHT)
      .padding({ left: SPACING.MD, right: SPACING.MD })
      .backgroundColor(COLORS.TITLE_BAR_BG)
      .border({ width: { bottom: 1 }, color: { bottom: COLORS.DIVIDER } })

      // 内容区
      if (this.subFolders.length === 0 && this.convs.length === 0) {
        // 空态
        Column() {
          Text("此文件夹为空")
            .fontSize(FONT_SIZES.REMIND)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .width("100%")
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      } else {
        List() {
          // 子文件夹列表
          ForEach(
            this.subFolders,
            (cat: Category) => {
              ListItem() {
                FolderItem({
                  category: cat,
                  onClickItem: (selected: Category) => {
                    // 进入下一级子文件夹
                    router.pushUrl({
                      url: "pages/FolderPage",
                      params: { folderId: selected.id, folderName: selected.name },
                    });
                  },
                  onMenuRename: (selected: Category) => {
                    this.openEditFolder(selected);
                  },
                  onMenuMove: (selected: Category) => {
                    this.openMoveFolder(selected);
                  },
                  onMenuDelete: (selected: Category) => {
                    this.confirmDeleteFolder(selected);
                  },
                })
              }.width("100%");
            },
            (cat: Category) => `${cat.id}_${this.listVersion}`,
          )

          // 子文件夹与对话之间的分隔线（两者都有时才显示）
          if (this.subFolders.length > 0 && this.convs.length > 0) {
            ListItem() {
              Divider()
                .strokeWidth(0.5)
                .color(COLORS.DIVIDER)
                .margin({ left: SPACING.XL, right: SPACING.XL })
            };
          }

          // 该文件夹下的对话
          ForEach(
            this.convs,
            (conv: Conversation) => {
              ListItem() {
                ConversationItem({
                  conversation: conv,
                  // 文件夹页：不显示星标（该页全是已收藏对话）；保留"移动"菜单调整位置
                  showFavoriteIcon: false,
                  onClickItem: (selected: Conversation) => {
                    // 选中对话 → 交给 ChatPage 加载（经由 SideBarPage 中转返回）
                    AppConfig.getInstance().selectedConversation = selected;
                    router.back();
                  },
                  onMenuMove: (selected: Conversation) => {
                    this.openPicker(selected);
                  },
                  onMenuRename: (selected: Conversation) => {
                    this.openRenameConvDialog(selected);
                  },
                  onMenuDelete: (selected: Conversation) => {
                    this.confirmDeleteConv(selected);
                  },
                  onMenuFavorite: (selected: Conversation) => {
                    this.doUnfavorite(selected);
                  },
                })
              }.width("100%");
            },
            (conv: Conversation) => `${conv.id}_${this.listVersion}`,
          )
        }
        .width("100%")
        .layoutWeight(1)
        .backgroundColor(COLORS.PAGE_BG)
        .edgeEffect(EdgeEffect.Spring);
      }
    }
    .width("100%")
    .height("100%")
    .backgroundColor(COLORS.PAGE_BG)
    // 悬浮新建子文件夹按钮（右下角）
    .overlay(this.fabBuilder(), {
      align: Alignment.BottomEnd,
    });
  }

  /**
   * 悬浮新建子文件夹按钮（右下角）
   * @Builder 包装：overlay 需要 CustomBuilder 类型参数
   */
  @Builder
  private fabBuilder() {
    Stack() {
      Button() {
        Text("+")
          .fontSize(FONT_SIZES.ICON_XXL)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
      }
      .width(32)
      .height(32)
      .type(ButtonType.Circle)
      .backgroundColor(COLORS.PRIMARY)
      .shadow({ radius: 8, color: "#662D65F8", offsetY: 2 })
      .onClick(() => {
        this.openNewFolderDialog();
      })
    }
    .hitTestBehavior(HitTestMode.None)
    .padding({ right: SPACING.XL, bottom: SPACING.XL });
  }

  // 数据加载

  /**
   * 加载当前文件夹的数据：子文件夹 + 该文件夹下的对话
   */
  private async loadData(): Promise<void> {
    this.subFolders = await DatabaseHelper.getInstance().getCategoriesByParent(this.folderId);
    this.convs = await DatabaseHelper.getInstance().getConversationsByCategory(this.folderId);
  }

  // 文件夹操作

  // 新建子文件夹
  private openNewFolderDialog(): void {
    this.newFolderController = new CustomDialogController({
      builder: NewFolderDialog({
        title: "新建子文件夹",
        oldName: "",
        onConfirm: (name: string) => {
          this.createSubFolder(name);
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Top,
      offset: { dx: 0, dy: 280 },
      customStyle: true,
    });
    this.newFolderController.open();
  }

  // 执行新建子文件夹
  private async createSubFolder(name: string): Promise<void> {
    const cat = new Category(undefined, name, this.folderId);
    await DatabaseHelper.getInstance().insertCategory(cat);
    await this.loadData();
    promptAction.showToast({ message: `已创建「${name}」` });
  }

  // 编辑子文件夹：重命名 + 切换图标颜色
  private openEditFolder(cat: Category): void {
    this.newFolderController = new CustomDialogController({
      builder: EditFolderDialog({
        oldName: cat.name,
        oldColor: cat.color,
        onConfirm: async (name: string, color: string) => {
          if (name.length === 0) {
            promptAction.showToast({ message: "名称不能为空" });
            return;
          }
          cat.name = name;
          cat.color = color; // 更新图标颜色
          await DatabaseHelper.getInstance().updateCategory(cat);
          await this.loadData();
          this.listVersion++; // 强制 ForEach 重建，刷新名称/颜色
          promptAction.showToast({ message: "已保存" });
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Top,
      offset: { dx: 0, dy: 280 },
      customStyle: true,
    });
    this.newFolderController.open();
  }

  // 删除子文件夹（二次确认 + 级联）
  private confirmDeleteFolder(cat: Category): void {
    this.getUIContext().showAlertDialog({
      title: "删除文件夹",
      message: `确定删除文件夹“${cat.name}”吗？其下所有子文件夹及对话的分类关系将被移除，对话本身不会删除。`,
      primaryButton: { value: "取消", action: () => {} },
      secondaryButton: {
        value: "删除",
        fontColor: Color.Red,
        action: () => {
          this.doDeleteFolder(cat.id);
        },
      },
    });
  }

  // 执行删除文件夹（级联）
  private async doDeleteFolder(id: string): Promise<void> {
    await DatabaseHelper.getInstance().deleteCategoryCascade(id);
    await this.loadData();
    promptAction.showToast({ message: "文件夹已删除" });
  }

  // 移动文件夹：弹出目标选择器（排除自身及子孙，防止成环）
  private async openMoveFolder(cat: Category): Promise<void> {
    const all = await DatabaseHelper.getInstance().getCategories();
    const exclude = await DatabaseHelper.getInstance().getCategorySubtreeIds(cat.id);
    // 候选目标 = 全部文件夹 - 自身及子孙（空串"不分类"由选择器提供，表示移到顶级）
    const candidates = all.filter((c: Category) => exclude.indexOf(c.id) < 0);
    this.pickerController = new CustomDialogController({
      builder: FolderPickerDialog({
        title: "移动到文件夹",
        folders: candidates,
        onSelect: (targetId: string) => {
          this.doMoveFolder(cat, targetId);
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
    });
    this.pickerController.open();
  }

  // 执行移动：更新 parentId 并刷新列表
  private async doMoveFolder(cat: Category, targetId: string): Promise<void> {
    cat.parentId = targetId; // 空串 = 移到顶级
    await DatabaseHelper.getInstance().updateCategory(cat);
    await this.loadData();
    promptAction.showToast({ message: targetId.length > 0 ? "已移动" : "已移到顶级" });
  }

  // 对话操作

  // 移动到文件夹：弹出文件夹选择器
  private async openPicker(conv: Conversation): Promise<void> {
    const allFolders = await DatabaseHelper.getInstance().getCategories();
    this.pickerController = new CustomDialogController({
      builder: FolderPickerDialog({
        folders: allFolders,
        onSelect: (folderId: string) => {
          this.doMove(conv, folderId);
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
    });
    this.pickerController.open();
  }

  // 执行移动：更新对话分类
  private async doMove(conv: Conversation, folderId: string): Promise<void> {
    conv.categoryId = folderId;
    await DatabaseHelper.getInstance().updateConversation(conv);
    // 若移出的目标不是当前文件夹 → 从当前列表移除
    if (folderId !== this.folderId) {
      this.convs = this.convs.filter((c: Conversation) => c.id !== conv.id);
    }
    promptAction.showToast({ message: "移动成功" });
  }

  // 重命名对话
  private openRenameConvDialog(conv: Conversation): void {
    this.newFolderController = new CustomDialogController({
      builder: NewFolderDialog({
        title: "重命名对话",
        oldName: conv.title,
        onConfirm: (name: string) => {
          this.doRenameConv(conv, name);
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Top,
      offset: { dx: 0, dy: 280 },
      customStyle: true,
    });
    this.newFolderController.open();
  }

  // 执行重命名对话
  private async doRenameConv(conv: Conversation, name: string): Promise<void> {
    conv.title = name;
    await DatabaseHelper.getInstance().updateConversation(conv);
    this.listVersion++; // 强制 ForEach 重建，刷新对话标题
    promptAction.showToast({ message: "重命名成功" });
  }

  // 删除对话（二次确认）
  private confirmDeleteConv(conv: Conversation): void {
    this.getUIContext().showAlertDialog({
      title: "删除对话",
      message: `确定删除对话“${conv.title.length > 0 ? conv.title : "新对话"}”吗？删除后不可恢复。`,
      primaryButton: { value: "取消", action: () => {} },
      secondaryButton: {
        value: "删除",
        fontColor: Color.Red,
        action: () => {
          this.doDeleteConv(conv.id);
        },
      },
    });
  }

  // 执行删除对话
  private async doDeleteConv(id: string): Promise<void> {
    await DatabaseHelper.getInstance().deleteConversations([id]);
    this.convs = this.convs.filter((c: Conversation) => c.id !== id);
    promptAction.showToast({ message: "已删除" });
  }

  // 取消收藏：清空收藏标记与位置，并从当前文件夹移除（未收藏对话不参与文件夹分类）
  private async doUnfavorite(conv: Conversation): Promise<void> {
    await DatabaseHelper.getInstance().setFavorite(conv, false);
    conv.isFavorite = false;
    conv.categoryId = "";
    // 从当前文件夹对话列表移除（对话不再属于任何文件夹）
    this.convs = this.convs.filter((c: Conversation) => c.id !== conv.id);
    this.listVersion++;
    promptAction.showToast({ message: "已取消收藏" });
  }
}
