# План миграции: разделение на kernel-fork repo + build-repo

> Статус: **черновик плана** (2026-04-27). Не утверждён, не запущен.
> Цель: уйти от sed/awk-патчей в build-time на «чистый» подход — форк ядра LineageOS с явными коммитами, текущий репо = только build-инфраструктура и доки.

## Зачем

Сейчас текущий репо смешивает три разные сущности:

1. **Build-инфраструктура** (`scripts/`, Docker pipeline, AnyKernel3 zip-генератор)
2. **Source-патчи к ядру и драйверам**, применяемые на лету через `sed`/`awk`/`git am` внутри `scripts/03-apply-patches.sh` (Realtek CFI fix PR #1041, hh_msgq.h fix, msm_cvp_ioctl.c fix, qcacld Kbuild relax, Kali QCACLD inject 17-patch series)
3. **Артефакты готовой сборки** (`artifacts/Module.symvers` 14K строк, `artifacts/kernel.config` 7K строк, `running-config.gz`, `installers/*.apk` 46 МБ, `modules/*.ko`, `magisk-realtek-wifi/system/lib/modules/*.ko`)

Минусы такого подхода:
- Каждый `sed`/`git am` — это «магия» во время сборки, без diff'а который видно как кommit. Изменения upstream (LOS bumps до lineage-23.3 / 24.0, новый Android) могут сломать sed-pattern'ы беззвучно.
- Нет «истории ядра» в человеческом виде — нельзя посмотреть `git log` и увидеть «что мы добавили поверх LOS».
- Артефакты сборки в repo раздувают `git clone` (Module.symvers 14K + kernel.config 7K + три `.ko` файла + три `.apk` ~46 МБ + magisk module duplicate). При следующей пересборке всё пойдёт в diff и история раздувается.
- Невозможно легко догнать upstream LOS — нет понятия «у меня kernel поверх вот этого LOS-tag'а, мне надо rebase».

После миграции:
- **Repo `nothing-phone-1-spacewar-kernel`** — форк `LineageOS/android_kernel_nothing_sm7325` ветка `lineage-23.2`. Поверх — ветка `nethunter-23.2-spacewar` с 8-12 явными коммитами (cherry-pick от kimocoder + наши source-патчи). Когда LOS обновляет `lineage-23.2` (или появляется `lineage-23.3`) — `git rebase` нашей ветки на новую базу. Diff с upstream всегда виден через `git log lineage-23.2..nethunter-23.2-spacewar`.
- **Repo `nothing-phone-1-nethunter-kernel`** (текущий) — только build-pipeline: Docker scripts, AnyKernel3 packaging, доки, `running-config.gz`, готовые Magisk-модули.

## Структура после миграции

### Repo 1 — kernel fork

```
nothing-phone-1-spacewar-kernel/
├── (вся структура Linux 5.4 kernel source — десятки тысяч файлов)
└── (на ветке nethunter-23.2-spacewar поверх lineage-23.2 — наши коммиты)
```

**Ветки:**
- `lineage-23.2` — точная копия `LineageOS/android_kernel_nothing_sm7325 lineage-23.2`. Используем для regular pull от upstream.
- `nethunter-23.2-spacewar` — рабочая ветка. Поверх lineage-23.2:

**План коммитов на ветке `nethunter-23.2-spacewar` (поверх `lineage-23.2`):**

```
nh01: backports: import 5.10 mac80211 backports for USB-WiFi support
      (cherry-pick of kimocoder eac4e43e + 81e70195)

nh02: qcacld-3.0: enable direct monitor mode through 'iw' command
      (cherry-pick of kimocoder 49b30b46 — single source patch in qcacld
      that lets `iw set type monitor` work on internal wlan0 alongside con_mode=4)

nh03: configs: add NetHunter defconfig fragments
      (cherry-pick of kimocoder cc9a1d37 + 3e8845d5 — adds NetHunter-specific
      kconfig fragments to arch/arm64/configs/)

nh04: scripts: remove localversion strings to keep -qgki suffix clean
      (cherry-pick of kimocoder 674cdaf3)

nh05: haven/hh_msgq.h: fix int functions returning ERR_PTR
      (replaces sed in scripts/03-apply-patches.sh — five static inline stubs
      fixed to return -ENODEV/-EINVAL instead of ERR_PTR(...))

nh06: media: msm_cvp_ioctl: add missing #include <linux/compat.h>
      (replaces sed — needed for compat_ptr() builtin)

nh07: drivers/staging/qcacld-3.0: relax -Werror=enum-conversion in Kbuild
      (replaces sed — needed for the Kali inject patch series to build under
      AOSP Clang)

nh08: qcacld-3.0: import Kali NetHunter frame injection vendor commands
      (squash of all 17 Kali QCACLD inject patches into one commit — easier
      to rebase than 17 individual patches. Adds wlan_hdd_frame_inject.{c,h},
      vendor commands 200/201/202, hooks throughout HDD/SME/WMA layers.)

nh09 (TBD): qcacld-3.0: CFI signature fix for inject codepath
      (UNRESOLVED — would require reading panic stacktrace from internal
      wlan0 inject and patching function pointers in QCACLD inject path
      to match CFI hashes. Tracked as future work.)
```

Itого 8 коммитов сейчас + 1 потенциальный (nh09). Чисто. При обновлении upstream lineage-23.2 → `git fetch upstream` → `git rebase upstream/lineage-23.2`. Конфликты только если LOS трогал именно те файлы что и мы — для Realtek/QCACLD/inject это редко.

**Realtek out-of-tree драйверы — НЕ в этот repo.** Они отдельные upstream-проекты (`aircrack-ng/rtl8188eus`, `morrownr/*`). Делаем для них свои отдельные мини-форки или просто храним патчи как `.patch` файлы в build-repo (см. ниже).

### Repo 2 — build / packaging (этот, оставшийся)

```
nothing-phone-1-nethunter-kernel/
├── README.md                          (упрощённый — указатель на kernel-fork repo)
├── docs/
│   ├── BUILD.md                       (обновлён под новый flow)
│   ├── BUILD-LOG-2026-04-26.md        (исторический, оставить как есть)
│   ├── CFI-FIX.md                     (объяснение PR #1041 — оставить, теперь повёрнуто на «уже в kernel fork»)
│   ├── INTERNAL-WIFI-MONITOR.md       (без изменений)
│   ├── CONTINUE-ON-NEW-PC.md          (упростить под новый flow)
│   ├── DIAGNOSTICS.md                 (исторический)
│   ├── FLASH.md                       (без изменений)
│   ├── MERCUSYS-USB-MODESWITCH.md     (без изменений)
│   └── MIGRATION-PLAN.md              (этот файл — после миграции переименовать в HISTORY)
├── scripts/
│   ├── 01-setup-container.sh          (как есть)
│   ├── 02-clone-sources.sh            (СУЩЕСТВЕННО упрощается — клонирует наш kernel-fork
│   │                                  + 3 Realtek-драйвера + AnyKernel3, всё)
│   ├── 03-apply-patches.sh            (упрощается — теперь только Realtek CFI sed-patch
│   │                                  + Focaltech firmware blob fetch, всё остальное
│   │                                  уже в kernel-fork-репо)
│   ├── 04-configure.sh                (как есть — running-config.gz approach)
│   ├── 05-build-kernel.sh             (как есть)
│   ├── 06-build-modules.sh            (как есть)
│   ├── 07-package-zip.sh              (как есть)
│   └── configs/
│       └── (опц. minor extras)
├── realtek-patches/                   (новая папка — патчи для out-of-tree drivers
│                                       которые ещё не вмержили upstream)
│   ├── rtl8188eus-cfi-fix-pr1041.patch
│   ├── 88x2bu-20210702-cfi-fix-pr1041.patch
│   └── 8821cu-20210916-cfi-fix-pr1041.patch
├── magisk-modules/
│   └── realtek-wifi-cfi-fix/          (source layout уже есть — переименовать корректно)
├── installers/                        (рассмотреть удаление .apk — см. ниже)
├── modules/                           (рассмотреть удаление .ko — см. ниже)
├── running-config.gz                  (важно — оставляем, источник истины конфига)
└── artifacts/                         (рассмотреть удаление — см. ниже)
```

### Что вычистить из текущего репо (предложение)

Эти файлы дублируются или пересобираются — не должны жить в git:

| Путь | Размер | Причина удаления |
|---|---|---|
| `artifacts/Module.symvers` | 14K строк | Регенерируется на каждой сборке. Источник истины для воспроизводимости — `running-config.gz` (config), не Module.symvers (которые из неё выводятся). |
| `artifacts/kernel.config` | 7K строк | То же что `gunzip running-config.gz` — дубликат. |
| `artifacts/kernel.release` | 1 строка | Просто строка `5.4.302-qgki-...-dirty`. Не критично, но можно убрать в README. |
| `artifacts/realtek-patches/*.patch` | 500 строк | Переезжают в новый `realtek-patches/` корня репо. |
| `installers/*.apk` | ~46 МБ | Magisk и NetHunter APK — это third-party бинарники. Лучше скачивать по URL в `scripts/00-download-installers.sh`. |
| `modules/{8188eu,88x2bu,8821cu}.ko` | ~13 МБ | Build artifacts; пересобираются `scripts/06-build-modules.sh`. Если хочется хранить готовый — выпускать GitHub Release с zip'ом. |
| `magisk-realtek-wifi/system/lib/modules/*.ko` | ~13 МБ | Дубликат `modules/`. Magisk-модуль packaging при сборке копирует .ko на лету. |
| `running-config.gz` | 40 КБ | **Оставить.** Это reproducibility token, ~критично. |

### Также — несоответствие путей в скриптах (баг сейчас)

Сейчас в `02-clone-sources.sh:23` репо клонируется в `/work/kernel`. Но `03-apply-patches.sh:20`, `04-configure.sh:38`, `05-build-kernel.sh:11`, `06-build-modules.sh:13` обращаются к `/work/kernel-los/...`. И `07-package-zip.sh:14` снова к `/work/kernel/...`.

Это не запустится «из коробки» — где-то скрипты ссылаются на `kernel-los`, где-то на `kernel`. По итогу сборки вчера, видимо, переименовывали вручную или клонировали два раза. **Перед запуском скриптов это надо исправить.** В плане миграции — унифицировать всё на одно имя (предлагаю `/work/kernel-los`, чтобы было однозначно «LineageOS kernel»).

## Последовательность миграции (черновик)

### Этап 1 — подготовка kernel-fork локально (без push)

1. Создать локальный bare clone upstream LOS: `git clone https://github.com/LineageOS/android_kernel_nothing_sm7325 -b lineage-23.2 ../spacewar-kernel-fork`. (Это ~3 ГБ shallow — лучше `--depth 100` чтобы потом нормально rebase делать.)
2. Завести ветку `nethunter-23.2-spacewar`.
3. Cherry-pick 7 коммитов kimocoder из `nethunter-23.0` (см. nh01-nh04 выше). Конфликты возможны на defconfig — разрешаем руками.
4. Применить наши source-патчи как 4-5 явных коммитов (см. nh05-nh08 выше).
5. Локально собрать через текущие `scripts/` (с правкой имени `kernel-los` и заменой `git clone` URL'а в `02-clone-sources.sh` на наш fork) — убедиться что vermagic совпадает с running-config.
6. **Только после успешной локальной сборки** — `gh repo create` и push (требует подтверждения пользователя).

### Этап 2 — обновление текущего репо

1. Удалить `artifacts/`, `installers/*.apk`, дубликаты `.ko` (требует подтверждения — это удаление; GitHub release как альтернатива хранения).
2. Обновить `scripts/02-clone-sources.sh` — использовать наш kernel-fork URL.
3. Сильно упростить `scripts/03-apply-patches.sh` — убрать sed-патчи которые теперь в kernel-fork; оставить только Realtek CFI sed (или вынести в `.patch` файлы и применять `git apply`).
4. Унифицировать пути `/work/kernel` vs `/work/kernel-los` (текущий баг).
5. Обновить README.md / CONTINUE-ON-NEW-PC.md под новый flow.
6. Создать `realtek-patches/` с тремя `.patch` файлами для CFI fix (можно просто перенести из `artifacts/realtek-patches/`).
7. Финальный test build чтобы убедиться что новый pipeline работает.
8. Commit + push.

### Этап 3 — verify

1. Запустить полный pipeline на чистой машине.
2. `vermagic` итогового `wlan.ko` и Realtek `.ko` должны совпадать с running-config.gz.
3. Поднять monitor mode на phone — без panic.

### Что требует подтверждения пользователя (не делаю в auto)

- `gh repo create ilyamen/nothing-phone-1-spacewar-kernel --public` (новый remote)
- `git push` нового форка
- Удаление файлов из текущего репо (`artifacts/`, `installers/*.apk`, `modules/*.ko`)
- Force-push в текущий repo если что-то пойдёт не так

### Что можно делать в auto

- Локально клонировать LOS upstream
- Локально готовить cherry-pick'и и коммиты на feature-ветке
- Править скрипты в текущем репо
- Создавать черновики документов
- Обновлять память

## Открытые вопросы

1. **Naming для нового repo.** Варианты:
   - `nothing-phone-1-spacewar-kernel`
   - `kernel-nothing-spacewar`
   - `android_kernel_nothing_sm7325` (мирроринг наименования upstream)
2. **Видимость нового repo:** public или private?
3. **Хранить ли в build-repo `.ko` для quick install** (через GitHub Release zip, не git LFS)?
4. **Realtek драйверы:** просто хранить три `.patch` файла в build-repo, или сделать три отдельных мини-форка `realtek-{8188eu,88x2bu,8821cu}-spacewar` с применённым CFI fix?
   - За один-репо-патчи: проще, не размножать репо.
   - За три форка: чище для долгосрочной поддержки, можно следить за upstream через git remote, делать PR обратно в `aircrack-ng`/`morrownr`.
   - Рекомендация по умолчанию: оставить как `.patch` файлы. Три форка — overkill для трёх drivers.
5. **QCACLD inject CFI fix (nh09):** делать сейчас в рамках миграции или отложить на отдельную задачу? Это может занять много часов — лучше отдельно.
