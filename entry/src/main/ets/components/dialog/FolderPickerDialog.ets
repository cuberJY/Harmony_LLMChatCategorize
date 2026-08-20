/**
 * 文件夹选择器（共享组件，状态管理 V2）
 * 用于：移动对话到文件夹、移动文件夹到其他文件夹
 * 显示：标题 + 「默认(不分类)」选项 + 可折叠的多层文件夹树 + 「取消/确认」按钮
 * 交互：点击行高亮选中 → 点「确认」回调 onSelect 并关闭（先点选、再确认，避免误触立即生效）
 * 注意：folders 需由调用方过滤后传入（移动文件夹时排除自身及子孙，防止成环）；
 *       层级关系由 Category.parentId 表达，本组件内部建树并按 depth 缩进、可折叠展开
 *
 * 打开方式：父页面通过 getPromptAction().openCustomDialog 打开；
 * 关闭方式：组件通过 onRequestClose 回调通知父页面 closeCustomDialog(dialogId)
 */

import { Category } from "../../model/Category";

/* 一行可见的文件夹节点：cat + 层级深度 + 是否可折叠 + 是否已展开（刷新时整表重建用） */
class FolderRow {
  cat: Category;
  depth: number;
  expandable: boolean;
  expanded: boolean;

  constructor(cat: Category, depth: number, expandable: boolean, expanded: boolean) {
    this.cat = cat;
    this.depth = depth;
    this.expandable = expandable;
    this.expanded = expanded;
  }
}

@ComponentV2
export struct FolderPickerDialog {
  @Param title: string = "移动到"; // 对话框标题（可传入覆盖）
  @Param folders: Category[] = []; // 候选文件夹列表（含各级，按 parentId 建树）
  @Event onSelect: (folderId: string) => void = (folderId: string) => {};
  @Event onRequestClose: () => void = () => {}; // 关闭回调（父页面负责关闭弹窗）

  /* 子节点映射：parentId -> 已排序的子文件夹（非 UI 状态，仅内存用） */
  private nodeMap: Map<string, Category[]> = new Map();
  @Local selectedId: string = ""; // 当前高亮选中的文件夹 ID，空串 = 「默认」顶级
  @Local expandedIds: Set<string> = new Set(); // 展开的文件夹 ID 集合（用 Set 表达折叠状态）
  @Local visibleRows: FolderRow[] = []; // 按 DFS 展开/折叠后实际渲染（扁平）的行列表

  aboutToAppear(): void {
    this.buildTree();
  }

  /**
   * 建树：按 parentId 分组 + 排序，初始化展开状态为「全展开」，并计算出可见行。
   * 展开集合把每个有子节点的父 ID 都放入，使初始即显示完整多级层级，便于用户挑选。
   */
  private buildTree(): void {
    this.nodeMap.clear();
    this.folders.forEach((cat: Category) => {
      const key = cat.parentId;
      const list = this.nodeMap.get(key);
      if (list) {
        list.push(cat);
      } else {
        this.nodeMap.set(key, [cat]);
      }
    });
    /* 同层统一按 sortOrder 升序，保证树顺序稳定 */
    this.nodeMap.forEach((list: Category[]) => {
      list.sort((a: Category, b: Category) => a.sortOrder - b.sortOrder || a.createdAt - b.createdAt);
    });
    /* 初始全展开：凡是「有子节点的父 ID」都加入展开集 */
    const expanded = new Set<string>();
    this.nodeMap.forEach((_children, parentId: string) => {
      if (parentId.length > 0) {
        expanded.add(parentId);
      }
    });
    this.expandedIds = expanded;
    this.recomputeVisible();
  }

  /**
   * 计算可见行：从根（parentId=""）开始 DFS 前序遍历。
   * 某个节点已折叠（不在 expandedIds）时，跳过其整棵子树。
   */
  private recomputeVisible(): void {
    const rows: FolderRow[] = [];
    const visit = (parentId: string, depth: number): void => {
      const children = this.nodeMap.get(parentId);
      if (!children) {
        return;
      }
      children.forEach((cat: Category) => {
        const sub = this.nodeMap.get(cat.id);
        const expandable = !!sub && sub.length > 0;
        const expanded = this.expandedIds.has(cat.id);
        rows.push(new FolderRow(cat, depth, expandable, expanded));
        if (expandable && expanded) {
          visit(cat.id, depth + 1);
        }
      });
    };
    visit("", 0);
    this.visibleRows = rows;
  }

  /* 折叠 / 展开：切换后重组可见行，触发 @Local 刷新 */
  private toggle(id: string): void {
    const next = new Set(this.expandedIds);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    this.expandedIds = next;
    this.recomputeVisible();
  }

  /* 点选：仅高亮，不提交（提交交给「确认」按钮） */
  private select(id: string): void {
    this.selectedId = id;
  }

  /* 确认：把当前选中的 ID 交回调并请求关闭 */
  private confirm(): void {
    this.onSelect(this.selectedId);
    this.onRequestClose();
  }

  build() {
    Column({ space: $r('app.float.space_xs') }) {
      /* 标题 */
      Text(this.title)
        .fontSize($r('app.float.font_title'))
        .fontWeight(800)
        .fontColor($r('app.color.font_primary'))
        .width("100%")
        .textAlign(TextAlign.Center)
        .padding({
          top: $r('app.float.space_sm'),
          bottom: $r('app.float.space_xs')
        })

      /* 「默认」选项：高亮即清空分类 / 移到顶级（selectedId = ""） */
      Row() {
        Text("默认")
          .fontSize($r('app.float.font_name'))
          .fontColor($r('app.color.font_primary'))
      }
      .width("100%")
      .height(40)
      .padding({
        left: $r('app.float.space_md'),
        right: $r('app.float.space_md')
      })
      .borderRadius(12)
      .backgroundColor(this.selectedId === "" ? $r('app.color.item_current_bg') : Color.Transparent)
      .onClick(() => {
        this.select("");
      })

      /* 文件夹树（可滚动，折叠/展开联动） */
      List() {
        ForEach(
          this.visibleRows,
          (row: FolderRow) => {
            ListItem() {
              this.folderRow(row)
            }
          },
          (row: FolderRow) => row.cat.id + (row.expanded ? "_exp" : "_col"), // key 含展开态：折叠/展开时强制该行重建，箭头样式随之刷新
        )
      }
      .width("100%")
      .height(360)

      /* 底部按钮区：取消 / 确认 */
      Row() {
        Text("取消")
          .fontSize($r('app.float.font_button'))
          .fontColor($r('app.color.font_emphasize'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({
            top: $r('app.float.space_md'),
            bottom: $r('app.float.space_xs')
          })
          .onClick(() => {
            this.onRequestClose();
          })
        Text("确定")
          .fontSize($r('app.float.font_button'))
          .fontColor($r('app.color.font_emphasize'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({
            top: $r('app.float.space_md'),
            bottom: $r('app.float.space_xs')
          })
          .onClick(() => {
            this.confirm();
          })
      }.width("100%")
    }
    .padding($r('app.float.space_lg'))
    .width("92%")
    /* 弹出框按官方规范用超大圆角（32vp） */
    .borderRadius($r('app.float.dialog_radius'))
    .backgroundColor($r('app.color.dialog_bg'));
  }

  /**
   * 单行文件夹渲染：左侧按 depth 缩进，图标+名称占主体可点击高亮选中，
   * 折叠箭头放行右侧（参考思考区域样式）。
   * 缩进基准 12vp，每深一层再 +20vp，直观体现父子层级。
   */
  @Builder
  private folderRow(row: FolderRow) {
    Row() {
      /* 图标 + 名称：点击高亮选中（缩进由父级 padding.left 承担，名称区左占满、把箭头挤到行尾） */
      Row() {
        SymbolGlyph($r("sys.symbol.folder"))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(600)
          .fontColor([row.cat.color])
          .margin({
            right: $r('app.float.space_xs')
          })
        Text(row.cat.name)
          .fontSize($r('app.float.font_name'))
          .fontColor($r('app.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .onClick(() => {
        this.select(row.cat.id);
      })

      /* 折叠/展开箭头（参考思考区域样式：放行右侧，展开 chevron_down、折叠 chevron_right，点击切换收/展） */
      if (row.expandable) {
        SymbolGlyph(row.expanded ? $r("sys.symbol.chevron_down") : $r("sys.symbol.chevron_right"))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(600)
          .fontColor([$r('app.color.font_secondary')])
          .margin({
            right: row.expanded ? $r('app.float.space_xs') : $r('app.float.space_sm')
          })
          .onClick(() => {
            this.toggle(row.cat.id);
          })
      }
    }
    .width("100%")
    .height(40)
    .padding({
      left: 12 + row.depth * 20, // 基础缩进(12vp=space_md) + 每层 20vp 层级缩进
      right: $r('app.float.space_xs')
    })
    .borderRadius(12)
    .backgroundColor(row.cat.id === this.selectedId
      ? $r('app.color.item_current_bg')
      : Color.Transparent)
  }
}

/**
 * 文件夹选择器的开放参数（ComponentContent 方式）
 * 用于将弹窗内容与调用方组件解耦：初始值 + 回调均通过 params 传入
 * 配合全局 @Builder buildFolderPickerContent 使用
 */
export class FolderPickerDialogParams {
  title: string = "移动到"; // 对话框标题（可传入覆盖）
  folders: Category[] = []; // 候选文件夹列表（含各级，扁平展示，组件内建树）
  onSelect: (folderId: string) => void = (folderId: string) => {}; // 确认选中回调
  onRequestClose: () => void = () => {}; // 关闭回调（父页面负责关闭弹窗）
}

/**
 * 全局 @Builder：包装 FolderPickerDialog，供 openCustomDialog(ComponentContent) 使用。
 * 注意：必须用全局函数而非组件成员 @Builder，才能规避成员 Builder 在弹窗场景的绑定/刷新问题
 */
@Builder
export function buildFolderPickerContent(params: FolderPickerDialogParams) {
  FolderPickerDialog({
    title: params.title,
    folders: params.folders,
    onSelect: (folderId: string) => {
      params.onSelect(folderId);
    },
    onRequestClose: () => {
      params.onRequestClose();
    },
  })
}