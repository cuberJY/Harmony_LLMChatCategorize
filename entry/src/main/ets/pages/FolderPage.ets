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

import { ComponentContent, KeyboardAvoidMode } from "@kit.ArkUI";
import { BusinessError } from "@kit.BasicServicesKit";
import { CategoryRepository } from "../database/CategoryRepository";
import { Category } from "../model/Category";
import { Conversation } from "../model/Conversation";
import { FolderItem } from "../components/item/FolderItem";
import { ConversationItem } from "../components/item/ConversationItem";
import { EditFolderDialogParams, buildEditFolderContent } from "../components/dialog/EditFolderDialog";
import { FolderPickerDialogParams, buildFolderPickerContent } from "../components/dialog/FolderPickerDialog";
import { RenameDialogParams, buildRenameDialog } from "../components/dialog/RenameInputDialog";
import { showDeleteConfirm } from "../common/Utils";
import { DIALOG_DELAY_AFTER_MENU, DIALOG_OFFSET_SLIGHT, DIALOG_OFFSET_TALL, DEFAULT_FOLDER_COLOR } from "../common/AppConstants";
import { FolderParams } from "../model/FolderParams";
import { FolderViewModel } from "../viewmodel/FolderViewModel";

@ComponentV2
export struct FolderPage {
  /* 路由参数（HomePage pageMap 中 pushPathByName 时注入）：当前文件夹 id 与名称 */
  @Param folderId: string = "";
  @Param folderName: string = "";
  /* 路由栈（NavDestination.onReady 获取）：进入下一级 / 返回 / 携带选中对话返回 */
  private pathStack: NavPathStack = new NavPathStack();
  /* 数据与业务逻辑（@Trace 状态 + 子文件夹/对话加载）全部收敛到 ViewModel，页面只保留 build / 路由 / 弹窗 */
  private vm: FolderViewModel = new FolderViewModel();

  /* 各弹窗的内容节点（ComponentContent 方式）：非空表示已打开或残留待清理，关闭/失败后置 null */
  private newFolderNode: ComponentContent<EditFolderDialogParams> | null = null; // 新建子文件夹（名称+颜色）
  private editFolderNode: ComponentContent<EditFolderDialogParams> | null = null; // 编辑子文件夹
  private moveFolderNode: ComponentContent<FolderPickerDialogParams> | null = null; // 移动文件夹
  private convPickerNode: ComponentContent<FolderPickerDialogParams> | null = null; // 移动对话
  private renameConvNode: ComponentContent<RenameDialogParams> | null = null; // 重命名对话
  private globalKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.RESIZE; // 记录全局避让模式

  aboutToAppear(): void {
    /**
     * 记住全局模式（EntryAbility 里设的 RESIZE），本页切换为 NONE：
     * 弹窗使用 Bottom + dy -360 固定位置（与收藏 Tab 一致），键盘弹出时不跳动
     */
    this.globalKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    /* 路由参数已由 @Param 注入（HomePage pageMap 初始化），直接传给 ViewModel */
    this.vm.setParams(this.folderId, this.folderName);
  }

  aboutToDisappear(): void {
    /* 离开页面恢复全局模式，保证上层页面（SideBarPage/ChatPage）的避让行为不受影响 */
    this.getUIContext().setKeyboardAvoidMode(this.globalKeyboardAvoidMode);
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
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

          Text(this.vm.folderName.length > 0 ? this.vm.folderName : "文件夹")
            .fontSize($r('app.float.font_title'))
            .fontWeight(700)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row().width(40)
        }
        .width("100%")
        .height($r('app.float.title_bar_height'))
        .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md') })
        .backgroundColor($r('app.color.title_bar_bg'))
        .border({ width: { bottom: 2 }, color: { bottom: $r('app.color.divider') } })

        if (this.vm.subFolders.length === 0 && this.vm.convs.length === 0) {
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
            /* 子文件夹列表 */
            ForEach(
              this.vm.subFolders,
              (cat: Category) => {
                ListItem() {
                  FolderItem({
                    category: cat,
                    onClickItem: (selected: Category) => {
                      /* 进入下一级子文件夹（同名路由再次入栈，参数为新文件夹） */
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
              (cat: Category) => cat.id + "_" + this.vm.listVersion.toString(),
            )

            /* 该文件夹下的对话 */
            ForEach(
              this.vm.convs,
              (conv: Conversation) => {
                ListItem() {
                  ConversationItem({
                    conversation: conv,
                    /* 文件夹页：不显示星标（该页全是已收藏对话）；保留"移动"菜单调整位置 */
                    showFavoriteIcon: false,
                    onClickItem: (selected: Conversation) => {
                      /* 选中对话 → pop 携带结果，逐层转发给 ChatPage 加载（SideBarPage 的 onPop 负责转发） */
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
              (conv: Conversation) => conv.id + "_" + this.vm.listVersion.toString(),
            )
          }
          .width("100%")
          .height("100%")
          .padding({ top: $r('app.float.space_md') })
          .backgroundColor($r('app.color.page_bg'))
          /* 项间自动分割线（与收藏 Tab 一致：文件夹/对话之间都有全宽分割线） */
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
      /* 悬浮新建子文件夹按钮（右下角） */
      .overlay(this.fabBuilder(), {
        align: Alignment.BottomEnd,
      });
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .onShown(() => {
      /* 首次进入与从子文件夹页面返回时刷新（子页可能移动/删除/重命名内容，返回需同步） */
      this.vm.loadData();
    })
  }

  /* 重命名对话（ComponentContent 方式，复用 RenameInputDialog） */
  private openRenameConvDialog(conv: Conversation): void {
    /* 先释放上次点遮罩关闭后残留的节点，防止内存泄漏 */
    if (this.renameConvNode) {
      this.renameConvNode.dispose();
      this.renameConvNode = null;
    }
    const params = new RenameDialogParams();
    params.title = "重命名对话";
    params.oldValue = conv.title;
    params.onConfirm = (name: string) => {
      this.vm.renameConv(conv, name);
    };
    params.onRequestClose = () => {
      this.closeDialog();
    };
    const node = new ComponentContent<RenameDialogParams>(this.getUIContext(),
      wrapBuilder(buildRenameDialog), params);
    this.renameConvNode = node;
    /* 延迟打开：等长按菜单（子窗口）关闭动画结束后再弹，否则弹窗会被菜单关闭流程吞掉 */
    setTimeout(() => {
      this.getUIContext().getPromptAction().openCustomDialog(node, {
        autoCancel: true,
        alignment: DialogAlignment.Center,
        offset: DIALOG_OFFSET_SLIGHT,
      }).catch((err: BusinessError) => {
        console.error(`openCustomDialog(重命名对话) 失败 code=${err.code} msg=${err.message}`);
        this.renameConvNode = null;
      });
    }, DIALOG_DELAY_AFTER_MENU);
  }

  /**
   * 悬浮新建子文件夹按钮（右下角）
   * 与收藏 Tab 的悬浮按钮方案统一：48×48 圆形 + 阴影
   * @Builder 包装：overlay 需要 CustomBuilder 类型参数
   */
  @Builder
  private fabBuilder() {
    Stack() {
      Button() {
        SymbolGlyph($r("sys.symbol.plus"))
          .fontSize($r('app.float.font_icon_xxl'))
          .fontColor([Color.White])
          .fontWeight(900)
      }
      .width(48)
      .height(48)
      .type(ButtonType.Circle)
      .backgroundColor($r('app.color.primary'))
      .shadow({ radius: 8, color: $r('app.color.fab_shadow'), offsetY: 2 })
      .margin({ right: $r('app.float.space_xl'), bottom: $r('app.float.space_xl') })
      .onClick(() => {
        this.openNewFolderDialog();
      })
    }
    .width("100%")
    .height("100%")
    .align(Alignment.BottomEnd) // 按钮定位到右下角，margin 提供外边距
    .hitTestBehavior(HitTestMode.None); // 透明区域不拦截触摸，仅按钮响应点击
  }

  /* 关闭一个 ComponentContent 弹窗节点并释放（关闭成功或已自动关闭都保证 dispose） */
  private closeContentNode<T extends Object>(node: ComponentContent<T>): void {
    this.getUIContext().getPromptAction().closeCustomDialog(node)
      .then(() => {
        node.dispose(); // 关闭后释放内容节点，防止内存泄漏
      })
      .catch((err: BusinessError) => {
        node.dispose(); // 弹窗可能已通过点遮罩自动关闭，close 会失败，直接释放节点即可
        console.error(`closeCustomDialog 失败 code=${err.code} msg=${err.message}`);
      });
  }

  /* 关闭当前打开的弹窗（弹窗组件通过 onRequestClose 回调触发） */
  private closeDialog(): void {
    /* 同一时刻至多一个节点非空；先置 null 再关闭，避免重复 close */
    const n1 = this.newFolderNode;
    if (n1) {
      this.newFolderNode = null;
      this.closeContentNode(n1);
    }
    const n2 = this.editFolderNode;
    if (n2) {
      this.editFolderNode = null;
      this.closeContentNode(n2);
    }
    const n3 = this.moveFolderNode;
    if (n3) {
      this.moveFolderNode = null;
      this.closeContentNode(n3);
    }
    const n4 = this.convPickerNode;
    if (n4) {
      this.convPickerNode = null;
      this.closeContentNode(n4);
    }
    const n5 = this.renameConvNode;
    if (n5) {
      this.renameConvNode = null;
      this.closeContentNode(n5);
    }
  }

  /* 新建子文件夹（ComponentContent 方式，复用 EditFolderDialog：名称 + 颜色，与收藏 Tab 新建文件夹统一） */
  private openNewFolderDialog(): void {
    /* 先释放上次点遮罩关闭后残留的节点，防止内存泄漏 */
    if (this.newFolderNode) {
      this.newFolderNode.dispose();
      this.newFolderNode = null;
    }
    /* 组装弹窗参数与回调（onConfirm 在弹窗"确定"时回调，闭包内 this 仍指向本页面） */
    const params = new EditFolderDialogParams();
    params.title = "新建子文件夹";
    params.oldName = "";
    params.oldColor = DEFAULT_FOLDER_COLOR;
    params.onConfirm = (name: string, color: string) => {
      this.vm.createSubFolder(name, color);
    };
    params.onRequestClose = () => {
      this.closeDialog();
    };
    /* ComponentContent：内容绑定本页面 UIContext，但组件实例独立，规避成员 @Builder 的时序/绑定问题 */
    const node = new ComponentContent<EditFolderDialogParams>(this.getUIContext(),
      wrapBuilder(buildEditFolderContent), params);
    this.newFolderNode = node;
    this.getUIContext().getPromptAction().openCustomDialog(node, {
      autoCancel: true,
      alignment: DialogAlignment.Center,
      offset: DIALOG_OFFSET_TALL,
    }).catch((err: BusinessError) => {
      console.error(`openCustomDialog(新建子文件夹) 失败 code=${err.code} msg=${err.message}`);
      this.newFolderNode = null;
    });
  }

  /* 编辑子文件夹：重命名 + 切换图标颜色（ComponentContent 方式，复用 EditFolderDialog） */
  private openEditFolder(cat: Category): void {
    /* 先释放上次点遮罩关闭后残留的节点，防止内存泄漏 */
    if (this.editFolderNode) {
      this.editFolderNode.dispose();
      this.editFolderNode = null;
    }
    const params = new EditFolderDialogParams();
    params.oldName = cat.name;
    params.oldColor = cat.color;
    params.onConfirm = (name: string, color: string) => {
      this.vm.saveEdit(cat, name, color);
    };
    params.onRequestClose = () => {
      this.closeDialog();
    };
    const node = new ComponentContent<EditFolderDialogParams>(this.getUIContext(),
      wrapBuilder(buildEditFolderContent), params);
    this.editFolderNode = node;
    /* 延迟打开：等长按菜单（子窗口）关闭动画结束后再弹，否则弹窗会被菜单关闭流程吞掉 */
    setTimeout(() => {
      this.getUIContext().getPromptAction().openCustomDialog(node, {
        autoCancel: true,
        alignment: DialogAlignment.Center,
        offset: DIALOG_OFFSET_TALL,
      }).catch((err: BusinessError) => {
        console.error(`openCustomDialog(编辑文件夹) 失败 code=${err.code} msg=${err.message}`);
        this.editFolderNode = null;
      });
    }, DIALOG_DELAY_AFTER_MENU);
  }

  /* 删除子文件夹（二次确认 + 级联） */
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

  /* 移动文件夹：弹出目标选择器（ComponentContent 方式，排除自身及子孙，防止成环） */
  private async openMoveFolder(cat: Category): Promise<void> {
    /* 先释放上次点遮罩关闭后残留的节点，防止内存泄漏 */
    if (this.moveFolderNode) {
      this.moveFolderNode.dispose();
      this.moveFolderNode = null;
    }
    /* 候选目标 = 全部文件夹 - 自身及子孙（空串"不分类"由选择器提供，表示移到顶级） */
    const candidates = await CategoryRepository.getInstance().getMoveCandidates(cat.id);
    const params = new FolderPickerDialogParams();
    params.title = "移动到文件夹";
    params.folders = candidates;
    params.onSelect = (targetId: string) => {
      this.vm.moveFolder(cat, targetId);
    };
    params.onRequestClose = () => {
      this.closeDialog();
    };
    const node = new ComponentContent<FolderPickerDialogParams>(this.getUIContext(),
      wrapBuilder(buildFolderPickerContent), params);
    this.moveFolderNode = node;
    /* 延迟打开：等长按菜单（子窗口）关闭动画结束后再弹，否则弹窗会被菜单关闭流程吞掉 */
    setTimeout(() => {
      this.getUIContext().getPromptAction().openCustomDialog(node, {
        autoCancel: true,
        alignment: DialogAlignment.Center,
      }).catch((err: BusinessError) => {
        console.error(`openCustomDialog(移动文件夹) 失败 code=${err.code} msg=${err.message}`);
        this.moveFolderNode = null;
      });
    }, DIALOG_DELAY_AFTER_MENU);
  }

  /* 移动对话：弹出文件夹选择器（ComponentContent 方式，复用 FolderPickerDialog） */
  private async openPicker(conv: Conversation): Promise<void> {
    /* 先释放上次点遮罩关闭后残留的节点，防止内存泄漏 */
    if (this.convPickerNode) {
      this.convPickerNode.dispose();
      this.convPickerNode = null;
    }
    const allFolders = await CategoryRepository.getInstance().getAll();
    const params = new FolderPickerDialogParams();
    params.folders = allFolders;
    params.onSelect = (folderId: string) => {
      this.vm.moveConv(conv, folderId);
    };
    params.onRequestClose = () => {
      this.closeDialog();
    };
    const node = new ComponentContent<FolderPickerDialogParams>(this.getUIContext(),
      wrapBuilder(buildFolderPickerContent), params);
    this.convPickerNode = node;
    /* 延迟打开：等长按菜单（子窗口）关闭动画结束后再弹，否则弹窗会被菜单关闭流程吞掉 */
    setTimeout(() => {
      this.getUIContext().getPromptAction().openCustomDialog(node, {
        autoCancel: true,
        alignment: DialogAlignment.Center,
      }).catch((err: BusinessError) => {
        console.error(`openCustomDialog(移动对话) 失败 code=${err.code} msg=${err.message}`);
        this.convPickerNode = null;
      });
    }, DIALOG_DELAY_AFTER_MENU);
  }

  /* 删除对话（二次确认） */
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
