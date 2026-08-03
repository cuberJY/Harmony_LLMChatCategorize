/**
 * 侧边栏页面（SideBarPage）
 * 视觉上与侧边栏类似，作为独立页面存在
 * 从 ChatPage 点击左上角按钮 或 左边缘右滑 进入
 *
 * 结构（从上到下）：
 *  顶部栏  [收藏] [历史]        ← 返回
 *  内容区  收藏Tab → 文件夹列表（第七步实现，先空态占位）
 *         历史Tab → 搜索框 + 按时间分组的历史对话列表
 *  底部    设置按钮（第六步接入）
 */

import { router, KeyboardAvoidMode } from "@kit.ArkUI";
import { common } from "@kit.AbilityKit";
import { Category } from "../model/Category";
import { FolderItem } from "../components/FolderItem";
import { EditFolderDialog } from "../components/EditFolderDialog";
import { FolderPickerDialog } from "../components/FolderPickerDialog";
import { DatabaseHelper } from "../database/DatabaseHelper";
import { Conversation } from "../model/Conversation";
import { ConversationItem } from "../components/ConversationItem";
import { AppConfig } from "../config/AppConfig";
import { COLORS, FONT_SIZES, SPACING, MESSAGES } from "../common/AppConstants";
import { RenameInputDialog } from "../components/RenameInputDialog";
import { getGroupName } from "../common/TimeUtil";
import { showToast, showDeleteConfirm } from "../common/Utils";
import { getMoveFolderCandidates, moveCategoryTo, moveConversationTo, saveCategoryEdit } from "../common/FolderOps";

// 时间分组项：一组对话
interface GroupItem {
  name: string; // 组名：今天 / 昨天 / 7天内 / 30天内 / xxxx年x月
  conversations: Conversation[]; // 该组下的对话列表
}


@Entry
@Component
struct SideBarPage {
  @State currentTab: number = 0; // 当前 Tab：0=历史 1=收藏（默认历史）
  @State conversations: Conversation[] = []; // 全量对话（历史Tab数据源）
  @State groups: GroupItem[] = []; // 分组后的对话（渲染数据源）
  @State topFolders: Category[] = []; // 顶级文件夹列表（收藏 Tab）
  @State uncategorizedConvs: Conversation[] = []; // 未分类对话列表（收藏 Tab）
  @State searchText: string = ""; // 搜索关键字
  @State isEditMode: boolean = false; // 多选编辑模式
  @State selectedIds: string[] = []; // 已选中对话 ID
  @State listVersion: number = 0; // 列表刷新版本号：重命名/改色等键不变的内容变更后自增，强制 ForEach 重建

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
          this.loadConversations();
          this.loadFavorites();
        });
    }
  }

  aboutToDisappear(): void {
    // 离开页面恢复全局模式，保证 ChatPage 底部输入框的避让不受影响
    this.getUIContext().setKeyboardAvoidMode(this.globalKeyboardAvoidMode);
  }

  onPageShow(): void {
    /**
     * 从 FolderPage 等页面返回时重新可见，收藏数据可能已变化（对话/文件夹移动、取消收藏），刷新
     * 历史列表也需刷新：取消收藏后星标、菜单文案要同步
     * 注：首次进入也会触发，此时数据库 init 可能未完成，查询返回空；
     * 随后 aboutToAppear 中的 init.then 会再次加载出正确数据，最终显示不受影响
     */
    // 兜底：任何上层页面改过全局键盘模式（如 SettingsPage 恢复时），回到本页都纠正为 NONE
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    this.loadConversations();
    this.loadFavorites();
  }

  build() {
    Column() {
      // 顶部栏：Tab 切换 + 返回
      if (this.isEditMode) {
        Row() {
          Text("已选择 ")
            .fontSize(FONT_SIZES.BODY)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text(this.selectedIds.length.toString())
            .fontSize(FONT_SIZES.BODY)
            .fontColor(COLORS.TEXT_IMPORTANT)
            .textAlign(TextAlign.Center)
          Text(" 项")
            .fontSize(FONT_SIZES.BODY)
            .fontColor(COLORS.TEXT_PRIMARY)
        }
        .width("100%")
        .justifyContent(FlexAlign.Center)
        .height(SPACING.TITLE_BAR_HEIGHT)
        .padding({ left: SPACING.XL, right: SPACING.XL })
        .backgroundColor(COLORS.TITLE_BAR_BG)
        .border({ width: { bottom: 1 }, color: { bottom: COLORS.DIVIDER } });
      } else {
        Row() {
          // Tab 容器（左对齐）
          Row() {
            // 「历史」Tab（index 0，默认页）
            Text("历史")
              .fontSize(FONT_SIZES.TOGGLE)
              .fontColor(
                this.currentTab === 0 ? COLORS.TOGGLE_TEXT_ACTIVE : COLORS.TOGGLE_TEXT_INACTIVE,
              )
              .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
              .padding({
                left: SPACING.MD,
                right: SPACING.MD,
                top: SPACING.XS,
                bottom: SPACING.XS,
              })
              .backgroundColor(this.currentTab === 0 ? COLORS.TOGGLE_BG_ACTIVE : Color.Transparent)
              .height(36)
              .borderRadius(18)
              .onClick(() => {
                this.switchTab(0);
              })

            // 「收藏」Tab（index 1）
            Text("收藏")
              .fontSize(FONT_SIZES.TOGGLE)
              .fontColor(
                this.currentTab === 1 ? COLORS.TOGGLE_TEXT_ACTIVE : COLORS.TOGGLE_TEXT_INACTIVE,
              )
              .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
              .padding({
                left: SPACING.MD,
                right: SPACING.MD,
                top: SPACING.XS,
                bottom: SPACING.XS,
              })
              .backgroundColor(this.currentTab === 1 ? COLORS.TOGGLE_BG_ACTIVE : Color.Transparent)
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
              .fontSize(FONT_SIZES.ICON_XXL)
              .fontWeight(700)
              .fontColor([Color.Black])
          }
          .width(40)
          .justifyContent(FlexAlign.End)
          .onClick(() => {
            router.back();
          })
        }
        .width("100%")
        .height(SPACING.TITLE_BAR_HEIGHT)
        .padding({ left: SPACING.LG, right: SPACING.XL })
        .backgroundColor(COLORS.TITLE_BAR_BG)
        // 底部分割线
        .border({
          width: { bottom: 1 },
          color: { bottom: COLORS.DIVIDER },
        });
      }

      // 内容区：Swiper 支持左右滑动切换 Tab（顺序与顶部 Tab 栏一致：历史在左、收藏在右）
      // 控制器作为构造参数传入：Tab 点击时通过 changeIndex 带动画切换
      Swiper(this.swiperController) {
        // 历史 Tab（index 0，默认页）
        Column() {
          // 搜索框
          if (this.conversations.length > 0) {
            TextInput({ placeholder: "搜索对话...", text: this.searchText })
              .fontSize(FONT_SIZES.INPUT)
              .fontColor(COLORS.TEXT_PRIMARY)
              .placeholderColor(COLORS.TEXT_SECONDARY)
              .backgroundColor(COLORS.PAGE_BG)
              .borderRadius(16)
              .borderWidth(1)
              .borderColor(COLORS.INPUT_BORDER)
              .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.XS, bottom: SPACING.XS })
              .margin({ left: SPACING.MD, right: SPACING.MD, top: SPACING.MD, bottom: SPACING.MD })
              .onChange((value: string) => {
                // 实时过滤：重新分组
                this.searchText = value;
                this.rebuildGroups();
              });
          }

          // 分组对话列表
          if (this.groups.length === 0) {
            // 空态提示
            Column() {
              Text("暂无历史对话")
                .fontSize(FONT_SIZES.REMIND)
                .fontColor(COLORS.TEXT_SECONDARY)
            }
            .width("100%")
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center);
          } else {
            List() {
              // 遍历分组：每组先渲染组标题，再渲染该组对话
              ForEach(
                this.groups,
                (group: GroupItem) => {
                  // 组标题（左对齐）
                  ListItem() {
                    Text(group.name)
                      .fontSize(FONT_SIZES.TIME)
                      .fontColor(COLORS.TEXT_SECONDARY)
                      .width("100%")
                      .textAlign(TextAlign.Start)
                      .padding({
                        left: SPACING.XL,
                        right: SPACING.XL,
                        top: SPACING.MD,
                        bottom: SPACING.XS,
                      })
                  };

                  // 该组下的对话
                  ForEach(
                    group.conversations,
                    (conv: Conversation) => {
                      ListItem() {
                        ConversationItem({
                          conversation: conv,
                          isEditMode: this.isEditMode,
                          isSelected: this.selectedIds.indexOf(conv.id) >= 0,
                          // 历史页：星标显示在行尾；不显示"移动"（未收藏对话不参与文件夹分类）
                          showMoveMenu: false,

                          onClickItem: (selected: Conversation) => {
                            this.selectConversation(selected);
                          },
                          onSelectChange: (selected: Conversation, checked: boolean) => {
                            this.toggleSelect(selected.id, checked);
                          },
                          onMenuRename: (selected: Conversation) => {
                            this.openRenameDialog(selected);
                          },
                          onMenuDelete: (selected: Conversation) => {
                            this.confirmDeleteSingle(selected);
                          },
                          onMenuSelect: (selected: Conversation) => {
                            this.enterEditMode(selected.id);
                          },
                          onMenuFavorite: (selected: Conversation) => {
                            this.onFavoriteAction(selected);
                          },
                        })
                      }.width("100%");
                    },
                    (conv: Conversation) => `${conv.id}_${this.listVersion}`,
                  );
                },
                (group: GroupItem) => group.name,
              )
            }
            .width("100%")
            .layoutWeight(1)
            .backgroundColor(COLORS.PAGE_BG)
            .divider({
              strokeWidth: 0.5,
              color: COLORS.DIVIDER,
            });
          }
        }
        .width("100%")
        .height("100%")

        // 收藏 Tab（index 1）
        Stack() {
          if (this.topFolders.length === 0 && this.uncategorizedConvs.length === 0) {
            // 空态
            Column() {
              Text("暂无收藏")
                .fontSize(FONT_SIZES.REMIND)
                .fontColor(COLORS.TEXT_SECONDARY)
            }
            .width("100%")
            .height("100%")
            .justifyContent(FlexAlign.Center);
          } else {
            List() {
              // 顶级文件夹
              ForEach(
                this.topFolders,
                (cat: Category) => {
                  ListItem() {
                    FolderItem({
                      category: cat,
                      onClickItem: (selected: Category) => {
                        // 点击 → 进入 FolderPage
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
                        this.confirmFolderDelete(selected);
                      },
                    })
                  }.width("100%");
                },
                (cat: Category) => `${cat.id}_${this.listVersion}`,
              )

              // 文件夹与对话之间的分隔线（两者都有时才显示）
              if (this.topFolders.length > 0 && this.uncategorizedConvs.length > 0) {
                ListItem() {
                  Divider()
                    .strokeWidth(0.5)
                    .color(COLORS.DIVIDER)
                    .margin({ left: SPACING.XL, right: SPACING.XL })
                };
              }

              // 未分类对话（category_id 为空）
              ForEach(
                this.uncategorizedConvs,
                (conv: Conversation) => {
                  ListItem() {
                    ConversationItem({
                      conversation: conv,
                      isEditMode: this.isEditMode,
                      isSelected: this.selectedIds.indexOf(conv.id) >= 0,
                      // 收藏页：不显示星标（该页全是已收藏对话）；保留"移动"菜单调整位置
                      showFavoriteIcon: false,

                      onClickItem: (selected: Conversation) => {
                        this.selectConversation(selected); // 直接进入对话
                      },
                      onSelectChange: (selected: Conversation, checked: boolean) => {
                        this.toggleSelect(selected.id, checked);
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
                        this.enterEditMode(selected.id);
                      },
                      onMenuFavorite: (selected: Conversation) => {
                        this.onFavoriteAction(selected);
                      },
                    })
                  }.width("100%");
                },
                (conv: Conversation) => `${conv.id}_${this.listVersion}`,
              )
            }
            .width("100%")
            .height("100%")
            .padding({ top: SPACING.MD })
            .backgroundColor(COLORS.PAGE_BG)
            .edgeEffect(EdgeEffect.Spring);
          }

          // 悬浮新建按钮（右下角）
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
          .shadow({ radius: 8, color: COLORS.FAB_SHADOW, offsetY: 2 })
          .margin({ right: SPACING.XL, bottom: SPACING.XL })
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
      .disableSwipe(this.isEditMode) // 多选编辑模式下禁止滑动，避免误操作
      .onChange((index: number) => {
        this.currentTab = index; // 滑动后同步状态，Tab 栏高亮跟随变化
      })

      // 底部：设置按钮
      if (this.isEditMode) {
        Row() {
          Row() {
            Text("取消")
              .fontSize(FONT_SIZES.BUTTON)
              .fontColor(COLORS.TOGGLE_TEXT_ACTIVE)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.exitEditMode();
              })
            Text(`删除`)
              .fontSize(FONT_SIZES.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.selectedIds.length > 0 ? COLORS.TEXT_DANGER : COLORS.TEXT_SECONDARY)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                if (this.selectedIds.length > 0) this.confirmBatchDelete();
              })
            // 批量移动到文件夹：仅收藏 Tab 显示（收藏对话才参与文件夹分类）
            if (this.currentTab === 1) {
              Text("移动")
                .fontSize(FONT_SIZES.BUTTON)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.selectedIds.length > 0 ? COLORS.TOGGLE_TEXT_ACTIVE : COLORS.TEXT_SECONDARY)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .onClick(() => {
                  if (this.selectedIds.length > 0) this.openBatchMovePicker();
                })
            }
            Text(this.isAllSelected() ? "取消全选" : "全选")
              .fontSize(FONT_SIZES.BUTTON)
              .fontColor(COLORS.TOGGLE_TEXT_ACTIVE)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.toggleSelectAll();
              })
          }
        }
        .width("100%")
        .height(SPACING.TITLE_BAR_HEIGHT)
        .justifyContent(FlexAlign.SpaceBetween)
        .backgroundColor(COLORS.TITLE_BAR_BG)
        .border({
          width: { top: 1 },
          color: { top: COLORS.DIVIDER },
        });
      } else {
        Row() {
          SymbolGlyph($r("sys.symbol.gearshape"))
            .fontSize(FONT_SIZES.ICON_XXL)
            .fontWeight(700)
            .fontColor([Color.Black])
            .margin({ right: SPACING.XS })
        }
        .width("100%")
        .height(SPACING.TITLE_BAR_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(COLORS.TITLE_BAR_BG)
        // 顶部分割线
        .border({
          width: { top: 1 },
          color: { top: COLORS.DIVIDER },
        })
        .onClick(() => {
          router.pushUrl({ url: "pages/SettingsPage" });
        });
      }
    }
    .width("100%")
    .height("100%")
    .backgroundColor(COLORS.PAGE_BG);
  }

  // 从数据库查询全部对话（按更新时间倒序）并重新分组
  private async loadConversations(): Promise<void> {
    const list = await DatabaseHelper.getInstance().getConversations();
    this.conversations = list;
    this.rebuildGroups();
  }

  /**
   * 根据搜索关键字重新构建分组
   * 规则：对话先按 updatedAt 倒序，再归入 今天/昨天/7天内/30天内/年月 各组
   */
  private rebuildGroups(): void {
    const keyword = this.searchText.trim().toLowerCase();
    // 1. 过滤（有关键字时按标题匹配）
    const filtered =
      keyword.length === 0
        ? this.conversations
        : this.conversations.filter((c: Conversation) => c.title.toLowerCase().includes(keyword));

    // 2. 按更新时间倒序
    const sorted = filtered
      .slice()
      .sort((a: Conversation, b: Conversation) => b.updatedAt - a.updatedAt);

    // 3. 遍历分组（保持各组出现顺序：今天 → 昨天 → 7天内 → 30天内 → 年月）
    const result: GroupItem[] = [];
    const groupIndexMap: Map<string, number> = new Map(); // 组名 → 在 result 中的下标
    sorted.forEach((conv: Conversation) => {
      const name = getGroupName(conv.updatedAt);
      const idx = groupIndexMap.get(name);
      if (idx === undefined) {
        // 新组
        groupIndexMap.set(name, result.length);
        result.push({ name: name, conversations: [conv] });
      } else {
        result[idx].conversations.push(conv);
      }
    });
    this.groups = result;
  }

  // 侧边栏页面过渡动画
  pageTransition() {
    // 打开（Push）：从左侧屏幕外(-100%)滑入 → 向右移动
    PageTransitionEnter({ type: RouteType.Push, duration: 150, curve: Curve.EaseOut }).translate({
      x: "-100%",
    });
    // 关闭（Pop）：向左滑出，回到左侧屏幕外
    PageTransitionExit({ type: RouteType.Pop, duration: 150, curve: Curve.EaseOut }).translate({
      x: "-100%",
    });
  }

  /**
   * 顶部 Tab 点击切换
   * 同时更新高亮状态 + 通过控制器带动画滑动，避免与手势滑动互相干扰
   * @param index 目标 Tab：0=历史 1=收藏
   */
  private switchTab(index: number): void {
    if (this.currentTab === index) return; // 已在该 Tab，无需切换
    this.currentTab = index; // 先更新高亮
    this.swiperController.changeIndex(index, true); // 带动画滑动到目标页
  }

  /**
   * 用户选中某条历史对话
   * 将选中对话存入 AppConfig → 返回 ChatPage → 由 onPageShow 读取加载
   * @param conv 选中的对话
   */
  private selectConversation(conv: Conversation): void {
    AppConfig.getInstance().selectedConversation = conv;
    router.back();
  }

  // 进入多选模式（可预选长按的那一项）
  private enterEditMode(preSelectId: string): void {
    this.isEditMode = true;
    this.selectedIds = preSelectId.length > 0 ? [preSelectId] : [];
  }

  private exitEditMode(): void {
    this.isEditMode = false;
    this.selectedIds = [];
  }

  private toggleSelect(id: string, checked: boolean): void {
    const idx = this.selectedIds.indexOf(id);
    if (checked && idx < 0) {
      this.selectedIds.push(id);
    } else if (!checked && idx >= 0) {
      this.selectedIds.splice(idx, 1);
    }
  }

  // 当前可见对话（分组拍平，供全选使用）
  private getAllVisible(): Conversation[] {
    const result: Conversation[] = [];
    this.groups.forEach((g: GroupItem) =>
      g.conversations.forEach((c: Conversation) => result.push(c)),
    );
    return result;
  }

  private isAllSelected(): boolean {
    const visible = this.getAllVisible();
    return visible.length > 0 && this.selectedIds.length === visible.length;
  }

  private toggleSelectAll(): void {
    if (this.isAllSelected()) {
      this.selectedIds = [];
    } else {
      this.selectedIds = this.getAllVisible().map((c: Conversation) => c.id);
    }
  }

  private renameDialogController: CustomDialogController | null = null; // 重命名对话框控制器

  // 重命名：弹出输入对话框（复用公共组件）
  private openRenameDialog(conv: Conversation): void {
    this.renameDialogController = new CustomDialogController({
      builder: RenameInputDialog({
        title: "重命名对话",
        oldValue: conv.title,
        onConfirm: (newTitle: string) => {
          this.doRename(conv.id, newTitle);
        },
      }),
      autoCancel: true, // 点击遮罩关闭
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -360 }, // 在 alignment 基础上再偏移（vp 单位）
      customStyle: true, // 完全自定义样式
    });
    this.renameDialogController.open();
  }

  // 执行重命名：更新内存 + 数据库
  private async doRename(id: string, newTitle: string): Promise<void> {
    const conv = this.conversations.find((c: Conversation) => c.id === id);
    if (!conv) return;
    conv.title = newTitle; // 更新内存对象
    // 收藏 Tab 的 uncategorizedConvs 是另一批实例，需同步，否则收藏列表不实时刷新
    const uc = this.uncategorizedConvs.find((c: Conversation) => c.id === id);
    if (uc) uc.title = newTitle;
    await DatabaseHelper.getInstance().updateConversation(conv); // 持久化
    this.listVersion++; // 强制 ForEach 重建，刷新对话标题
    showToast(MESSAGES.RENAME_SUCCESS);
  }

  // 文件夹对话框控制器
  private folderDialogController: CustomDialogController | null = null;
  private pickerController: CustomDialogController | null = null; // 移动文件夹选择器控制器

  // 加载收藏 Tab 数据：顶级文件夹 + 已收藏但未放入文件夹的对话
  private async loadFavorites(): Promise<void> {
    // 顶级文件夹：parent_id 为空
    this.topFolders = await DatabaseHelper.getInstance().getCategoriesByParent("");
    // 未分类收藏对话：已收藏（is_favorite=1）且 category_id 为空
    const favorites = await DatabaseHelper.getInstance().getFavoriteConversations();
    this.uncategorizedConvs = favorites.filter((c: Conversation) => c.categoryId.length === 0);
  }

  /**
   * 长按菜单-收藏/取消收藏（历史 Tab 与收藏 Tab 共用）
   * 未收藏 → 弹出选择收藏位置；已收藏 → 直接取消收藏
   */
  private onFavoriteAction(conv: Conversation): void {
    if (conv.isFavorite) {
      this.doUnfavorite(conv);
    } else {
      this.openFavoritePicker(conv);
    }
  }

  // 收藏：弹出收藏位置选择器（复用 FolderPickerDialog）
  private async openFavoritePicker(conv: Conversation): Promise<void> {
    const allFolders = await DatabaseHelper.getInstance().getCategories();
    this.pickerController = new CustomDialogController({
      builder: FolderPickerDialog({
        title: "选择收藏位置",
        folders: allFolders,
        onSelect: (folderId: string) => {
          this.doFavorite(conv, folderId);
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
    });
    this.pickerController.open();
  }

  // 执行收藏：置 is_favorite=1 并写入收藏位置
  private async doFavorite(conv: Conversation, folderId: string): Promise<void> {
    // 历史列表中的对应实例同步更新（列表数据源可能是另一批实例）
    const hist = this.conversations.find((c: Conversation) => c.id === conv.id);
    if (hist) {
      hist.isFavorite = true;
      hist.categoryId = folderId;
    }
    conv.isFavorite = true;
    conv.categoryId = folderId;
    await DatabaseHelper.getInstance().setFavorite(conv, true);
    await this.loadFavorites(); // 刷新收藏 Tab（对话可能进入文件夹或未分类）
    this.listVersion++; // 刷新历史列表：星标出现、菜单变为"取消收藏"
    showToast(MESSAGES.FAVORITED);
  }

  // 执行取消收藏：置 is_favorite=0、清空收藏位置，并从收藏列表移除
  private async doUnfavorite(conv: Conversation): Promise<void> {
    await DatabaseHelper.getInstance().setFavorite(conv, false); // 同时清空 categoryId
    // 历史列表中的对应实例同步更新（收藏 Tab 与历史列表可能是不同实例）
    const hist = this.conversations.find((c: Conversation) => c.id === conv.id);
    if (hist) {
      hist.isFavorite = false;
      hist.categoryId = "";
    }
    conv.isFavorite = false;
    conv.categoryId = "";
    await this.loadFavorites(); // 刷新收藏 Tab（未分类收藏可能变化）
    this.listVersion++; // 刷新历史列表：星标消失、菜单变回"收藏"
    showToast(MESSAGES.UNFAVORITED);
  }

  // 新建顶级文件夹对话框（复用 EditFolderDialog：名称 + 颜色）
  private openNewFolderDialog(): void {
    this.folderDialogController = new CustomDialogController({
      builder: EditFolderDialog({
        title: "新建文件夹", // 覆盖默认标题
        oldName: "",
        oldColor: "#FF9F0A",
        onConfirm: async (name: string, color: string) => {
          const cat = new Category(undefined, name, undefined, color); // 颜色一并入库
          await DatabaseHelper.getInstance().insertCategory(cat); // ← 等写入完成
          await this.loadFavorites(); // ← 再刷新
          showToast(`已创建 ${name}`);
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -360 },
      customStyle: true,
    });
    this.folderDialogController.open();
  }

  // 编辑文件夹：重命名 + 切换图标颜色
  private openEditFolder(cat: Category): void {
    this.folderDialogController = new CustomDialogController({
      builder: EditFolderDialog({
        oldName: cat.name,
        oldColor: cat.color,
        onConfirm: async (name: string, color: string) => {
          await saveCategoryEdit(cat, name, color); // 更新名称与颜色并持久化
          await this.loadFavorites();
          this.listVersion++; // 强制 ForEach 重建，刷新名称/颜色
          showToast(MESSAGES.SAVED);
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -360 },
      customStyle: true,
    });
    this.folderDialogController.open();
  }

  // 移动文件夹：弹出目标选择器（排除自身及子孙，防止成环）
  private async openMoveFolder(cat: Category): Promise<void> {
    // 候选目标 = 全部文件夹 - 自身及子孙（空串"不分类"由选择器提供，表示移到顶级）
    const candidates = await getMoveFolderCandidates(cat.id);
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
    await moveCategoryTo(cat, targetId); // 空串 = 移到顶级
    await this.loadFavorites();
    showToast(targetId.length > 0 ? MESSAGES.MOVED : MESSAGES.MOVED_TO_TOP);
  }

  // 移动对话：弹出文件夹选择器（复用 FolderPickerDialog）
  private async openConvPicker(conv: Conversation): Promise<void> {
    const allFolders = await DatabaseHelper.getInstance().getCategories();
    this.pickerController = new CustomDialogController({
      builder: FolderPickerDialog({
        folders: allFolders,
        onSelect: (folderId: string) => {
          this.doMoveConv(conv, folderId);
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
    });
    this.pickerController.open();
  }

  // 执行移动对话：更新分类并刷新收藏列表
  private async doMoveConv(conv: Conversation, folderId: string): Promise<void> {
    await moveConversationTo(conv, folderId);
    // 收藏 Tab 的未分类列表可能因分类变化而增删，重新加载刷新
    await this.loadFavorites();
    showToast(MESSAGES.MOVED_OK);
  }

  // 批量移动：弹出文件夹选择器（收藏 Tab 多选模式）
  private async openBatchMovePicker(): Promise<void> {
    const allFolders = await DatabaseHelper.getInstance().getCategories();
    this.pickerController = new CustomDialogController({
      builder: FolderPickerDialog({
        folders: allFolders,
        onSelect: (folderId: string) => {
          this.doBatchMove(folderId);
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
    });
    this.pickerController.open();
  }

  // 执行批量移动：选中对话统一移入目标文件夹，然后退出编辑模式并刷新
  private async doBatchMove(folderId: string): Promise<void> {
    const ids = this.selectedIds.slice(); // 先拷贝，避免退出编辑模式时被清空
    await DatabaseHelper.getInstance().moveConversations(ids, folderId);
    this.exitEditMode();
    await this.loadFavorites(); // 移入文件夹后从"未分类"消失
    showToast(folderId.length > 0 ? `已移动 ${ids.length} 个对话` : MESSAGES.MOVED_OUT);
  }

  // 删除文件夹（二次确认 + 级联）
  private confirmFolderDelete(cat: Category): void {
    showDeleteConfirm(
      this.getUIContext(),
      "删除文件夹",
      `确定删除文件夹“${cat.name}”吗？其下所有子文件夹及对话的分类关系将被移除，对话本身不会删除。`,
      () => {
        this.doDeleteFolder(cat.id);
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
        this.doDelete([conv.id]);
      },
    );
  }

  private confirmBatchDelete(): void {
    if (this.selectedIds.length === 0) return;
    showDeleteConfirm(
      this.getUIContext(),
      "删除对话",
      `确定删除选中的 ${this.selectedIds.length} 个对话吗？删除后不可恢复。`,
      () => {
        this.doDelete(this.selectedIds.slice());
      },
    );
  }

  // 执行删除：先拷贝 id，再删除 → 退出编辑模式 → 刷新
  private async doDelete(ids: string[]): Promise<void> {
    this.removeConversationsLocally(ids); // 内存中移除
    this.exitEditMode();
    await DatabaseHelper.getInstance().deleteConversations(ids); // 删数据库
    showToast(`已删除 ${ids.length} 个对话`);
  }

  // 执行删除文件夹（级联），confirmFolderDelete 的 onConfirm 回调
  private async doDeleteFolder(id: string): Promise<void> {
    await DatabaseHelper.getInstance().deleteCategoryCascade(id);
    await this.loadFavorites();
    showToast(MESSAGES.FOLDER_DELETED);
  }

  // 从内存数据源移除指定对话，并同步渲染分组
  private removeConversationsLocally(ids: string[]): void {
    // 从全量数据源移除：保证后续搜索/重新分组不会把已删项带回来
    this.conversations = this.conversations.filter((c: Conversation) => ids.indexOf(c.id) < 0);
    // 从渲染用分组中移除，并剔除被删空的分组
    this.groups = this.groups
      .map(
        (g: GroupItem): GroupItem => ({
          name: g.name,
          conversations: g.conversations.filter((c: Conversation) => ids.indexOf(c.id) < 0),
        }),
      )
      .filter((g: GroupItem) => g.conversations.length > 0);
    // 同步移除收藏 Tab 的未分类对话，否则切到收藏界面仍会显示已删除的对话
    this.uncategorizedConvs = this.uncategorizedConvs.filter(
      (c: Conversation) => ids.indexOf(c.id) < 0,
    );
  }


}
