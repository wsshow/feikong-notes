# 云间拾光

云间拾光（Cloud Reverie）是浅色主题，存储标识为 `sunnyGrowth`。切换后保留页面状态及原有明暗偏好。主题接入方式见[主题系统](theme-system.md)。

## 页面表现

- 首页与日历使用浅天空蓝渐变、白色表面、海军蓝文字和亮蓝主操作。底栏及安全区延续页面渐变底色。
- 标题使用静态太阳与云朵装饰，窄屏或大字号时隐藏。装饰跳过点击和无障碍焦点。
- 年历使用白色月份卡片，常规手机三列，窄屏或大字号减至两列或一列。周、日视图沿用直接浏览笔记的交互。
- 月历选中日期为蓝底白字，数量徽标为白底蓝字。今天使用描边，与选中态重合时保留“今”。零条隐藏徽标，超过 99 显示 `99+`，读屏提供完整数量。

## 设计源

- [tokens.json](../assets/themes/sunny_growth/tokens.json) 存放版本化的 `ref / sys / comp` 令牌。
- [sun_cloud.svg](../assets/themes/sunny_growth/sun_cloud.svg) 存放太阳与云朵矢量源。
- [sunny_growth_tokens.dart](../lib/theme/sunny_growth_tokens.dart) 由以上源文件生成。

更新设计源后在仓库根目录执行：

```sh
python3 tool/generate_sunny_growth.py
python3 tool/generate_sunny_growth.py --check
```
