# 红魔 8S Pro+（NX729J）Droidspaces 内核构建配方

[English](README.en.md) | 简体中文

为红魔 8S Pro+（NX729J，骁龙 8 Gen 2 / SM8550）构建带 [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS)
容器支持的 GKI 内核。

> 纯 AI 构建项目（DeepSeek V4 Flash + Codex）

## 这个仓库解决什么问题

Droidspaces 需要内核开启 PID / IPC 命名空间、SYSVIPC 等选项，而绝大多数原厂 GKI 内核都没开
（红魔 8S Pro+ 就没有）。同时这些选项会改动 `task_struct` 大小，直接把 374 个预编译厂商模块的
符号 CRC 全部撞坏，结果是**开机即黑屏**。

本仓库记录的做法是：

1. **用出厂内核自己的源码树和提交**（Google ACK `android13-5.15`，提交 `b1f32b310a30`）；
2. **用手机自身的 `/proc/config.gz` 作为配置基准**（而不是魔改 defconfig）；
3. 只叠加 Droidspaces 需要的选项；
4. 打上 Droidspaces 官方的 **kABI padding 补丁**，让 SYSVIPC 走 Android 预留的 ABI 占位槽，
   从而**不改变任何导出符号的 CRC**；
5. 关闭 `TRIM_UNUSED_KSYMS`，导出全部符号（只会比原厂更全，不会更少）。

结果：厂商模块加载行为与出厂内核完全一致。

## 验证结果（本机型实测）

对手机上全部 **374 个厂商内核模块**（`vendor_dlkm` 270 个 + `vendor_boot` ramdisk 里另有 300 余个）
做了逐符号 CRC 比对：

```
modules with real problems : 0
truly missing symbols      : 0
crc mismatches             : 0
```

> 注意：光比对 `/vendor/lib/modules` 是不够的——大量符号（`qcom_scm_*`、`gh_rm_*`、`llcc_slice_*`、
> `ipc_log_*`）由藏在 **`vendor_boot` ramdisk** 里的模块导出，必须一并纳入比对，否则会误报"缺失"。
> `check_crc.py` 已按此处理。

## 文件说明

| 文件 | 说明 |
|---|---|
| `nx729j-RedMagicOS10.0.12.config` | 手机原厂内核配置全文（`/proc/config.gz` 导出）|
| `config.fragment` | 本配方新增/关闭的选项清单 |
| `patches/001.GKI...patch` | Droidspaces 官方 kABI 补丁（GPL-3.0，来源见 `patches/README.md`）|
| `build.sh` | 一键构建脚本 |
| `check_crc.py` | 刷机前的厂商模块符号 CRC 验证脚本（**强烈建议先跑**）|

## 构建

```bash
sudo apt install build-essential bc bison flex libssl-dev libelf-dev \
                 cpio lz4 zstd dwarves python3 kmod clang-14 lld-14 llvm-14
./build.sh
```

产物：`$WORK/ack/arch/arm64/boot/Image`

> `LTO_CLANG_FULL` 在链接阶段需要约 15GB 内存；内存小的机器可以改用 ThinLTO
> （Google GKI 官方用的就是它，不影响 ABI 与 CRC）：
> `scripts/config --disable LTO_CLANG_FULL --enable LTO_CLANG_THIN`

## 刷机（只动 boot_b）

```bash
# 备份原厂
su -c "dd if=/dev/block/by-name/boot_b of=/sdcard/boot_b-stock.img bs=1M"

# 用 magiskboot 把新内核放回原厂 boot 镜像（保留头部/命令行/vbmeta）
magiskboot unpack boot_b-stock.img
cp Image kernel
magiskboot repack boot_b-stock.img boot_b-new.img

# 刷入（fastboot 或手机内 dd）
fastboot flash boot_b boot_b-new.img
```

**不要动 `init_boot`**：KernelSU (LKM) 的 `kernelsu.ko` 在那里，动它就会丢 root。

## 已实测的功能（红魔 8S Pro+ / RedMagicOS 10.0.12）

| 项目 | 结果 |
|---|---|
| 内核启动 | 正常 |
| WiFi / 显示 / 蓝牙 / 音频 / 相机 | 正常（厂商模块全部加载）|
| KernelSU root | 保留（LKM 在 `init_boot`）|
| Droidspaces 需求检查 | 必须项全部通过 |
| Debian 13 容器 | systemd 作为 PID 1，`is-system-running = running` |
| 容器网络 | NAT + DNS 正常，apt 从阿里云镜像可用 |
| GPU 节点 | `/dev/kgsl-3d0`、`/dev/dri/renderD128` 已镜像进容器 |
| Turnip 硬件 Vulkan | 未通过：发行版自带 Mesa 未编入 Android 的 kgsl 后端；需按官方文档使用 Mesa-for-Android-Container 构建 |

## 许可

构建脚本与本仓库文档：GPL-2.0（与内核一致）。
`patches/` 下的补丁来自 Droidspaces 项目，遵循其 GPL-3.0 许可。
