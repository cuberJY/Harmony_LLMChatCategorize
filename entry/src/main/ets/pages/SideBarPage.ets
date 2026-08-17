/**
 * 侧边栏页面（SideBarPage）
 * 视觉上与侧边栏类似，作为独立页面存在
 * 从 ChatPage 点击左上角按钮 或 左边缘右滑 进入
 *
 * Navigation 路由重构
 * - 不再作为 @Entry 页面，由 HomePage 的 Navigation 以 NavDestination 形式承载
 * - 路由：顶部返回 / 选中对话 pop(conv) 回传；进入 FolderPage / SettingsPage 用 pushPathByName
 * - 返回刷新：NavDestination.onShown 替代原 onPageShow
 *
 * 结构（从上到下）：
 *  顶部栏  [收藏] [历史]              ← 返回
 *  内容区  收藏Tab → 文件夹列表（先空态占位）
 *         历史Tab → 搜索框入口（点击弹出搜索面板）+ 按时间分组的历史对话列表
 *  底部    设置按钮
 */

import { ComponentContent, KeyboardAvoidMode, window } from "@kit.ArkUI";
import { BusinessError } from "@kit.BasicServicesKit";
import { common } from "@kit.AbilityKit";
import { Category } from "../model/Category";
import { FolderItem } from "../components/item/FolderItem";
import { EditFolderDialogParams, buildEditFolderContent } from "../components/dialog/EditFolderDialog";
import { FolderPickerDialogParams, buildFolderPickerContent } from "../components/dialog/FolderPickerDialog";
import { DatabaseHelper } from "../database/DatabaseHelper";
import { CategoryRepository } from "../database/CategoryRepository";
import { ConversationItem } from "../components/item/ConversationItem";
import { EditModeTitleBar } from "../components/common/EditModeTitleBar";
import { EditModeActionBar } from "../components/common/EditModeActionBar";
import { NewFolderFab } from "../components/common/NewFolderFab";
import { RenameDialogParams, buildRenameDialog } from "../components/dialog/RenameInputDialog";
import { showDeleteConfirm, SafeAreaHelper } from "../common/Utils";
import { DIALOG_DELAY_AFTER_MENU, DIALOG_OFFSET_SLIGHT, DIALOG_OFFSET_TALL, DEFAULT_FOLDER_COLOR } from "../common/AppConstants";
import { NavTransitionManager } from "../common/NavTransitionManager";
import { FolderParams } from "../model/FolderParams";
import { Conversation, ConversationSelection } from "../model/Conversation";
import { SideBarViewModel, GroupItem } from "../viewmodel/SideBarViewModel";
import { SearchSheetPanel } from "../components/panel/SearchSheetPanel";
import { SearchViewModel } from "../viewmodel/SearchViewModel";

@ComponentV2
export struct SideBarPage {
  /* 路由栈（NavDestination.onReady 获取）：跳转 FolderPage/SettingsPage 并转发返回结果 */
  private pathStack: NavPathStack = new NavPathStack();
  /* 当前打开的对话 id（来自 ChatPage 路由参数，用于历史列表高亮当前对话） */
  @Param currentConversationId: string = "";
  /* 转场位移动画状态：百分比字符串，绑定 NavDestination.translate（由转场回调驱动） */
  @Local offsetX: string = "0%";
  /* 本页在路由栈中的索引（注册/注销转场回调用，onReady 时确定） */
  private transitionIndex: number = -1;
  /* 数据与业务逻辑（@Trace 状态 + 分组 + 编辑模式）全部收敛到 ViewModel，页面只保留 build / 路由 / 弹窗 */
  private vm: SideBarViewModel = new SideBarViewModel();
  /* 搜索面板状态：sheetShow 控制 bindSheet 显隐（$$ 双向绑定，下滑/点遮罩关闭自动复位）；searchVm 常驻，面板关闭再打开状态保留 */
  @Local searchSheetShow: boolean = false;
  private searchVm: SearchViewModel = new SearchViewModel();
  /* 沉浸式系统栏高度（vp，EntryAbility 注入）：aboutToAppear 一次性读取（V2 无 @StorageProp，用 @Local + 手动读取） */
  @Local statusBarHeightVp: number = 0;
  @Local navBarHeightVp: number = 0;

  /* 重命名弹窗的内容节点（ComponentContent 方式）：非空表示已打开或残留待清理 */
  private renameDialogNode: ComponentContent<RenameDialogParams> | null = null;
  /* 收藏位置选择弹窗的内容节点（ComponentContent 方式） */
  private favoritePickerNode: ComponentContent<FolderPickerDialogParams> | null = null;
  /* 新建文件夹弹窗的内容节点（ComponentContent 方式） */
  private newFolderDialogNode: ComponentContent<EditFolderDialogParams> | null = null;
  /* 编辑文件夹弹窗的内容节点（ComponentContent 方式） */
  private editFolderNode: ComponentContent<EditFolderDialogParams> | null = null;
  /* 移动文件夹弹窗的内容节点（ComponentContent 方式） */
  private moveFolderNode: ComponentContent<FolderPickerDialogParams> | null = null;
  /* 移动对话弹窗的内容节点（ComponentContent 方式） */
  private convPickerNode: ComponentContent<FolderPickerDialogParams> | null = null;
  /* 批量移动弹窗的内容节点（ComponentContent 方式） */
  private batchMoveNode: ComponentContent<FolderPickerDialogParams> | null = null;
  private globalKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.RESIZE; // 记录全局避让模式
  private swiperController: SwiperController = new SwiperController(); // Swiper 控制器：程序化带动画切换

  aboutToAppear(): void {
    /* 读取系统栏高度（标题栏/底部栏/内容区避让用） */
    this.statusBarHeightVp = SafeAreaHelper.getStatusBarHeight();
    this.navBarHeightVp = SafeAreaHelper.getNavBarHeight();
    /* 记住全局模式（EntryAbility 里设的 RESIZE），本页切换为 NONE：键盘不顶起底部"设置" */
    this.globalKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    /* 初始化数据库（单例已初始化则跳过） */
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context) {
      DatabaseHelper.getInstance()
        .init(context)
        .then(() => {
          this.vm.loadConversations();
          this.vm.loadFavorites();
        });
    }
  }

  aboutToDisappear(): void {
    /* 离开页面恢复全局模式，保证 ChatPage 底部输入框的避让不受影响 */
    this.getUIContext().setKeyboardAvoidMode(this.globalKeyboardAvoidMode);
    /* 注销转场动画回调 */
    if (this.transitionIndex >= 0) {
      NavTransitionManager.getInstance().unregister(this.transitionIndex);
      this.transitionIndex = -1;
    }
  }

  /* 搜索面板内容：SearchSheetPanel 组件（vm 常驻共享，选中对话回传并关闭面板） */
  @Builder
  searchSheetContent() {
    SearchSheetPanel({
      vm: this.searchVm,
      onSelectConversation: (selected: Conversation, messageId: string) => {
        /* 选中搜索结果：关闭面板 + 携带对话与定位消息返回 ChatPage（本页即由 ChatPage push 而来） */
        this.searchSheetShow = false;
        const selection: ConversationSelection = { conv: selected, focusMessageId: messageId };
        this.pathStack.pop(selection);
      },
    })
  }

  /**
   * 搜索面板高度：撑满窗口（窗口高度 - 状态栏 - 标题栏），形式与 ChatPage 的半模态面板一致
   * 窗口/状态栏为 px，统一转 vp
   */
  private searchSheetHeight(): number {
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (host === undefined || host.windowStage === undefined) {
        return 500; // 兜底高度
      }
      /* 标题栏高度（float 资源带 'vp' 单位，getNumber 返回 px，需转回 vp） */
      const titleBarHeightPx = host.resourceManager.getNumber($r('app.float.title_bar_height').id);
      const titleBarHeight = this.getUIContext().px2vp(titleBarHeightPx);
      const win = host.windowStage.getMainWindowSync();
      /* 窗口总高度（px） */
      const windowHeightPx = win.getWindowProperties().windowRect.height;
      /* 状态栏（顶部安全区）高度（px），非沉浸式窗口时为 0 */
      const safeTopPx = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
      const windowHeight = this.getUIContext().px2vp(windowHeightPx);
      const safeTop = this.getUIContext().px2vp(safeTopPx);
      return Math.max(200, windowHeight - safeTop - titleBarHeight);
    } catch (e) {
      return 500; // 异常兜底，保证面板可显示
    }
  }

  build() {
    NavDestination() {
      Column() {
        /* 顶部栏：Tab 切换 + 返回 */
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
              SymbolGlyph($r("sys.symbol.gearshape"))
                .fontSize($r('app.float.font_icon_xxl'))
                .fontWeight(700)
                .fontColor([$r('app.color.text_primary')])
            }
            .width(40)
            .layoutWeight(1)
            .onClick(() => {
              this.pathStack.pushPathByName("SettingsPage", undefined);
            });
            
            /* Tab 容器（左对齐） */
            Row() {
              /* 「历史」Tab（index 0，默认页） */
              Text("历史")
                .fontSize($r('app.float.font_toggle'))
                .fontColor(
                  this.vm.currentTab === 0 ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'),
                )
                .fontWeight(this.vm.currentTab === 0 ? 700 : 400)
                .padding({
                  left: $r('app.float.space_md'),
                  right: $r('app.float.space_md'),
                  top: $r('app.float.space_xs'),
                  bottom: $r('app.float.space_xs'),
                })
                .backgroundColor(this.vm.currentTab === 0 ? $r('app.color.toggle_bg_active') : Color.Transparent)
                .height(36)
                .borderRadius(18)
                .onClick(() => {
                  this.switchTab(0);
                })

              /* 「收藏」Tab（index 1） */
              Text("收藏")
                .fontSize($r('app.float.font_toggle'))
                .fontColor(
                  this.vm.currentTab === 1 ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'),
                )
                .fontWeight(this.vm.currentTab === 1 ? 700 : 400)
                .padding({
                  left: $r('app.float.space_md'),
                  right: $r('app.float.space_md'),
                  top: $r('app.float.space_xs'),
                  bottom: $r('app.float.space_xs'),
                })
                .backgroundColor(this.vm.currentTab === 1 ? $r('app.color.toggle_bg_active') : Color.Transparent)
                .height(36)
                .borderRadius(18)
                .onClick(() => {
                  this.switchTab(1);
                })
            }

            .alignItems(VerticalAlign.Center)

            Row() {
              SymbolGlyph($r("sys.symbol.magnifyingglass"))
                .fontSize($r('app.float.font_icon_xxl'))
                .fontWeight(700)
                .fontColor([$r('app.color.text_primary')])
                .margin({
                  left: $r('app.float.space_md'),
                  right: $r('app.float.space_md'),
                })
                .onClick(() => {
                  /* 打开搜索面板（从下方弹出）：每次弹出刷新数据源，搜索状态由常驻 searchVm 保留 */
                  this.searchSheetShow = true;
                  this.searchVm.loadConversations();
                })
                /* 半模态搜索面板：从下方弹出，无标题栏（形式同 ChatPage 的网页/文本面板） */
                .bindSheet($$this.searchSheetShow, this.searchSheetContent(), {
                  height: this.searchSheetHeight(),
                  dragBar: false,
                  showClose: false,
                  backgroundColor: $r('app.color.dialog_bg'),
                  onDisappear: () => {
                    this.searchSheetShow = false;
                  },
                });
              SymbolGlyph($r("sys.symbol.ellipsis_message"))
                .fontSize($r('app.float.font_icon_xxl'))
                .fontWeight(700)
                .fontColor([$r('app.color.text_primary')])
                .margin({
                  left: $r('app.float.space_md'),
                })
                .onClick(() => {
                  this.pathStack.pop();
                })
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.End)
          }
          .width("100%")
          .height(SafeAreaHelper.getTitleBarHeight(this.getUIContext()) + this.statusBarHeightVp)
          .padding({
            top: this.statusBarHeightVp,
            left: $r('app.float.space_lg'),
            right: $r('app.float.space_xl')
          })
          .backgroundColor($r('app.color.title_bar_bg'))
          /* 沉浸式：expandSafeArea 背景向上延伸 + 显式 padding 内容避让（safeAreaPadding 在固定高度组件上失效） */
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
          .border({
            width: { bottom: 2 },
            color: { bottom: $r('app.color.divider') },
          });
        }

        /* 内容区：Swiper 左右滑动切换 Tab（历史左、收藏右），控制器供 Tab 点击时 changeIndex 带动画切换 */
        Swiper(this.swiperController) {
          /* 历史 Tab */
          Column() {
            if (this.vm.groups.length === 0) {
              Column() {
                Text("暂无历史对话")
                  .fontSize($r('app.float.font_remind'))
                  .fontColor($r('app.color.text_secondary'))
              }
              .width("100%")
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center);
            } else {
              List() {
                /* 遍历分组：每组先渲染组标题，再渲染该组对话 */
                ForEach(
                  this.vm.groups,
                  (group: GroupItem) => {
                    /* 时间组标题（左对齐） */
                    ListItem() {
                      Text(group.name)
                        .fontSize($r('app.float.font_time'))
                        .fontColor($r('app.color.text_secondary'))
                        .width("100%")
                        .textAlign(TextAlign.Start)
                        .padding({
                          left: $r('app.float.space_lg'),
                          right: $r('app.float.space_xl'),
                          top: $r('app.float.space_md'),
                          bottom: $r('app.float.space_xs'),
                        })
                    };

                    /* 该组下的对话 */
                    ForEach(
                      group.conversations,
                      (conv: Conversation) => {
                        ListItem() {
                          ConversationItem({
                            conversation: conv,
                            isEditMode: this.vm.isEditMode,
                            isSelected: this.vm.selectedIds.indexOf(conv.id) >= 0,
                            /* 是否为当前对话（高亮显示） */
                            isCurrent: conv.id === this.currentConversationId,
                            /* 历史页：星标显示在行尾；不显示"移动"（未收藏对话不参与文件夹分类） */
                            showMoveMenu: false,

                            onClickItem: (selected: Conversation) => {
                              /* 选中对话 → pop 携带结果返回 ChatPage（pushPathByName 的 onPop 接收） */
                              this.pathStack.pop(selected);
                            },
                            onSelectChange: (selected: Conversation, checked: boolean) => {
                              this.vm.toggleSelect(selected.id, checked);
                            },
                            onMenuRename: (selected: Conversation) => {
                              this.openRenameDialog(selected);
                            },
                            onMenuDelete: (selected: Conversation) => {
                              this.confirmDeleteSingle(selected);
                            },
                            onMenuSelect: (selected: Conversation) => {
                              this.vm.enterEditMode(selected.id);
                            },
                            onMenuFavorite: (selected: Conversation) => {
                              this.onFavoriteAction(selected);
                            },
                          })
                        }.width("100%");
                      },
                      (conv: Conversation) => conv.id + "_" + this.vm.listVersion.toString(),
                    );
                  },
                  (group: GroupItem) => group.name + "_" + this.vm.listVersion.toString(),
                )
              }
              .width("100%")
              .layoutWeight(1)
              .backgroundColor($r('app.color.page_bg'))
            }
          }
          .width("100%")
          .height("100%")

          /* 收藏 Tab */
          Stack() {
            if (this.vm.topFolders.length === 0 && this.vm.uncategorizedConvs.length === 0) {
              Column() {
                Text("暂无收藏")
                  .fontSize($r('app.float.font_remind'))
                  .fontColor($r('app.color.text_secondary'))
              }
              .width("100%")
              .height("100%")
              .justifyContent(FlexAlign.Center);
            } else {
              List() {
                /* 顶级文件夹 */
                ForEach(
                  this.vm.topFolders,
                  (cat: Category) => {
                    ListItem() {
                      FolderItem({
                        category: cat,
                        onClickItem: (selected: Category) => {
                          /* 点击 → 进入 FolderPage；onPop 转发 FolderPage 返回的选中对话给 ChatPage */
                          this.pathStack.pushPathByName(
                            "FolderPage",
                            new FolderParams(selected.id, selected.name),
                            (popInfo: PopInfo) => {
                              const conv = popInfo.result as Conversation | undefined;
                              if (conv && conv.id.length > 0) {
                                /* 文件夹页选中对话 → 继续 pop 回 ChatPage 并携带结果 */
                                this.pathStack.pop(conv);
                              }
                            },
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
                          this.confirmFolderDelete(selected);
                        },
                      })
                    }.width("100%");
                  },
                  (cat: Category) => cat.id + "_" + this.vm.listVersion.toString(),
                )

                /* 未分类对话（category_id 为空） */
                ForEach(
                  this.vm.uncategorizedConvs,
                  (conv: Conversation) => {
                    ListItem() {
                      ConversationItem({
                        conversation: conv,
                        isEditMode: this.vm.isEditMode,
                        isSelected: this.vm.selectedIds.indexOf(conv.id) >= 0,
                        /* 收藏页：不显示星标（该页全是已收藏对话）；保留"移动"菜单调整位置 */
                        showFavoriteIcon: false,
                        showPinMenu: true,

                        onClickItem: (selected: Conversation) => {
                          /* 直接进入对话 → pop 携带结果返回 ChatPage */
                          this.pathStack.pop(selected);
                        },
                        onSelectChange: (selected: Conversation, checked: boolean) => {
                          this.vm.toggleSelect(selected.id, checked);
                        },
                        onMenuRename: (selected: Conversation) => {
                          this.openRenameDialog(selected);
                        },
                        onMenuPin: (selected: Conversation) => {
                          this.vm.togglePinConv(selected);
                        },
                        onMenuDelete: (selected: Conversation) => {
                          this.confirmDeleteSingle(selected);
                        },
                        onMenuMove: (selected: Conversation) => {
                          this.openConvPicker(selected);
                        },
                        onMenuSelect: (selected: Conversation) => {
                          this.vm.enterEditMode(selected.id);
                        },
                        onMenuFavorite: (selected: Conversation) => {
                          this.onFavoriteAction(selected);
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
              /* 项间自动分割线（与历史 Tab 一致：文件夹/对话之间都有全宽分割线） */
              .divider({
                strokeWidth: 0.5,
                color: $r('app.color.divider'),
              })
              .edgeEffect(EdgeEffect.Spring);
            }

            /* 悬浮新建按钮（右下角，多选编辑模式隐藏避免遮挡底部操作栏） */
            NewFolderFab({
              visible: !this.vm.isEditMode,
              onAddClick: () => {
                this.openNewFolderDialog();
              },
            })
          }
          .width("100%")
          .height("100%")
          .align(Alignment.BottomEnd)
          .hitTestBehavior(HitTestMode.None);
        }
        .layoutWeight(1)
        .width("100%")
        /* 沉浸式：非编辑态无底部栏，内容区底部避让导航条（编辑态由底部操作栏避让，这里不再留白） */
        .padding({ bottom: this.vm.isEditMode ? 0 : this.navBarHeightVp })
        .duration(150) // 动画时长 150ms（对 changeIndex 与手势滑动都生效）
        .curve(Curve.EaseOut)
        .loop(false)
        .disableSwipe(this.vm.isEditMode) // 多选编辑模式下禁止滑动，避免误操作
        .indicator(false) // 隐藏底部圆点指示器
        .onChange((index: number) => {
          if (index === 0 && this.vm.currentTab !== 0) {
            this.vm.listVersion++;
          }
          this.vm.setCurrentTab(index); // 滑动后同步状态，Tab 栏高亮跟随变化
        })

        /* 底部 */
        if (this.vm.isEditMode) {
          EditModeActionBar({
            selectedCount: this.vm.selectedIds.length,
            showFavoriteActions: this.vm.currentTab === 1,
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
      }
      .width("100%")
      .height("100%")
      .backgroundColor($r('app.color.page_bg'));
    }
    .hideTitleBar(true)
    /* 转场位移：由 HomePage 的 customNavContentTransition 通过动画回调驱动（0% 时无偏移） */
    .translate({ x: this.offsetX })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      /* 注册转场动画回调：本页在路由栈中的索引 = 当前栈内页面数 - 1 */
      this.transitionIndex = this.pathStack.getAllPathName().length - 1;
      NavTransitionManager.getInstance().register(this.transitionIndex, {
        start: (isPush: boolean, isExit: boolean) => {
          /* 初始位置：作为 to（打开侧边栏）先位于左侧屏外；作为 from（关闭侧边栏）留在原位 */
          this.offsetX = isExit ? "0%" : "-100%";
        },
        finish: (isPush: boolean, isExit: boolean) => {
          /* 目标位置：作为 to 左滑入原位；作为 from 左滑出屏幕 */
          this.offsetX = isExit ? "-100%" : "0%";
        },
        onFinish: () => {
          /* 动画结束重置，供下次转场使用 */
          this.offsetX = "0%";
        },
      });
    })
    .onShown(() => {
      /* 返回时刷新数据（收藏/历史可能已变）；兜底纠正上层页面改过的全局键盘模式为 NONE */
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
      this.vm.loadConversations();
      this.vm.loadFavorites();
      this.vm.listVersion++;
    })
    .onBackPressed(() => {
      /* 多选编辑模式：系统返回键优先退出编辑模式（拦截本次返回），再按一次才真正返回 ChatPage */
      if (this.vm.isEditMode) {
        this.vm.exitEditMode();
        return true; // true = 本页自行处理返回键，框架不再执行默认弹栈
      }
      return false; // 非编辑模式：交还默认弹栈逻辑返回 ChatPage
    })
  }

  /**
   * 顶部 Tab 点击切换
   * 同时更新高亮状态 + 通过控制器带动画滑动，避免与手势滑动互相干扰
   * @param index 目标 Tab：0=历史 1=收藏
   */
  private switchTab(index: number): void {
    if (this.vm.currentTab === index) return;
    this.vm.setCurrentTab(index); // 先更新高亮
    this.swiperController.changeIndex(index, true); // 带动画滑动到目标页
  }

  /* 重命名：弹出输入对话框（ComponentContent 方式，内容与页面解耦） */
  private openRenameDialog(conv: Conversation): void {
    /* 上一次弹窗若通过点遮罩（autoCancel）自动关闭，节点会残留，先释放避免内存泄漏 */
    if (this.renameDialogNode) {
      this.renameDialogNode.dispose();
      this.renameDialogNode = null;
    }
    /* 组装弹窗参数与回调（onConfirm 在弹窗"确定"时回调，闭包内 this 仍指向本页面） */
    const params = new RenameDialogParams();
    params.title = "重命名对话";
    params.oldValue = conv.title;
    params.onConfirm = (newTitle: string) => {
      this.vm.doRename(conv.id, newTitle);
    };
    params.onRequestClose = () => {
      this.closeDialog();
    };

    /* ComponentContent：内容绑定本页面 UIContext，但组件实例独立，规避成员 @Builder 的时序/绑定问题 */
    const node = new ComponentContent<RenameDialogParams>(this.getUIContext(),
      wrapBuilder(buildRenameDialog), params);
    this.renameDialogNode = node;
    /* 延迟打开：等长按菜单（子窗口）关闭动画结束后再弹，否则弹窗会被菜单关闭流程吞掉 */
    setTimeout(() => {
      this.getUIContext().getPromptAction().openCustomDialog(node, {
        autoCancel: true,
        alignment: DialogAlignment.Center,
        offset: DIALOG_OFFSET_SLIGHT,
      }).catch((err: BusinessError) => {
        /* 失败静默正是"按钮无效"的主要嫌疑，这里打日志暴露真实错误码 */
        console.error(`openCustomDialog(重命名) 失败 code=${err.code} msg=${err.message}`);
        this.renameDialogNode = null;
      });
    }, DIALOG_DELAY_AFTER_MENU);
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
    /* 1) ComponentContent 方式的弹窗（重命名/收藏/新建文件夹，同一时刻只会有一个节点非空） */
    const renameNode = this.renameDialogNode;
    if (renameNode) {
      this.renameDialogNode = null;
      this.closeContentNode(renameNode);
    }
    const favNode = this.favoritePickerNode;
    if (favNode) {
      this.favoritePickerNode = null;
      this.closeContentNode(favNode);
    }
    const newFolderNode = this.newFolderDialogNode;
    if (newFolderNode) {
      this.newFolderDialogNode = null;
      this.closeContentNode(newFolderNode);
    }
    const editFolderNode = this.editFolderNode;
    if (editFolderNode) {
      this.editFolderNode = null;
      this.closeContentNode(editFolderNode);
    }
    const moveFolderNode = this.moveFolderNode;
    if (moveFolderNode) {
      this.moveFolderNode = null;
      this.closeContentNode(moveFolderNode);
    }
    const convPickerNode = this.convPickerNode;
    if (convPickerNode) {
      this.convPickerNode = null;
      this.closeContentNode(convPickerNode);
    }
    const batchMoveNode = this.batchMoveNode;
    if (batchMoveNode) {
      this.batchMoveNode = null;
      this.closeContentNode(batchMoveNode);
    }
  }

  /**
   * 长按菜单-收藏/取消收藏（历史 Tab 与收藏 Tab 共用）
   * 未收藏 → 弹出选择收藏位置；已收藏 → 直接取消收藏
   */
  private onFavoriteAction(conv: Conversation): void {
    if (conv.isFavorite) {
      this.vm.doUnfavorite(conv);
    } else {
      this.openFavoritePicker(conv);
    }
  }

  /* 收藏：弹出收藏位置选择器（ComponentContent 方式，内容与页面解耦） */
  private async openFavoritePicker(conv: Conversation): Promise<void> {
    /* 上一次弹窗若通过点遮罩（autoCancel）自动关闭，节点会残留，先释放避免内存泄漏 */
    if (this.favoritePickerNode) {
      this.favoritePickerNode.dispose();
      this.favoritePickerNode = null;
    }
    const allFolders = await CategoryRepository.getInstance().getAll();
    /* 组装弹窗参数与回调（onSelect 在弹窗选中"默认"或某个文件夹时回调） */
    const params = new FolderPickerDialogParams();
    params.title = "选择收藏位置";
    params.folders = allFolders;
    params.onSelect = (folderId: string) => {
      this.vm.doFavorite(conv, folderId);
    };
    params.onRequestClose = () => {
      this.closeDialog();
    };

    const node = new ComponentContent<FolderPickerDialogParams>(this.getUIContext(),
      wrapBuilder(buildFolderPickerContent), params);
    this.favoritePickerNode = node;
    /* 延迟打开：等长按菜单（子窗口）关闭动画结束后再弹，否则弹窗会被菜单关闭流程吞掉 */
    setTimeout(() => {
      this.getUIContext().getPromptAction().openCustomDialog(node, {
        autoCancel: true,
        alignment: DialogAlignment.Center,
      }).catch((err: BusinessError) => {
        /* 失败静默正是"按钮无效"的主要嫌疑，这里打日志暴露真实错误码 */
        console.error(`openCustomDialog(收藏) 失败 code=${err.code} msg=${err.message}`);
        this.favoritePickerNode = null;
      });
    }, DIALOG_DELAY_AFTER_MENU);
  }

  /* 新建顶级文件夹对话框（ComponentContent 方式，复用 EditFolderDialog：名称 + 颜色） */
  private openNewFolderDialog(): void {
    /* 先释放上次点遮罩关闭后残留的节点 */
    if (this.newFolderDialogNode) {
      this.newFolderDialogNode.dispose();
      this.newFolderDialogNode = null;
    }
    /* 组装弹窗参数与回调（onConfirm 在弹窗"确定"时回调） */
    const params = new EditFolderDialogParams();
    params.title = "新建文件夹"; // 覆盖默认标题
    params.oldName = "";
    params.oldColor = DEFAULT_FOLDER_COLOR;
    params.onConfirm = (name: string, color: string) => {
      this.vm.createFolder(name, color);
    };
    params.onRequestClose = () => {
      this.closeDialog();
    };

    const node = new ComponentContent<EditFolderDialogParams>(this.getUIContext(),
      wrapBuilder(buildEditFolderContent), params);
    this.newFolderDialogNode = node;
    this.getUIContext().getPromptAction().openCustomDialog(node, {
      autoCancel: true,
      alignment: DialogAlignment.Center,
      offset: DIALOG_OFFSET_TALL,
    }).catch((err: BusinessError) => {
      /* 失败静默正是"按钮无效"的主要嫌疑，这里打日志暴露真实错误码 */
      console.error(`openCustomDialog(新建文件夹) 失败 code=${err.code} msg=${err.message}`);
      this.newFolderDialogNode = null;
    });
  }

  /* 编辑文件夹：重命名 + 切换图标颜色（ComponentContent 方式，与重命名/新建文件夹统一） */
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
      this.vm.doMoveFolder(cat, targetId);
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
  private async openConvPicker(conv: Conversation): Promise<void> {
    /* 先释放上次点遮罩关闭后残留的节点，防止内存泄漏 */
    if (this.convPickerNode) {
      this.convPickerNode.dispose();
      this.convPickerNode = null;
    }
    const allFolders = await CategoryRepository.getInstance().getAll();
    const params = new FolderPickerDialogParams();
    params.title = "移动到文件夹";
    params.folders = allFolders;
    params.onSelect = (folderId: string) => {
      this.vm.doMoveConv(conv, folderId);
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

  /* 批量移动：弹出文件夹选择器（ComponentContent 方式，复用 FolderPickerDialog，收藏 Tab 多选模式） */
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

  /* 删除文件夹（二次确认 + 级联） */
  private confirmFolderDelete(cat: Category): void {
    showDeleteConfirm(
      this.getUIContext(),
      "删除文件夹",
      `确定删除文件夹“${cat.name}”吗？其下所有子文件夹及对话的分类关系将被移除，对话本身不会删除。`,
      () => {
        this.vm.doDeleteFolder(cat.id);
      },
    );
  }

  /* 单选删除确认（API 26 推荐 UIContext 弹窗） */
  private confirmDeleteSingle(conv: Conversation): void {
    showDeleteConfirm(
      this.getUIContext(),
      "删除对话",
      `确定删除对话“${conv.title.length > 0 ? conv.title : "新对话"}”吗？删除后不可恢复。`,
      () => {
        this.vm.doDelete([conv.id]);
      },
    );
  }

  private confirmBatchDelete(): void {
    if (this.vm.selectedIds.length === 0) return;
    showDeleteConfirm(
      this.getUIContext(),
      "删除对话",
      `确定删除选中的 ${this.vm.selectedIds.length} 个对话吗？删除后不可恢复。`,
      () => {
        this.vm.doDelete(this.vm.selectedIds.slice());
      },
    );
  }
}
