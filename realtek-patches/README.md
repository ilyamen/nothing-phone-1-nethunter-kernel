# Realtek out-of-tree driver patches

Каждый файл — стандартный `git format-patch`-style diff поверх соответствующего upstream-репо. Применяется через `git apply <file>` или `patch -p1 < <file>` из корня дерева драйвера.

| Patch | Применять к | Upstream URL |
|---|---|---|
| `rtl8188eus-cfi-fix.patch` | `aircrack-ng/rtl8188eus` (master) | https://github.com/aircrack-ng/rtl8188eus |
| `88x2bu-20210702-cfi-fix.patch` | `morrownr/88x2bu-20210702` (main) | https://github.com/morrownr/88x2bu-20210702 |
| `8821cu-20210916-cfi-fix.patch` | `morrownr/8821cu-20210916` (main) | https://github.com/morrownr/8821cu-20210916 |

## Что включает каждый патч

Каждый из трёх файлов трогает 6 файлов драйвера:

1. **`Makefile`** — ARM64 platform fix:
   - Добавляет `-DCONFIG_LITTLE_ENDIAN -DCONFIG_IOCTL_CFG80211 -DRTW_USE_CFG80211_STA_EVENT -DCONFIG_PLATFORM_ANDROID -fno-pic` в `EXTRA_CFLAGS`
   - Удаляет `-DRTW_ENABLE_WIFI_CONTROL_FUNC` (нужен только на полноценном Android с WiFi HAL — у нас его нет)
   - Удаляет `-Wno-stringop-overread` и `-Wno-enum-int-mismatch` (не понимаются современным AOSP Clang)

2. **`os_dep/linux/os_intfs.c`** — `MODULE_IMPORT_NS(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver)` без `#if`-гарда. Драйверы по умолчанию обёртывают этот импорт в `#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5,10,0))`, но наш kernel 5.4 тоже требует его — иначе `insmod` падает с `Unknown symbol kernel_read`.

3. **`include/usb_ops_linux.h` + `os_dep/linux/usb_ops_linux.c`** — CFI signature fix:
   - `void usb_recv_tasklet(void *priv)` → `void usb_recv_tasklet(unsigned long priv)`
   - Источник: PR #1041 от GeorgeBannister в `aircrack-ng/rtl8812au`. Без этого `iw set type monitor` крашит ядро на CFI=on.

4. **`include/xmit_osdep.h` + `os_dep/linux/xmit_linux.c`** — CFI signature fix:
   - `int _rtw_xmit_entry(_pkt*, _nic_hdl)` → `netdev_tx_t _rtw_xmit_entry(struct sk_buff*, struct net_device*)`
   - То же для `rtw_xmit_entry`
   - Внутри: `int ret = 0;` → `netdev_tx_t ret = NETDEV_TX_OK;`
   - Источник: тот же PR #1041.

## Применение

Из `scripts/03-apply-patches.sh` — после `git clone` соответствующего upstream-репо:

```bash
cd /work/rtl8188eus           && git apply /work/realtek-patches/rtl8188eus-cfi-fix.patch
cd /work/88x2bu-20210702      && git apply /work/realtek-patches/88x2bu-20210702-cfi-fix.patch
cd /work/8821cu-20210916      && git apply /work/realtek-patches/8821cu-20210916-cfi-fix.patch
```

Если upstream драйвер обновится и патч больше не применяется чисто — открыть конфликт, разрулить вручную, обновить `.patch` файл (`cd <driver> && git diff > /work/realtek-patches/<name>.patch`).

## Почему out-of-tree, а не in-tree

Эти драйверы — отдельные проекты Realtek-сообщества. Их upstream регулярно обновляется (новые баги, поддержка новых ревизий чипов). Хранить их копию в нашем kernel-fork означало бы вручную синхронизировать ~50 МБ чужого кода при каждом upstream-апдейте.

Out-of-tree подход:
- Драйверы клонируются в build-time из их upstream
- Наши правки накладываются как .patch (видно построчно что мы изменили)
- При обновлении upstream — `git apply` либо проходит чисто, либо мы быстро разрулим конфликт в маленьком патче
- Skрипт `scripts/06-build-modules.sh` собирает их как `.ko` против нашего собранного ядра
