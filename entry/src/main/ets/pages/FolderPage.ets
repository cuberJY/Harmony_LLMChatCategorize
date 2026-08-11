/**
 * 文件夹页（FolderPage）
 * 显示指定文件夹下的内容：子文件夹 + 该文件夹下的对话
 * 类似文件管理器进入目录：
 *   - 顶部：文件夹名称 + 返回
 *   - 内容：子文件夹列表（可继续进入）+ 该文件夹下的对话
 *   - 右下角：悬浮圆形 + 按钮 → 新建子文件夹
 * 交互：
 *   - 点击子文件夹 → 进入下一级 FolderPage
 *   - 点击对话 → 返回聊天页加载该对话（pop 携带结果，经 SideBarPage 转发给 ChatPage）
 *   - 长按子文件夹 → 重命名 / 删除（删除二次确认 + 级联）
 *   - 长按对话 → 移动到文件夹 / 重命名 / 删除
 *
 * Navigation 路由重构
 * - 不再作为 @Entry 页面，由 HomePage 的 Navigation 以 NavDestination 形式承载
 * - 路由参数通过 @Param（HomePage pageMap 注入）接收，替代 router.getParams
 */

import { CategoryRepository } from "../database/CategoryRepository";
import { Category } from "../model/Category";
import { Conversation } from "../model/Conversation";
import { FolderItem } from "../components/item/FolderItem";
import { ConversationItem } from "../components/item/ConversationItem";
import { EditFolderDialog } from "../components/dialog/EditFolderDialog";
import { FolderPickerDialog } from "../components/dialog/FolderPickerDialog";
import { RenameInputDialog } from "../components/dialog/RenameInputDialog";
import { showDeleteConfirm } from "../common/Utils";
import { FolderParams } from "../model/FolderParams";
import { FolderViewModel } from "../viewmodel/FolderViewModel";

@ComponentV2
export struct FolderPage {
  // 路由参数（HomePage pageMap 中 pushPathByName 时注入）：当前文件夹 id 与名称
  @Param folderId: string = "";
  @Param folderName: string = "";
  // 路由栈（NavDestination.onReady 获取）：进入下一级 / 返回 / 携带选中对话返回
  private pathStack: NavPathStack = new NavPathStack();
  // 数据与业务逻辑（@Trace 状态 + 子文件夹/对话加载）全部收敛到 ViewModel，页面只保留 build / 路由 / 弹窗
  private vm: FolderViewModel = new FolderViewModel();

  private dialogId: number = -1; // 当前打开的弹窗 ID（openCustomDialog 返回值，供 closeCustomDialog 使用）

  aboutToAppear(): void {
    // 路由参数已由 @Param 注入（HomePage pageMap 初始化），直接传给 ViewModel
    this.vm.setParams(this.folderId, this.folderName);
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部栏
        Row() {
          // 返回按钮
          Row() {
            SymbolGlyph($r("sys.symbol.chevron_left"))
              .fontSize($r('app.float.font_icon_xl'))
              .fontWeight(700)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(40)
          .justifyContent(FlexAlign.Start)
          .onClick(() => {
            this.pathStack.pop();
          })

          // 文件夹名称
          Text(this.vm.folderName.length > 0 ? this.vm.folderName : "文件夹")
            .fontSize($r('app.float.font_title'))
            .fontWeight(700)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          // 右侧占位（保持对称）
          Row().width(40)
        }
        .width("100%")
        .height($r('app.float.title_bar_height'))
        .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md') })
        .backgroundColor($r('app.color.title_bar_bg'))
        .border({ width: { bottom: 1 }, color: { bottom: $r('app.color.divider') } })

        // 内容区
        if (this.vm.subFolders.length === 0 && this.vm.convs.length === 0) {
          // 空态
          Column() {
            Text("此文件夹为空")
              .fontSize($r('app.float.font_remind'))
              .fontColor($r('app.color.text_secondary'))
          }
          .width("100%")
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center);
        } else {
          List() {
            // 子文件夹列表
            ForEach(
              this.vm.subFolders,
              (cat: Category) => {
                ListItem() {
                  FolderItem({
                    category: cat,
                    onClickItem: (selected: Category) => {
                      // 进入下一级子文件夹（同名路由再次入栈，参数为新文件夹）
                      this.pathStack.pushPathByName(
                        "FolderPage",
                        new FolderParams(selected.id, selected.name),
                      );
                    },
                    onMenuRename: (selected: Category) => {
                      this.openEditFolder(selected);
                    },
                    onMenuPin: (selected: Category) => {
                      this.vm.togglePinFolder(selected);
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
              (cat: Category) => `${cat.id}_${this.vm.listVersion}`,
            )

            // 该文件夹下的对话
            ForEach(
              this.vm.convs,
              (conv: Conversation) => {
                ListItem() {
                  ConversationItem({
                    conversation: conv,
                    // 文件夹页：不显示星标（该页全是已收藏对话）；保留"移动"菜单调整位置
                    showFavoriteIcon: false,
                    onClickItem: (selected: Conversation) => {
                      // 选中对话 → pop 携带结果，逐层转发给 ChatPage 加载（SideBarPage 的 onPop 负责转发）
                      this.pathStack.pop(selected);
                    },
                    onMenuMove: (selected: Conversation) => {
                      this.openPicker(selected);
                    },
                    onMenuRename: (selected: Conversation) => {
                      this.openRenameConvDialog(selected);
                    },
                    onMenuPin: (selected: Conversation) => {
                      this.vm.togglePinConv(selected);
                    },
                    onMenuDelete: (selected: Conversation) => {
                      this.confirmDeleteConv(selected);
                    },
                    onMenuFavorite: (selected: Conversation) => {
                      this.vm.unfavorite(selected);
                    },
                  })
                }.width("100%");
              },
              (conv: Conversation) => `${conv.id}_${this.vm.listVersion}`,
            )
          }
          .width("100%")
          .layoutWeight(1)
          .backgroundColor($r('app.color.page_bg'))
          // 项间自动分割线（与收藏 Tab 一致：文件夹/对话之间都有全宽分割线）
          .divider({
            strokeWidth: 0.5,
            color: $r('app.color.divider'),
          })
          .edgeEffect(EdgeEffect.Spring);
        }
      }
      .width("100%")
      .height("100%")
      .backgroundColor($r('app.color.page_bg'))
      // 悬浮新建子文件夹按钮（右下角）
      .overlay(this.fabBuilder(), {
        align: Alignment.BottomEnd,
      });
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .onShown(() => {
      // 首次进入与从子文件夹页面返回时刷新（子页可能移动/删除/重命名内容，返回需同步）
      this.vm.loadData();
    })
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
          .fontSize($r('app.float.font_icon_xxl'))
          .fontColor(Color.White)
          .fontWeight(500)
      }
      .width(32)
      .height(32)
      .type(ButtonType.Circle)
      .backgroundColor($r('app.color.primary'))
      .shadow({ radius: 8, color: $r('app.color.fab_shadow'), offsetY: 2 })
      .onClick(() => {
        this.openNewFolderDialog();
      })
    }
    .hitTestBehavior(HitTestMode.None)
    .padding({ right: $r('app.float.space_xl'), bottom: $r('app.float.space_xl') });
  }

  // 关闭当前打开的弹窗（弹窗组件通过 onRequestClose 回调触发）
  private closeDialog(): void {
    if (this.dialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.dialogId);
      this.dialogId = -1;
    }
  }

  // 新建子文件夹
  private openNewFolderDialog(): void {
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.buildNewFolderDialog(),
      autoCancel: true,
      alignment: DialogAlignment.Top,
      offset: { dx: 0, dy: 280 },
    }).then((id: number) => {
      this.dialogId = id;
    });
  }

  @Builder
  buildNewFolderDialog() {
    RenameInputDialog({
      title: "新建子文件夹",
      placeholder: "请输入文件夹名称",
      onConfirm: (name: string) => {
        this.vm.createSubFolder(name);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 编辑子文件夹：重命名 + 切换图标颜色
  private openEditFolder(cat: Category): void {
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.buildEditFolderDialog(cat),
      autoCancel: true,
      alignment: DialogAlignment.Top,
      offset: { dx: 0, dy: 280 },
    }).then((id: number) => {
      this.dialogId = id;
    });
  }

  @Builder
  buildEditFolderDialog(cat: Category) {
    EditFolderDialog({
      oldName: cat.name,
      oldColor: cat.color,
      onConfirm: (name: string, color: string) => {
        this.vm.saveEdit(cat, name, color);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 删除子文件夹（二次确认 + 级联）
  private confirmDeleteFolder(cat: Category): void {
    showDeleteConfirm(
      this.getUIContext(),
      "删除文件夹",
      `确定删除文件夹“${cat.name}”吗？其下所有子文件夹及对话的分类关系将被移除，对话本身不会删除。`,
      () => {
        this.vm.deleteFolderCascade(cat.id);
      },
    );
  }

  // 移动文件夹：弹出目标选择器（排除自身及子孙，防止成环）
  private async openMoveFolder(cat: Category): Promise<void> {
    // 候选目标 = 全部文件夹 - 自身及子孙（空串"不分类"由选择器提供，表示移到顶级）
    const candidates = await CategoryRepository.getInstance().getMoveCandidates(cat.id);
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.buildMoveFolderPicker(cat, candidates),
      autoCancel: true,
      alignment: DialogAlignment.Center,
    }).then((id: number) => {
      this.dialogId = id;
    });
  }

  @Builder
  buildMoveFolderPicker(cat: Category, folders: Category[]) {
    FolderPickerDialog({
      title: "移动到文件夹",
      folders: folders,
      onSelect: (targetId: string) => {
        this.vm.moveFolder(cat, targetId);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 移动到文件夹：弹出文件夹选择器
  private async openPicker(conv: Conversation): Promise<void> {
    const allFolders = await CategoryRepository.getInstance().getAll();
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.buildConvPicker(conv, allFolders),
      autoCancel: true,
      alignment: DialogAlignment.Center,
    }).then((id: number) => {
      this.dialogId = id;
    });
  }

  @Builder
  buildConvPicker(conv: Conversation, folders: Category[]) {
    FolderPickerDialog({
      folders: folders,
      onSelect: (folderId: string) => {
        this.vm.moveConv(conv, folderId);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 重命名对话
  private openRenameConvDialog(conv: Conversation): void {
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.buildRenameConvDialog(conv),
      autoCancel: true,
      alignment: DialogAlignment.Top,
      offset: { dx: 0, dy: 280 },
    }).then((id: number) => {
      this.dialogId = id;
    });
  }

  @Builder
  buildRenameConvDialog(conv: Conversation) {
    RenameInputDialog({
      title: "重命名对话",
      oldValue: conv.title,
      onConfirm: (name: string) => {
        this.vm.renameConv(conv, name);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 删除对话（二次确认）
  private confirmDeleteConv(conv: Conversation): void {
    showDeleteConfirm(
      this.getUIContext(),
      "删除对话",
      `确定删除对话“${conv.title.length > 0 ? conv.title : "新对话"}”吗？删除后不可恢复。`,
      () => {
        this.vm.deleteConv(conv.id);
      },
    );
  }
}
