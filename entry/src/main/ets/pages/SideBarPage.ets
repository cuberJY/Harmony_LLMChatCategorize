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

import { router, promptAction } from "@kit.ArkUI";
import { common } from "@kit.AbilityKit";
import { DatabaseHelper } from "../database/DatabaseHelper";
import { Conversation } from "../model/Conversation";
import { ConversationItem } from "../components/ConversationItem";
import { AppConfig } from "../config/AppConfig";
import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";

// 时间分组项：一组对话
interface GroupItem {
  name: string; // 组名：今天 / 昨天 / 7天内 / 30天内 / xxxx年x月
  conversations: Conversation[]; // 该组下的对话列表
}

@Entry
@Component
struct SideBarPage {
  @State currentTab: number = 1; // 当前 Tab：0=收藏 1=历史（默认历史）
  @State conversations: Conversation[] = []; // 全量对话（历史Tab数据源）
  @State groups: GroupItem[] = []; // 分组后的对话（渲染数据源）
  @State searchText: string = ""; // 搜索关键字
  @State isEditMode: boolean = false; // 多选编辑模式
  @State selectedIds: string[] = []; // 已选中对话 ID

  aboutToAppear(): void {
    // 初始化数据库（单例已初始化则跳过）
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context) {
      DatabaseHelper.getInstance()
        .init(context)
        .then(() => {
          this.loadConversations();
        });
    }
  }

  build() {
    Column() {
      // 顶部栏：Tab 切换 + 返回
      if (this.isEditMode) {
        Row() {
          Text("已选择")
            .fontSize(FONT_SIZES.BODY)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text(this.selectedIds.length.toString())
            .fontSize(FONT_SIZES.BODY)
            .fontColor(COLORS.TEXT_IMPORTANT)
            .textAlign(TextAlign.Center)
          Text("项")
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
            // 「收藏」Tab
            Text("收藏")
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
              .height(32)
              .borderRadius(16)
              .onClick(() => {
                this.currentTab = 0;
              })

            // 「历史」Tab
            Text("历史")
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
              .height(32)
              .borderRadius(16)
              .margin({ left: SPACING.XS })
              .onClick(() => {
                this.currentTab = 1;
              })
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)

          // 右侧：返回按钮
          Row() {
            SymbolGlyph($r("sys.symbol.chevron_right"))
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

      // 内容区（按 Tab 切换）
      if (this.currentTab === 0) {
        // 收藏 Tab：文件夹列表（第七步实现，先空态占位）
        Column() {
          Text("暂无文件夹")
            .fontSize(FONT_SIZES.REMIND)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .width("100%")
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      } else {
        // 历史 Tab：搜索框 + 分组对话列表
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
              })
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
                      // ← 左对齐
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

                          onClickItem: (selected: Conversation) => {
                            this.selectConversation(selected);
                          },
                          onSelectChange: (selected: Conversation, checked: boolean) => {
                            this.toggleSelect(selected.id, checked);
                          },
                          onMenuDelete: (selected: Conversation) => {
                            this.confirmDeleteSingle(selected);
                          },
                          onMenuSelect: (selected: Conversation) => {
                            this.enterEditMode(selected.id);
                          },
                        })
                      }.width("100%");
                    },
                    (conv: Conversation) => conv.id,
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
        .layoutWeight(1);
      }

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
            .fontSize(FONT_SIZES.ICON_LG)
            .fontWeight(600)
            .fontColor([Color.Black])
            .margin({ right: SPACING.XS })
          Text("设置")
            .fontSize(FONT_SIZES.BUTTON)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)
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
      const name = this.getGroupName(conv.updatedAt);
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

  // 单选删除确认（API 26 推荐 UIContext 弹窗）
  private confirmDeleteSingle(conv: Conversation): void {
    this.getUIContext().showAlertDialog({
      title: "删除对话",
      message: `确定删除对话“${conv.title.length > 0 ? conv.title : "新对话"}”吗？删除后不可恢复。`,
      primaryButton: { value: "取消", action: () => {} },
      secondaryButton: {
        value: "删除",
        fontColor: Color.Red,
        action: () => {
          this.doDelete([conv.id]);
        },
      },
    });
  }

  private confirmBatchDelete(): void {
    if (this.selectedIds.length === 0) return;
    this.getUIContext().showAlertDialog({
      title: "删除对话",
      message: `确定删除选中的 ${this.selectedIds.length} 个对话吗？删除后不可恢复。`,
      primaryButton: { value: "取消", action: () => {} },
      secondaryButton: {
        value: "删除",
        fontColor: Color.Red,
        action: () => {
          this.doDelete(this.selectedIds.slice());
        },
      },
    });
  }

  // 执行删除：先拷贝 id，再删除 → 退出编辑模式 → 刷新
  private async doDelete(ids: string[]): Promise<void> {
    this.removeConversationsLocally(ids); // 内存中移除
    this.exitEditMode();
    await DatabaseHelper.getInstance().deleteConversations(ids); // 删数据库
    promptAction.showToast({ message: `已删除 ${ids.length} 个对话` });
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
  }

  /**
   * 根据时间戳计算所属分组名
   *   今天 → "今天"
   *   昨天 → "昨天"
   *   7天内 → "7天内"
   *   30天内 → "30天内"
   *   更早 → "2026年6月"
   */
  private getGroupName(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();

    // 今天
    if (date.toDateString() === now.toDateString()) {
      return "今天";
    }
    // 昨天
    const yesterday = new Date(now);
    yesterday.setDate(now.getDate() - 1);
    if (date.toDateString() === yesterday.toDateString()) {
      return "昨天";
    }
    // 7天内 / 30天内
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const msgDayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    const diffDays = Math.floor((todayStart - msgDayStart) / (1000 * 60 * 60 * 24));
    if (diffDays < 7) {
      return "7天内";
    }
    if (diffDays < 30) {
      return "30天内";
    }
    // 更早 → 年月分组
    return `${date.getFullYear()}年${date.getMonth() + 1}月`;
  }
}
