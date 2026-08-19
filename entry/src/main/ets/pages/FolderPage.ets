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

import { ComponentContent, KeyboardAvoidMode, window } from "@kit.ArkUI";
import { BusinessError } from "@kit.BasicServicesKit";
import { common } from "@kit.AbilityKit";
import { CategoryRepository } from "../database/CategoryRepository";
import { Category } from "../model/Category";
import { Conversation } from "../model/Conversation";
import { Message } from "../model/Message";
import { FolderItem } from "../components/item/FolderItem";
import { EditModeTitleBar } from "../components/common/EditModeTitleBar";
import { EditModeActionBar } from "../components/common/EditModeActionBar";
import { NewFolderFab } from "../components/common/NewFolderFab";
import { ConversationItem } from "../components/item/ConversationItem";
import { EditFolderDialogParams, buildEditFolderContent } from "../components/dialog/EditFolderDialog";
import { FolderPickerDialogParams, buildFolderPickerContent } from "../components/dialog/FolderPickerDialog";
import { RenameDialogParams, buildRenameDialog } from "../components/dialog/RenameInputDialog";
import { showDeleteConfirm, SafeAreaHelper, showToast } from "../common/Utils";
import { DIALOG_DELAY_AFTER_MENU, DIALOG_OFFSET_SLIGHT, DIALOG_OFFSET_TALL, DEFAULT_FOLDER_COLOR } from "../common/AppConstants";
import { FolderParams } from "../model/FolderParams";
import { FolderViewModel } from "../viewmodel/FolderViewModel";
import { ShareSheetPanel, ShareCardData, ShareCardItem } from "../components/panel/ShareSheetPanel";
import { ShareService, ShareFormat } from "../service/ShareService";
import { ConversationRepository } from "../database/ConversationRepository";
import { image } from "@kit.ImageKit";
import { ExportCardLayer, EXPORT_CARD_WIDTH, EXPORT_IMAGE_MAX_ROUNDS, EXPORT_PDF_MAX_ROUNDS } from "../components/export/ExportCardLayer";
import { ExportLoading } from "../components/export/ExportLoading";
import { PdfExporter } from "../service/PdfExporter";
import { ImageMerger, IMAGE_MERGE_MAX_HEIGHT } from "../service/ImageMerger";

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
  private batchMoveNode: ComponentContent<FolderPickerDialogParams> | null = null; // 批量移动对话
  private globalKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.RESIZE; // 记录全局避让模式
  /* 沉浸式系统栏高度（vp，EntryAbility 注入）：aboutToAppear 一次性读取（V2 无 @StorageProp，用 @Local + 手动读取） */
  @Local statusBarHeightVp: number = 0;
  @Local navBarHeightVp: number = 0;
  /* 分享半模态面板状态：sheetShow 控制 bindSheet 显隐（$$ 双向绑定，下滑/点遮罩关闭自动复位） */
  @Local shareSheetShow: boolean = false;
  @Local shareSheetTitle: string = "分享"; // 分享面板标题
  @Local sharePreviewText: string = ""; // 纯文本预览内容
  @Local sharePreviewMarkdown: string = ""; // Markdown 源码预览内容（.md 文件分享）
  @Local sharePreviewHtml: string = ""; // HTML 预览内容
  @Local shareCardData: ShareCardData | null = null; // 图片卡片数据
  /* PDF 导出隐藏层开关：置 true 触发 ExportCardLayer 渲染隐藏分段卡片（页面级组件可截图，
     弹层内截图实测报 100001 不可用），导出完成置 false 卸载 */
  @Local exportShow: boolean = false;
  /* 当前导出格式（图片/PDF）：ExportCardLayer 轮数上限与导出处理分支按此区分 */
  @Local exportFormat: ShareFormat = ShareFormat.PDF;

  aboutToAppear(): void {
    /* 读取系统栏高度（标题栏/底部栏/列表避让用） */
    this.statusBarHeightVp = SafeAreaHelper.getStatusBarHeight();
    this.navBarHeightVp = SafeAreaHelper.getNavBarHeight();
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
        /* 多选编辑模式：标题区改为"已选择 X 项"（与 SideBarPage 共用通用组件） */
        if (this.vm.isEditMode) {
          EditModeTitleBar({
            selectedCount: this.vm.selectedIds.length,
            isAllSelected: this.vm.isAllSelected(),
            onExit: () => {
              this.vm.exitEditMode();
            },
            onToggleSelectAll: () => {
              this.vm.toggleSelectAll();
            },
          })
        } else {
          Row() {
            Row() {
              SymbolGlyph($r("sys.symbol.chevron_left"))
                .fontSize($r('app.float.font_icon_xxl'))
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

            Row(){}.width(40) // 占位符，保持标题居居中
          }
          .width("100%")
          .height(SafeAreaHelper.getTitleBarHeight(this.getUIContext()) + this.statusBarHeightVp)
          .padding({
            top: this.statusBarHeightVp,
            left: $r('app.float.space_lg'),
            right: $r('app.float.space_lg')
          })
          .backgroundColor($r('app.color.title_bar_bg'))
          /* 沉浸式：expandSafeArea 背景向上延伸 + 显式 padding 内容避让（safeAreaPadding 在固定高度组件上失效） */
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
          .border({ width: { bottom: 2 }, color: { bottom: $r('app.color.divider') } })
        }

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
                    isEditMode: this.vm.isEditMode,
                    isSelected: this.vm.selectedIds.indexOf(conv.id) >= 0,
                    onClickItem: (selected: Conversation) => {
                      /* 选中对话 → pop 携带结果，逐层转发给 ChatPage 加载（SideBarPage 的 onPop 负责转发） */
                      this.pathStack.pop(selected);
                    },
                    onSelectChange: (selected: Conversation, checked: boolean) => {
                      this.vm.toggleSelect(selected.id, checked);
                    },
                    onMenuSelect: (selected: Conversation) => {
                      this.vm.enterEditMode(selected.id);
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
                    onMenuShare: (selected: Conversation) => {
                      this.handleShareConversation(selected);
                    },
                  })
                }.width("100%");
              },
              (conv: Conversation) => conv.id + "_" + this.vm.listVersion.toString(),
            )
          }
          .width("100%")
          .layoutWeight(1)
          /* 沉浸式：非编辑态无底部栏，列表底部避让导航条（编辑态由底部操作栏避让，这里不再留白） */
          .padding({
            top: $r('app.float.space_md'),
            bottom: this.vm.isEditMode ? 0 : this.navBarHeightVp,
          })
          .backgroundColor($r('app.color.page_bg'))
          /* 项间自动分割线（与收藏 Tab 一致：文件夹/对话之间都有全宽分割线） */
          .divider({
            strokeWidth: 0.5,
            color: $r('app.color.divider'),
          })
          .edgeEffect(EdgeEffect.Spring);
        }

        /* 多选编辑模式：底部操作栏（与 SideBarPage 共用通用组件，本页恒为收藏页操作） */
        if (this.vm.isEditMode) {
          EditModeActionBar({
            selectedCount: this.vm.selectedIds.length,
            showFavoriteActions: true,
            onDelete: () => {
              this.confirmBatchDelete();
            },
            onUnfavorite: () => {
              this.vm.doBatchUnfavorite();
            },
            onMove: () => {
              this.openBatchMovePicker();
            },
          })
        }
        /* 图片/PDF 导出隐藏层：页面级分段卡片渲染 + 截图（弹层内截图不可用，需在页面组件树中挂载） */
        ExportCardLayer({
          showLayer: this.exportShow,
          cardData: this.shareCardData,
          shareTitle: this.shareSheetTitle,
          maxRounds: this.exportFormat === ShareFormat.IMAGE ? EXPORT_IMAGE_MAX_ROUNDS : EXPORT_PDF_MAX_ROUNDS,
          onSegmentsReady: (segCount: number, segHeights: number[]) => {
            this.doExport(this.exportFormat, segCount, segHeights);
          },
        })
        /* 导出加载层：图片/PDF 生成期间显示 LoadingProgress（exportShow 置 false 自动卸载） */
        if (this.exportShow) {
          ExportLoading()
        }
      }
      .width("100%")
      .height("100%")
      .backgroundColor($r('app.color.page_bg'))
      /* 悬浮新建子文件夹按钮（右下角） */
      .overlay(this.fabBuilder(), {
        align: Alignment.BottomEnd,
      })
      /* 分享半模态面板（预览 + 格式选择 + 分享按钮）：弹层生命周期与页面绑定，onDisappear 兜底复位 */
      .bindSheet($$this.shareSheetShow, this.shareSheetContent(), {
        height: this.shareSheetHeight(),
        dragBar: false,
        showClose: false,
        backgroundColor: $r('app.color.dialog_bg'),
        onDisappear: () => {
          this.shareSheetShow = false;
        },
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
    .onBackPressed(() => {
      /* 导出加载期间：拦截返回键，避免导出中断或页面 pop 后分享弹窗错位 */
      if (this.exportShow) {
        return true; // true = 本页自行处理返回键，框架不再执行默认弹栈
      }
      /* 多选编辑模式：系统返回键优先退出编辑模式（拦截本次返回），再按一次才真正返回上级 */
      if (this.vm.isEditMode) {
        this.vm.exitEditMode();
        return true; // true = 本页自行处理返回键，框架不再执行默认弹栈
      }
      return false; // 非编辑模式：交还默认弹栈逻辑返回上一级
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
      NewFolderFab({
        visible: !this.vm.isEditMode,
        onAddClick: () => {
          this.openNewFolderDialog();
        },
      })
    }
    .width("100%")
    .height("100%")
    .align(Alignment.BottomEnd) // 按钮定位到底部，margin 提供外边距
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
    const n6 = this.batchMoveNode;
    if (n6) {
      this.batchMoveNode = null;
      this.closeContentNode(n6);
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

  /* 批量移动对话：弹出文件夹选择器（ComponentContent 方式，复用 FolderPickerDialog，多选编辑模式） */
  private async openBatchMovePicker(): Promise<void> {
    /* 先释放上次点遮罩关闭后残留的节点，防止内存泄漏 */
    if (this.batchMoveNode) {
      this.batchMoveNode.dispose();
      this.batchMoveNode = null;
    }
    const allFolders = await CategoryRepository.getInstance().getAll();
    const params = new FolderPickerDialogParams();
    params.title = "批量移动到文件夹";
    params.folders = allFolders;
    params.onSelect = (folderId: string) => {
      this.vm.doBatchMove(folderId);
    };
    params.onRequestClose = () => {
      this.closeDialog();
    };
    const node = new ComponentContent<FolderPickerDialogParams>(this.getUIContext(),
      wrapBuilder(buildFolderPickerContent), params);
    this.batchMoveNode = node;
    /* 该弹窗由底部编辑栏"移动"按钮触发（非菜单），无需延迟，直接打开 */
    this.getUIContext().getPromptAction().openCustomDialog(node, {
      autoCancel: true,
      alignment: DialogAlignment.Center,
    }).catch((err: BusinessError) => {
      console.error(`openCustomDialog(批量移动) 失败 code=${err.code} msg=${err.message}`);
      this.batchMoveNode = null;
    });
  }

  /* 批量删除对话（二次确认） */
  private confirmBatchDelete(): void {
    if (this.vm.selectedIds.length === 0) return;
    showDeleteConfirm(
      this.getUIContext(),
      "删除对话",
      `确定删除选中的 ${this.vm.selectedIds.length} 个对话吗？删除后不可恢复。`,
      () => {
        this.vm.doBatchDelete();
      },
    );
  }

  /* ===== 分享对话（与 SideBarPage 逻辑一致，复用 ShareSheetPanel 半模态面板）===== */

  /**
   * 分享整段对话：加载消息 → 打开分享半模态面板（预览 + 选格式）
   */
  private async handleShareConversation(conv: Conversation): Promise<void> {
    const title = conv.title.length > 0 ? conv.title : "新对话";
    /* 先立即弹出面板（标题先行），不等待数据库读取与预览生成：
       超长对话 getMessages 读库+反序列化耗时可达秒级，若在弹出前 await 会阻塞 UI 线程，
       表现为"点分享后过一会才出面板"。先弹，再异步取消息、生成预览后填充 */
    this.shareSheetTitle = title;
    this.shareSheetShow = true;
    const messages = await ConversationRepository.getInstance().getMessages(conv.id);
    if (messages.length === 0) {
      console.error(`handleShareConversation: 对话 ${conv.id} 无消息`);
      this.shareSheetShow = false; // 无内容可分享，关闭已弹出的面板
      return;
    }
    /* 生成纯文本 / Markdown / HTML 预览 + 图片卡片数据：marked 解析为同步 CPU 密集操作，
       先让出执行权（setTimeout 0）使面板首帧正常渲染，再异步填充预览，避免刚弹出的面板被卡顿 */
    setTimeout(() => {
      this.sharePreviewText = ShareService.formatConversationAsText(messages, title);
      this.sharePreviewMarkdown = ShareService.formatConversationAsMarkdown(messages, title);
      this.sharePreviewHtml = ShareService.formatConversationAsHtml(messages, title);
      this.shareCardData = this.buildCardData(messages, title);
    }, 0);
  }

  /**
   * 分享整段对话：按用户选择格式调用系统分享面板
   * @param format 分享格式（纯文本 / HTML / 图片 / PDF）
   * @param pixelMap 图片格式时由面板 componentSnapshot 截取的 PixelMap
   * @param pdfPath PDF 格式时由面板 PdfExporter 生成的 PDF 文件路径
   */
  private doShareConversation(format: ShareFormat, pixelMap?: image.PixelMap, pdfPath?: string): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (format === ShareFormat.IMAGE && pixelMap !== undefined) {
      /* 图片：导出 PNG 文件后按图片分享 */
      ShareService.sharePixelMap(context, pixelMap, this.shareSheetTitle);
    } else if (format === ShareFormat.PDF && pdfPath !== undefined) {
      /* PDF：直接分享 PdfExporter 生成的 PDF 文件 */
      ShareService.sharePdfFile(context, pdfPath, this.shareSheetTitle);
    } else if (format === ShareFormat.HTML) {
      ShareService.share(context, this.sharePreviewHtml, ShareFormat.HTML, this.shareSheetTitle);
    } else if (format === ShareFormat.MARKDOWN) {
      /* Markdown：生成 .md 文件后按文件分享（保留原始标记） */
      ShareService.share(context, this.sharePreviewMarkdown, ShareFormat.MARKDOWN, this.shareSheetTitle);
    } else {
      ShareService.share(context, this.sharePreviewText, ShareFormat.PLAIN_TEXT, this.shareSheetTitle);
    }
    /* 分享面板已拉起，关闭预览半模态 */
    this.shareSheetShow = false;
  }

  /**
   * 组装图片卡片数据：消息列表 → 角色 + 内容（用户消息纯文本；AI 消息保留 Markdown 原文，
   * 由卡片内 Markdown 组件渲染，分享图片中 AI 回复呈现原始富文本格式）
   */
  private buildCardData(messages: Message[], title: string): ShareCardData {
    const items: ShareCardItem[] = messages.map((m: Message): ShareCardItem => {
      const item: ShareCardItem = {
        role: m.isUser() ? 'user' : 'assistant',
        content: m.content,
      };
      return item;
    });
    return { title: title, items: items };
  }

  /* 分享半模态面板内容：预览 + 格式选择 + 分享按钮 */
  @Builder
  shareSheetContent() {
    ShareSheetPanel({
      previewText: this.sharePreviewText,
      previewMarkdown: this.sharePreviewMarkdown,
      previewHtml: this.sharePreviewHtml,
      cardData: this.shareCardData,
      shareTitle: this.shareSheetTitle,
      onShare: (format: ShareFormat, pixelMap?: image.PixelMap, pdfPath?: string) => {
        this.doShareConversation(format, pixelMap, pdfPath);
      },
      onExportRequest: (format: ShareFormat) => {
        this.handleExportRequest(format);
      },
      onClose: () => {
        this.shareSheetShow = false;
      },
    })
  }

  /**
   * 面板图片/PDF 导出请求：记录导出格式并置 exportShow 触发 ExportCardLayer
   * 渲染隐藏分段卡片（弹层内截图不可用，改由页面级组件截图；面板点击后已自行关闭）
   */
  private handleExportRequest(format: ShareFormat): void {
    if (format === ShareFormat.IMAGE || format === ShareFormat.PDF) {
      this.exportFormat = format;
      this.exportShow = true;
    }
  }

  /**
   * 图片/PDF 导出：ExportCardLayer 各段渲染稳定后回调，页面级逐段 get(id) 截图，
   * 段高超限时按比例缩小（scale）兜底，然后：
   *  - 图片：ImageMerger 纵向拼接为一张长图，写 PNG 文件后按图片分享；
   *  - PDF：PdfExporter 铺入多页 A4 PDF，完成后走既有 doShareConversation 拉起系统分享
   */
  private async doExport(format: ShareFormat, segCount: number, segHeights: number[]): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const snap = this.getUIContext().getComponentSnapshot();
    const segments: image.PixelMap[] = [];
    try {
      for (let i = 0; i < segCount; i++) {
        /* 段高（vp）换算物理像素：超 15000px 则动态缩小 scale（等比），避免超截图渲染缓冲上限 */
        let scale: number = 1;
        const hPx: number = this.getUIContext().vp2px(segHeights[i] || 0);
        if (hPx > 15000) {
          scale = 15000 / hPx;
        }
        const pm: image.PixelMap = await snap.get(`exportCard_${i}`, { waitUntilRenderFinished: true, scale: scale });
        if (pm === undefined || pm === null) {
          throw new Error(`exportCard_${i} snapshot undefined`);
        }
        segments.push(pm);
      }
      if (format === ShareFormat.IMAGE) {
        /* 图片：各段纵向拼接为长图（内部按 targetWidth 对齐、超高超限缩小并释放各段），
           拼接完成后写 PNG 分享，再释放拼接结果 */
        const merged: image.PixelMap = await ImageMerger.mergeVertical(
          segments, this.getUIContext().vp2px(EXPORT_CARD_WIDTH), IMAGE_MERGE_MAX_HEIGHT);
        await ShareService.sharePixelMap(context, merged, this.shareSheetTitle);
        merged.release();
      } else {
        const pdfPath: string = await PdfExporter.exportSegments(context, segments, this.shareSheetTitle);
        this.doShareConversation(ShareFormat.PDF, undefined, pdfPath);
      }
      this.exportShow = false;
    } catch (e) {
      const err: Error = e as Error;
      console.error(`FolderPage export FAILED: ${err.message}`);
      this.exportShow = false;
      showToast($r('app.string.share_snapshot_failed'));
    }
  }

  /** 分享半模态面板高度（vp）：撑满窗口（窗口高 - 状态栏 - 标题栏），复用 Utils 统一计算 */
  private shareSheetHeight(): number {
    return SafeAreaHelper.getSheetHeight(this.getUIContext());
  }
}
