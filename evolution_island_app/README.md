# 达尔文进化岛 (Darwin Evolution Island)

一个**独立、现代（Dart 3 / 空安全）**的 Flutter 工程，零第三方依赖（只用 Flutter
SDK 自带库），可直接在本机运行与继续开发。你在遍布怪物的孤岛上从一只弱小的史莱姆
开始，击杀怪物获取经验，不断进化成更强的生命形态，最终成为统治全岛的远古巨龙。

## 快速开始

最省事的方式是用自带脚本（会自动补齐平台目录并运行）：

```bash
cd evolution_island_app
./run.sh               # 默认设备
./run.sh -d chrome     # 指定设备，参数会透传给 flutter run
```

或手动运行。本仓库只提交了源码（`lib/`），未提交各平台的样板目录，
首次运行前先用 `flutter create .` 生成它们（只会写入 web/android/ios/
桌面 等运行壳，不会改动 `lib/`）：

```bash
cd evolution_island_app
flutter create .       # 仅首次需要，生成 web/android/ios/... 平台目录
flutter pub get
flutter run            # 或 flutter run -d chrome / -d macos / -d <设备>
```

> 已用 Flutter stable + Dart 3 验证：`flutter analyze` 0 错误、`flutter test`
> 通过、`flutter build web` 编译成功。

运行后在终端按 `r` 热重载、`R` 热重启，改完代码即时生效。

## 玩法

- **移动**：在屏幕任意位置按住并拖动，触发虚拟摇杆控制方向。
- **攻击**：自动攻击范围内最近的怪物（近战阶段挥击，远程阶段喷射火球）。
- **进化**：击杀怪物获得经验，升级后随等级解锁新形态，进化时回满血并短暂无敌。
- **生存**：被怪物接触或击中会扣血，HP 归零即游戏结束，可立即重开。

## 进化链

| 阶段 | 名称 | 解锁等级 |
| --- | --- | --- |
| 1 | 幼苗史莱姆 | Lv.1 |
| 2 | 利齿蜥蜴 | Lv.3 |
| 3 | 影狼 | Lv.6 |
| 4 | 岩石巨兽 | Lv.10 |
| 5 | 烈焰翼龙 | Lv.15 |
| 6 | 远古巨龙 | Lv.21 |

怪物种类（甲虫、暗影蝙蝠、狂暴野猪、剧毒巨蛙、岩石魔像、火焰元素）随等级
逐步解锁，强度也随等级提升，让孤岛始终保持挑战。

## 代码结构

- `lib/models.dart` — 进化阶段、怪物种类与各类游戏实体的数据模型。
- `lib/painter.dart` — 程序化绘制岛屿、生物与特效的 `CustomPainter`（无图片资源）。
- `lib/game_screen.dart` — 游戏主循环、操作输入、战斗逻辑与 HUD。
- `lib/main.dart` — 应用入口。

## 继续开发的一些方向

- 数值平衡：调整 `models.dart` 里各阶段/怪物的 HP、攻击、速度、经验等常量。
- 新内容：在 `CreatureForm` 加新形态、在 `kMonsterTypes` 加新怪物、扩展进化链。
- 系统玩法：BOSS、技能/装备、最高分存档（可加 `shared_preferences`）、音效等。
