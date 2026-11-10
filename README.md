# Tactics Proto（晨星战旗 · 第 4 阶段原型）

**在线试玩**：https://wxj783428795.github.io/tactics-proto/
（需要支持 WebGL 2 的桌面浏览器。网页版是无线程导出，不需要特殊的服务器响应头。）

本仓库存放完整的 Godot 4.3 源码。每次推送到 `main`，GitHub Actions 都会自动跑测试、导出网页版并发布到上面的地址（见下文「自动发布」）。


原创的小队制即时大地图战略 + 战术规则自动战斗原型。现在已经有一段 3 章的小战役：经验升级、转职、装备、招募和存档。共 11 个职业：剑士、重甲、弓手、法师、牧师，以及新增的骑兵、刺客、盾卫、吟游者、枪兵、翔翼兵。职业说明和克制关系见 design_doc.md 第 5 节。引擎：**Godot 4.3**（标准版，GDScript，Compatibility 渲染器）。

## 运行
1. 下载 Godot 4.3 或更高版本（标准版）：https://godotengine.org/download
2. 打开 Godot → 导入 → 选择本文件夹里的 `project.godot` → 按 F5 运行（主场景是标题画面）。
   - 新游戏：先看序章，再进入营地。
   - 继续：读取存档。
   - 快速战斗：单场测试战斗。
   - 沙盒地图：原来的测试大地图。
3. 营地：
   - 选择章节，查看简报后出击。
   - 「部队管理」：编入小队、装备、转职、战术和编队。
   - 「招募」：用金币雇佣新成员。
   - 「存档」：手动存档。
   - 任务结束后进入战报界面，并且会自动存档。
4. 大地图操作：
   - 左键点我方小队，再点据点或路口，下达行军命令。
   - 选中我方小队后，左键点敌方小队就会追击（红色虚线），右键点任意小队只查看。
   - 空格暂停，F 键切换速度（1x / 2x / 4x）。
   - 右侧面板可以「编队」「战术」「原地停止」；战役中还可以「撤退」，沙盒模式是「保存」。
   - 敌我小队相遇时自动进入战斗：战前可以调整阵型、编辑战术，然后「开始战斗」或「跳过演出」，打完点「返回地图」。
   - 每章目标显示在左上角：攻陷大本营 / 坚守 N 秒 / 击败首领。
   - 我方据点每 10 秒产生资金。
   - 战斗后败方会被击退，双方原地整备 3 秒（地图上有倒计时圈）。
   - 大本营和要塞有耐久条：有守军时无法占领，每打赢守军一场就削减耐久，归零后守军溃退。
5. 单独测试战斗：在编辑器里打开 `scenes/battle_test.tscn` 并运行当前场景（F6）。

## 目录
- `scripts/battle_engine.gd`、`battle_unit.gd`：战斗逻辑（纯数据）
- `scripts/progression.gd`：经验、升级、转职、装备（纯函数）
- `scripts/campaign_state.gd`：名册、小队、金币、库存、任务进度、存档；`game.gd`：跨场景共享的静态状态
- `scripts/title_screen.gd`、`camp.gd`、`roster_screen.gd`、`story_scene.gd`、`results_screen.gd`：标题、营地、部队管理、剧情、战报
- `scripts/map_model.gd`、`squad.gd`：大地图逻辑（纯数据）
- `scripts/tactics_schema.gd`：战术条件与目标的定义，以及规则的增删和移动
- `scripts/overworld.gd`、`map_canvas.gd`：大地图界面
- `scripts/battle_view.gd`、`unit_cell.gd`：战斗界面
- `scripts/rule_editor.gd`、`formation_editor.gd`、`ui_util.gd`：编辑器弹窗
- `data/classes.json`：职业、技能、默认战术；`data/campaign.json`：地图、据点、小队、AI；`data/battle_setup.json`：单独战斗配置；`data/items.json`：道具；`data/campaign/`：战役任务、地图、招募（由 `tools/make_campaign_data.py` 生成）
- `tests/run_battle_test.gd`、`run_map_test.gd`、`run_class_test.gd`、`run_campaign_test.gd`、`run_siege_test.gd`、`run_pursuit_test.gd`：无头测试
- `tests/screenshot.gd`、`screenshot_classes.gd`、`screenshot_campaign.gd`：截图（需要图形环境）
- `docs/`：截图
- `assets/fonts/`：Noto Sans CJK SC 子集（SIL OFL 协议）。新增汉字后运行 `python3 tools/make_font_subset.py` 重新生成，否则网页版里新字会显示成方块。

## 添加新职业
在 `data/classes.json` 中，先在 `skills` 里添加技能（可用字段见文件开头的 `_comment`），再在 `classes` 里添加职业：填写数值、`tags`、`skills`、`passives`、`default_tactics`。然后在 `campaign.json` 或 `battle_setup.json` 里用职业 id 编入小队。如果需要新的战术条件，在 `battle_engine.gd` 的 `_resolve_targets` 和 `tactics_schema.gd` 的 `CONDITIONS` 里各加一项。最后运行 `tools/make_font_subset.py`。

## 添加章节 / 道具
- 道具：在 `data/items.json` 里添加，可以有 `stats` 和 `start_effects`。
- 章节：在 `data/campaign/missions.json` 的 `missions` 里加一项，写明 `map`、`goal`、`briefing`、`reward`、`join`、`pre_story`、`post_story`。
- 地图 JSON 的结构和 `campaign.json` 一样，另外支持这些字段：
  - `objective`：`capture_hq`、`defend` + `time`、`defeat_boss` + `squad`
  - `player_start`
  - 节点的 `gold` 和 `reward`
  - 敌方小队的 `ai.boss`

## 存档
- 战役进度（名册、等级、装备、战术、金币、库存、已通关章节）保存在 `user://campaign_save.json`。
- 沙盒地图的编队和战术保存在 `user://squad_setups.json`。桌面版位于 Godot 的用户数据目录；网页版保存在浏览器的 IndexedDB 里。

## 命令行
```bash
godot --headless --path . --import                                # 首次运行先导入资源
godot --headless --path . --script res://tests/run_battle_test.gd  # 战斗测试
godot --headless --path . --script res://tests/run_map_test.gd     # 大地图测试
godot --headless --path . --script res://tests/run_class_test.gd   # 新职业与新机制测试
godot --headless --path . --script res://tests/run_campaign_test.gd  # 成长 / 装备 / 名册 / 战役 / 存档 / 界面测试
godot --headless --path . --script res://tests/run_siege_test.gd     # 战后击退 / 整备 / 据点耐久 / 攻城回归测试
godot --headless --path . --script res://tests/run_pursuit_test.gd   # 追击敌方小队测试
godot --headless --path . --export-release Web build/web/index.html  # 导出网页版（需要先安装 4.3 导出模板）
```
网页版是无线程导出，不需要 SharedArrayBuffer 或 COOP/COEP 响应头，可以直接把 build/web 打成 zip 上传到 itch.io（选择 HTML 类型）。


## 自动发布（GitHub Actions → GitHub Pages）

工作流文件是 `.github/workflows/deploy-web.yml`。每次推送到 `main` 都会自动执行，也可以在 Actions 页面手动运行（workflow_dispatch）。步骤如下：
1. 下载 Godot 4.3-stable（Linux）和 4.3 网页导出模板，并用 `actions/cache` 缓存。
2. 用 `--headless --import` 导入项目。
3. 运行全部无头测试（battle / map / class / campaign / siege / pursuit），任何一项失败都会中止发布。
4. 导出 `Web` 预设（无线程）到 `build/web`，并加上 `.nojekyll`。
5. 用 `actions/upload-pages-artifact` 和 `actions/deploy-pages` 发布。

仓库设置里，Pages 的来源（Source）要选「GitHub Actions」。

**日常更新**：修改代码 → 本地跑测试 → `git commit` → `git push origin main`。等 Actions 变绿，几分钟后网页就会更新。

**备用方案**：如果 Actions 暂时不可用，可以在本机用 `tools/deploy_web.sh` 导出，然后推送到 `gh-pages` 分支。这时要把 Pages 的来源改成 `gh-pages` 分支。

`.godot/` 和 `build/` 不进仓库（见 `.gitignore`），首次打开项目时 Godot 会自动重新导入。
