# 达尔文进化岛 · Unity 3D 版

一个 **Unity 3D** 单人小游戏：孤岛上遍布动物，玩家自动攻击，敌人分**近战**和
**远程**两种攻击方式。所有 3D 模型都是**运行时用基础几何体程序化拼出来的**
（Cube / Sphere / Capsule / Cylinder），所以仓库里**没有任何二进制模型资源**，
复制脚本即可运行。

## 特性对照你的需求

- ✅ **Unity + 3D 建模**：玩家（绿色小英雄）、近战动物（红色野猪）、远程动物
  （紫色喷射蛙）、树木、岩石、海岛全部用 3D 基础体程序化生成。
- ✅ **操作简单，控制上下左右**：方向键或 WASD 在岛上移动，仅此而已。
- ✅ **自动攻击**：玩家会自动朝范围内最近的敌人发射弹丸，无需任何攻击键。
- ✅ **两种攻击方式的动物**：
  - 近战动物：冲向玩家，贴身撕咬。
  - 远程动物：与玩家保持距离、放风筝，远远吐出毒弹。

附带：等级/经验/击杀 HUD、敌人头顶血条、升级变强变大、阵亡后一键重开。

## 运行方式（零配置）

得益于 `[RuntimeInitializeOnLoadMethod]`，整套游戏会在按下 Play 时自动搭建
（相机、灯光、海岛、玩家、敌人、UI 全部代码生成），**无需手动搭场景、连引用**。

1. 用 Unity Hub 新建一个 **3D 工程**（建议 Unity 2021 LTS 或更新版本）。
2. 把本目录下的 `Assets/EvolutionIsland3D` 整个文件夹拷到你工程的 `Assets/` 下。
3. 直接按 **Play**。空场景也能跑（默认的 SampleScene 即可）。

> 也可以直接用 Unity Hub「Add project from disk」打开 `evolution_island_unity`
> 这个目录本身（首次打开 Unity 会自动生成 `Library/`、`ProjectSettings/` 等）。

## 操作

| 操作 | 按键 |
| --- | --- |
| 移动（上下左右） | 方向键 或 W A S D |
| 攻击 | 自动（朝最近敌人开火） |
| 阵亡后重开 | 按 R 或点击「再来一局」 |

## 两点环境提示（新版 Unity 可能需要）

1. **输入系统**：代码用的是传统 `Input`（`Input.GetAxisRaw`）。如果你的工程只启用了
   新版 Input System，移动会失效。改法：`Edit > Project Settings > Player >
   Active Input Handling` 设为 **Both** 或 **Input Manager (Old)**。
2. **渲染管线**：代码直接给图元默认材质设颜色，Built-in 和 URP 都能正常显示，
   一般无需改动。

## 代码结构（`Assets/EvolutionIsland3D/Scripts/`）

| 文件 | 职责 |
| --- | --- |
| `GameBootstrap.cs` | 按 Play 自动启动游戏（零配置入口）。 |
| `GameManager.cs` | 搭建世界、相机跟随、刷怪、等级/击杀、HUD、重开。 |
| `PlayerController.cs` | 玩家移动（上下左右）+ 自动攻击。 |
| `Enemy.cs` | 敌人 AI：近战追击 / 远程放风筝两套行为。 |
| `Projectile.cs` | 弹丸飞行与命中判定（玩家与远程敌人共用）。 |
| `CreatureBuilder.cs` | 用基础几何体程序化拼出各种 3D 模型与场景物件。 |

## 继续扩展的方向

- 在 `CreatureBuilder` 里增加新动物造型；在 `GameManager.SpawnEnemy` 里加新种类。
- 数值平衡：调 `GameManager` 里刷怪与等级成长、`PlayerController` 的攻击参数。
- 进阶：BOSS、技能/进化形态、掉落与拾取、音效、用真正的美术模型替换程序化模型。

---

> 说明：本工程的 C# 已用 Mono `mcs` 对照 Unity API 做过离线编译校验（语法与跨文件
> 引用均通过）。但**完整运行/画面表现需在 Unity 编辑器中验证**——当前开发环境
> 没有 Unity，无法实跑。如运行中遇到问题，把报错发我即可。
