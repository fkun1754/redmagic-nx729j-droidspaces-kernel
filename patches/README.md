# patches/

`001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch` comes from the Droidspaces
project (GPL-3.0):

https://github.com/ravindu644/Droidspaces-OSS/tree/main/Documentation/resources/kernel-patches/GKI/below-kernel-6.12

It moves `struct sysv_sem` / `struct sysv_shm` out of their normal place in
`struct task_struct` and into the ABI padding slots Android already reserves
(`ANDROID_KABI_USE(6, ...)`), so `CONFIG_SYSVIPC` and `CONFIG_IPC_NS` can be
enabled without changing the size or layout of `task_struct`. That is what keeps
every exported symbol CRC identical to the stock kernel, and therefore keeps all
prebuilt vendor modules loadable.

If a device bootloops (vendor modules refusing to load), the same folder has
alternates that use different padding slots:

* `001.GKI-below-6.12-fix_sysvipc_kabi_1_2_3.patch`
* `001.GKI-below-6.12-fix_sysvipc_kabi_3_4_5.patch`
