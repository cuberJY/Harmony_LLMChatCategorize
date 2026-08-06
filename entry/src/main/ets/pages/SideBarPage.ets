/**
 * 侧边栏页面（SideBarPage）
 * 视觉上与侧边栏类似，作为独立页面存在
 * 从 ChatPage 点击左上角按钮 或 左边缘右滑 进入
 *
 * 阶段四：Navigation 路由重构
 * - 不再作为 @Entry 页面，由 HomePage 的 Navigation 以 NavDestination 形式承载
 * - 路由：顶部返回 / 选中对话 pop(conv) 回传；进入 FolderPage / SettingsPage 用 pushPathByName
 * - 返回刷新：NavDestination.onShown 替代原 onPageShow
 *
 * 结构（从上到下）：
 *  顶部栏  [收藏] [历史]        ← 返回
 *  内容区  收藏Tab → 文件夹列表（第七步实现，先空态占位）
 *         历史Tab → 搜索框 + 按时间分组的历史对话列表
 *  底部    设置按钮（第六步接入）
 */

import { KeyboardAvoidMode } from "@kit.ArkUI";
import { common } from "@kit.AbilityKit";
import { Category } from "../model/Category";
import { FolderItem } from "../components/FolderItem";
import { EditFolderDialog } from "../components/EditFolderDialog";
import { FolderPickerDialog } from "../components/FolderPickerDialog";
import { DatabaseHelper } from "../database/DatabaseHelper";
import { CategoryRepository } from "../database/RepositoryCategory";
import { Conversation } from "../model/Conversation";
import { ConversationItem } from "../components/ConversationItem";
import { RenameInputDialog } from "../components/RenameInputDialog";
import { showDeleteConfirm } from "../common/Utils";
import { getMoveFolderCandidates } from "../common/FolderOps";
import { NavTransitionManager } from "../common/NavTransitionManager";
import { FolderParams } from "../model/FolderParams";
import { SideBarViewModel, GroupItem } from "../viewmodel/SideBarViewModel";

@ComponentV2
export struct SideBarPage {
  // 路由栈（NavDestination.onReady 获取）：跳转 FolderPage/SettingsPage 并转发返回结果
  private pathStack: NavPathStack = new NavPathStack();
  // 转场位移动画状态：百分比字符串，绑定 NavDestination.translate（由转场回调驱动）
  @Local offsetX: string = "0%";
  // 本页在路由栈中的索引（注册/注销转场回调用，onReady 时确定）
  private transitionIndex: number = -1;
  // 数据与业务逻辑（@Trace 状态 + 分组 + 编辑模式）全部收敛到 ViewModel，页面只保留 build / 路由 / 弹窗
  private vm: SideBarViewModel = new SideBarViewModel();

  private dialogId: number = -1; // 当前打开的弹窗 ID（openCustomDialog 返回值，供 closeCustomDialog 使用）
  private globalKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.RESIZE; // 记录全局避让模式
  private swiperController: SwiperController = new SwiperController(); // Swiper 控制器：程序化带动画切换

  aboutToAppear(): void {
    // 记住全局模式（EntryAbility 里设的 RESIZE），本页切换为 NONE：键盘不顶起底部"设置"
    this.globalKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    // 初始化数据库（单例已初始化则跳过）
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
    // 离开页面恢复全局模式，保证 ChatPage 底部输入框的避让不受影响
    this.getUIContext().setKeyboardAvoidMode(this.globalKeyboardAvoidMode);
    // 注销转场动画回调
    if (this.transitionIndex >= 0) {
      NavTransitionManager.getInstance().unregister(this.transitionIndex);
      this.transitionIndex = -1;
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部栏：Tab 切换 + 返回
        if (this.vm.isEditMode) {
          Row() {
            Text("已选择 ")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_primary'))
            Text(this.vm.selectedIds.length.toString())
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_important'))
              .textAlign(TextAlign.Center)
            Text(" 项")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_primary'))
          }
          .width("100%")
          .justifyContent(FlexAlign.Center)
          .height($r('app.float.title_bar_height'))
          .padding({ left: $r('app.float.space_xl'), right: $r('app.float.space_xl') })
          .backgroundColor($r('app.color.title_bar_bg'))
          .border({ width: { bottom: 1 }, color: { bottom: $r('app.color.divider') } });
        } else {
          Row() {
            // Tab 容器（左对齐）
            Row() {
              // 「历史」Tab（index 0，默认页）
              Text("历史")
                .fontSize($r('app.float.font_toggle'))
                .fontColor(
                  this.vm.currentTab === 0 ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'),
                )
                .fontWeight(this.vm.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
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

              // 「收藏」Tab（index 1）
              Text("收藏")
                .fontSize($r('app.float.font_toggle'))
                .fontColor(
                  this.vm.currentTab === 1 ? $r('app.color.toggle_text_active') : $r('app.color.toggle_text_inactive'),
                )
                .fontWeight(this.vm.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
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
            .layoutWeight(1)
            .alignItems(VerticalAlign.Center)

            // 右侧：返回按钮
            Row() {
              SymbolGlyph($r("sys.symbol.ellipsis_message "))
                .fontSize($r('app.float.font_icon_xxl'))
                .fontWeight(700)
                .fontColor([$r('app.color.text_primary')])
            }
            .width(40)
            .justifyContent(FlexAlign.End)
            .onClick(() => {
              this.pathStack.pop();
            })
          }
          .width("100%")
          .height($r('app.float.title_bar_height'))
          .padding({ left: $r('app.float.space_lg'), right: $r('app.float.space_xl') })
          .backgroundColor($r('app.color.title_bar_bg'))
          // 底部分割线
          .border({
            width: { bottom: 1 },
            color: { bottom: $r('app.color.divider') },
          });
        }

        // 内容区：Swiper 支持左右滑动切换 Tab（顺序与顶部 Tab 栏一致：历史在左、收藏在右）
        // 控制器作为构造参数传入：Tab 点击时通过 changeIndex 带动画切换
        Swiper(this.swiperController) {
          // 历史 Tab（index 0，默认页）
          Column() {
            // 搜索框
            if (this.vm.conversations.length > 0) {
              TextInput({ placeholder: "搜索对话...", text: this.vm.searchText })
                .fontSize($r('app.float.font_input'))
                .fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.page_bg'))
                .borderRadius(16)
                .borderWidth(1)
                .borderColor($r('app.color.input_border'))
                .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md'), top: $r('app.float.space_xs'), bottom: $r('app.float.space_xs') })
                .margin({ left: $r('app.float.space_md'), right: $r('app.float.space_md'), top: $r('app.float.space_md'), bottom: $r('app.float.space_md') })
                .onChange((value: string) => {
                  // 实时过滤：重新分组
                  this.vm.searchText = value;
                  this.vm.rebuildGroups();
                });
            }

            // 分组对话列表
            if (this.vm.groups.length === 0) {
              // 空态提示
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
                // 遍历分组：每组先渲染组标题，再渲染该组对话
                ForEach(
                  this.vm.groups,
                  (group: GroupItem) => {
                    // 组标题（左对齐）
                    ListItem() {
                      Text(group.name)
                        .fontSize($r('app.float.font_time'))
                        .fontColor($r('app.color.text_secondary'))
                        .width("100%")
                        .textAlign(TextAlign.Start)
                        .padding({
                          left: $r('app.float.space_xl'),
                          right: $r('app.float.space_xl'),
                          top: $r('app.float.space_md'),
                          bottom: $r('app.float.space_xs'),
                        })
                    };

                    // 该组下的对话
                    ForEach(
                      group.conversations,
                      (conv: Conversation) => {
                        ListItem() {
                          ConversationItem({
                            conversation: conv,
                            isEditMode: this.vm.isEditMode,
                            isSelected: this.vm.selectedIds.indexOf(conv.id) >= 0,
                            // 历史页：星标显示在行尾；不显示"移动"（未收藏对话不参与文件夹分类）
                            showMoveMenu: false,

                            onClickItem: (selected: Conversation) => {
                              // 选中对话 → pop 携带结果返回 ChatPage（pushPathByName 的 onPop 接收）
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
                      (conv: Conversation) => `${conv.id}_${this.vm.listVersion}`,
                    );
                  },
                  (group: GroupItem) => group.name,
                )
              }
              .width("100%")
              .layoutWeight(1)
              .backgroundColor($r('app.color.page_bg'))
              .divider({
                strokeWidth: 0.5,
                color: $r('app.color.divider'),
              });
            }
          }
          .width("100%")
          .height("100%")

          // 收藏 Tab（index 1）
          Stack() {
            if (this.vm.topFolders.length === 0 && this.vm.uncategorizedConvs.length === 0) {
              // 空态
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
                // 顶级文件夹
                ForEach(
                  this.vm.topFolders,
                  (cat: Category) => {
                    ListItem() {
                      FolderItem({
                        category: cat,
                        onClickItem: (selected: Category) => {
                          // 点击 → 进入 FolderPage；onPop 转发 FolderPage 返回的选中对话给 ChatPage
                          this.pathStack.pushPathByName(
                            "FolderPage",
                            new FolderParams(selected.id, selected.name),
                            (popInfo: PopInfo) => {
                              const conv = popInfo.result as Conversation | undefined;
                              if (conv && conv.id.length > 0) {
                                // 文件夹页选中对话 → 继续 pop 回 ChatPage 并携带结果
                                this.pathStack.pop(conv);
                              }
                            },
                          );
                        },
                        onMenuRename: (selected: Category) => {
                          this.openEditFolder(selected);
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
                  (cat: Category) => `${cat.id}_${this.vm.listVersion}`,
                )

                // 文件夹与对话之间的分隔线（两者都有时才显示）
                if (this.vm.topFolders.length > 0 && this.vm.uncategorizedConvs.length > 0) {
                  ListItem() {
                    Divider()
                      .strokeWidth(0.5)
                      .color($r('app.color.divider'))
                      .margin({ left: $r('app.float.space_xl'), right: $r('app.float.space_xl') })
                  };
                }

                // 未分类对话（category_id 为空）
                ForEach(
                  this.vm.uncategorizedConvs,
                  (conv: Conversation) => {
                    ListItem() {
                      ConversationItem({
                        conversation: conv,
                        isEditMode: this.vm.isEditMode,
                        isSelected: this.vm.selectedIds.indexOf(conv.id) >= 0,
                        // 收藏页：不显示星标（该页全是已收藏对话）；保留"移动"菜单调整位置
                        showFavoriteIcon: false,

                        onClickItem: (selected: Conversation) => {
                          // 直接进入对话 → pop 携带结果返回 ChatPage
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
                  (conv: Conversation) => `${conv.id}_${this.vm.listVersion}`,
                )
              }
              .width("100%")
              .height("100%")
              .padding({ top: $r('app.float.space_md') })
              .backgroundColor($r('app.color.page_bg'))
              .edgeEffect(EdgeEffect.Spring);
            }

            // 悬浮新建按钮（右下角）
            Button() {
              Text("+")
                .fontSize($r('app.float.font_icon_xxl'))
                .fontColor(Color.White)
                .fontWeight(FontWeight.Medium)
            }
            .width(32)
            .height(32)
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
          .align(Alignment.BottomEnd)
        }
        .layoutWeight(1)
        .width("100%")
        .duration(150) // 动画时长 150ms（对 changeIndex 与手势滑动都生效）
        .curve(Curve.EaseOut) // 或指定曲线
        .loop(false) // 禁止循环
        .indicator(false) // 隐藏底部指示点（已有自己的 Tab 栏）
        .disableSwipe(this.vm.isEditMode) // 多选编辑模式下禁止滑动，避免误操作
        .onChange((index: number) => {
          this.vm.setCurrentTab(index); // 滑动后同步状态，Tab 栏高亮跟随变化
        })

        // 底部：设置按钮
        if (this.vm.isEditMode) {
          Row() {
            Row() {
              Text("取消")
                .fontSize($r('app.float.font_button'))
                .fontColor($r('app.color.toggle_text_active'))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .onClick(() => {
                  this.vm.exitEditMode();
                })
              Text(`删除`)
                .fontSize($r('app.float.font_button'))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.vm.selectedIds.length > 0 ? $r('app.color.text_danger') : $r('app.color.text_secondary'))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .onClick(() => {
                  if (this.vm.selectedIds.length > 0) this.confirmBatchDelete();
                })
              // 批量移动到文件夹：仅收藏 Tab 显示（收藏对话才参与文件夹分类）
              if (this.vm.currentTab === 1) {
                Text("移动")
                  .fontSize($r('app.float.font_button'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.vm.selectedIds.length > 0 ? $r('app.color.toggle_text_active') : $r('app.color.text_secondary'))
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    if (this.vm.selectedIds.length > 0) this.openBatchMovePicker();
                  })
              }
              Text(this.vm.isAllSelected() ? "取消全选" : "全选")
                .fontSize($r('app.float.font_button'))
                .fontColor($r('app.color.toggle_text_active'))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .onClick(() => {
                  this.vm.toggleSelectAll();
                })
            }
          }
          .width("100%")
          .height($r('app.float.title_bar_height'))
          .justifyContent(FlexAlign.SpaceBetween)
          .backgroundColor($r('app.color.title_bar_bg'))
          .border({
            width: { top: 1 },
            color: { top: $r('app.color.divider') },
          });
        } else {
          Row() {
            SymbolGlyph($r("sys.symbol.gearshape"))
              .fontSize($r('app.float.font_icon_xxl'))
              .fontWeight(700)
              .fontColor([$r('app.color.text_primary')])
              .margin({ right: $r('app.float.space_xs') })
          }
          .width("100%")
          .height($r('app.float.title_bar_height'))
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.title_bar_bg'))
          // 顶部分割线
          .border({
            width: { top: 1 },
            color: { top: $r('app.color.divider') },
          })
          .onClick(() => {
            this.pathStack.pushPathByName("SettingsPage", undefined);
          });
        }
      }
      .width("100%")
      .height("100%")
      .backgroundColor($r('app.color.page_bg'));
    }
    .hideTitleBar(true)
    // 转场位移：由 HomePage 的 customNavContentTransition 通过动画回调驱动（0% 时无偏移）
    .translate({ x: this.offsetX })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      // 注册转场动画回调：本页在路由栈中的索引 = 当前栈内页面数 - 1
      this.transitionIndex = this.pathStack.getAllPathName().length - 1;
      NavTransitionManager.getInstance().register(this.transitionIndex, {
        start: (isPush: boolean, isExit: boolean) => {
          // 初始位置：作为 to（打开侧边栏）先位于左侧屏外；作为 from（关闭侧边栏）留在原位
          this.offsetX = isExit ? "0%" : "-100%";
        },
        finish: (isPush: boolean, isExit: boolean) => {
          // 目标位置：作为 to 左滑入原位；作为 from 左滑出屏幕
          this.offsetX = isExit ? "-100%" : "0%";
        },
        onFinish: () => {
          // 动画结束重置，供下次转场使用
          this.offsetX = "0%";
        },
      });
    })
    .onShown(() => {
      // 从 FolderPage/SettingsPage 返回时重新可见：收藏/历史数据可能已变化（移动/取消收藏/重命名），刷新
      // 兜底：任何上层页面改过全局键盘模式（如 SettingsPage 恢复时），回到本页都纠正为 NONE
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
      this.vm.loadConversations();
      this.vm.loadFavorites();
      // 注：首次进入也会触发，此时数据库 init 可能未完成，查询返回空；
      // 随后 aboutToAppear 中的 init.then 会再次加载出正确数据，最终显示不受影响
    })
  }

  /**
   * 顶部 Tab 点击切换
   * 同时更新高亮状态 + 通过控制器带动画滑动，避免与手势滑动互相干扰
   * @param index 目标 Tab：0=历史 1=收藏
   */
  private switchTab(index: number): void {
    if (this.vm.currentTab === index) return; // 已在该 Tab，无需切换
    this.vm.setCurrentTab(index); // 先更新高亮
    this.swiperController.changeIndex(index, true); // 带动画滑动到目标页
  }

  // 重命名：弹出输入对话框（复用公共组件，openCustomDialog 方式）
  private openRenameDialog(conv: Conversation): void {
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.buildRenameDialog(conv),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -360 }, // 在 alignment 基础上再偏移（vp 单位）
    }).then((id: number) => {
      this.dialogId = id; // 记录弹窗 ID，供 onRequestClose 关闭
    });
  }

  @Builder
  buildRenameDialog(conv: Conversation) {
    RenameInputDialog({
      title: "重命名对话",
      oldValue: conv.title,
      onConfirm: (newTitle: string) => {
        this.vm.doRename(conv.id, newTitle);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 关闭当前打开的弹窗（弹窗组件通过 onRequestClose 回调触发）
  private closeDialog(): void {
    if (this.dialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.dialogId);
      this.dialogId = -1;
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

  // 收藏：弹出收藏位置选择器（复用 FolderPickerDialog）
  private async openFavoritePicker(conv: Conversation): Promise<void> {
    const allFolders = await CategoryRepository.getInstance().getAll();
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.buildFavoritePicker(conv, allFolders),
      autoCancel: true,
      alignment: DialogAlignment.Center,
    }).then((id: number) => {
      this.dialogId = id;
    });
  }

  @Builder
  buildFavoritePicker(conv: Conversation, folders: Category[]) {
    FolderPickerDialog({
      title: "选择收藏位置",
      folders: folders,
      onSelect: (folderId: string) => {
        this.vm.doFavorite(conv, folderId);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 新建顶级文件夹对话框（复用 EditFolderDialog：名称 + 颜色）
  private openNewFolderDialog(): void {
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.buildNewFolderDialog(),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -360 },
    }).then((id: number) => {
      this.dialogId = id;
    });
  }

  @Builder
  buildNewFolderDialog() {
    EditFolderDialog({
      title: "新建文件夹", // 覆盖默认标题
      oldName: "",
      oldColor: "#FF9F0A",
      onConfirm: (name: string, color: string) => {
        this.vm.createFolder(name, color);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 编辑文件夹：重命名 + 切换图标颜色
  private openEditFolder(cat: Category): void {
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.buildEditFolderDialog(cat),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -360 },
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

  // 移动文件夹：弹出目标选择器（排除自身及子孙，防止成环）
  private async openMoveFolder(cat: Category): Promise<void> {
    // 候选目标 = 全部文件夹 - 自身及子孙（空串"不分类"由选择器提供，表示移到顶级）
    const candidates = await getMoveFolderCandidates(cat.id);
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
        this.vm.doMoveFolder(cat, targetId);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 移动对话：弹出文件夹选择器（复用 FolderPickerDialog）
  private async openConvPicker(conv: Conversation): Promise<void> {
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
        this.vm.doMoveConv(conv, folderId);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 批量移动：弹出文件夹选择器（收藏 Tab 多选模式）
  private async openBatchMovePicker(): Promise<void> {
    const allFolders = await CategoryRepository.getInstance().getAll();
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.buildBatchMovePicker(allFolders),
      autoCancel: true,
      alignment: DialogAlignment.Center,
    }).then((id: number) => {
      this.dialogId = id;
    });
  }

  @Builder
  buildBatchMovePicker(folders: Category[]) {
    FolderPickerDialog({
      folders: folders,
      onSelect: (folderId: string) => {
        this.vm.doBatchMove(folderId);
      },
      onRequestClose: () => {
        this.closeDialog();
      },
    })
  }

  // 删除文件夹（二次确认 + 级联）
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

  // 单选删除确认（API 26 推荐 UIContext 弹窗）
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
