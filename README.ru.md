# Keenetic Entware Flash

**Подготовка USB-флешки для Entware на роутерах Keenetic и Netcraze — одной командой.**

[English](README.md) | [中文](README.zh.md)

Пошаговые команды для проверки на Mac: [TESTING.ru.md](TESTING.ru.md).

## Быстрый старт

Вставьте USB-флешку и выполните:

```bash
git clone https://github.com/onepyad/keenetic-entware-flash.git
cd keenetic-entware-flash
# macOS: install/check Homebrew, Python and e2fsprogs first
if [ "$(uname -s)" = Darwin ]; then bash setup-macos.sh; fi
sudo bash run.sh
```

Скрипт попросит отключить остальные накопители и выберет единственную флешку:

```
Отключите все остальные флешки и внешние диски.
Оставьте подключённой только флешку, которую хотите подготовить.
Когда готово, нажмите Enter (или введите 0 для отмены):
  Media Name: USB DISK 2.0
  Disk Size: 16.0 GB (...)
Автоматически выбрана флешка: /dev/disk4
```

Docker проверяется до выбора накопителя. На Linux доступна запись без Docker; в режиме Docker образ скачивается или собирается локально.

## Требования

Что нужно — зависит от запускаемого скрипта:

| Скрипт | macOS | Linux |
|--------|-------|-------|
| `run.sh` (запись флешки) | Homebrew + Python + e2fsprogs **или** Docker Desktop + Python | Docker **или** `parted`, `e2fsprogs`, `util-linux`, `kpartx` |
| `clone.sh backup` | встроено (`dd`, `diskutil`) | встроено (`dd`, `lsblk`) |
| `clone.sh restore` (с авто-расширением) | Docker Desktop | `parted`, `e2fsprogs`, `util-linux`, `kpartx`, `gdisk` |
| `clone.sh restore --no-expand` | встроено | встроено |
| `check.sh` (quick / full / write) | встроено | встроено |
| `check.sh entware` (глубокая проверка) | `e2fsprogs` (Docker не нужен) | `e2fsprogs` |

### macOS

```bash
# Docker Desktop — нужен для run.sh и для clone.sh restore с расширением ext4.
# macOS не умеет менять размер ext4 нативно, поэтому это делает Linux-контейнер.
brew install --cask docker
# затем один раз запустите Docker Desktop, чтобы поднялся демон

# e2fsprogs — нужен для check.sh entware и проверки целостности ext4.
# Даёт e2fsck и debugfs. Homebrew ставит keg-only (не в PATH);
# check.sh находит их в кеге автоматически.
brew install e2fsprogs

# ddrescue — нужен только для спасения умирающей флешки (см. «Восстановление умирающей флешки»).
brew install ddrescue
```

> В Docker Desktop file sharing должен разрешать `/Users` (по умолчанию так и есть).
> `clone.sh` кладёт временные образы в `~/.cache/keenetic-flash`, чтобы контейнер
> мог их примонтировать.

### Linux

```bash
# Debian / Ubuntu (и большинство хостов-роутеров)
sudo apt install docker.io parted e2fsprogs util-linux kpartx gdisk gddrescue

# Docker на Linux опционален: run.sh и clone.sh могут использовать системные утилиты.
```

## Поддерживаемые модели

Выбор платформы выполняется по точному коду модели **KN-xxxx** (Keenetic)
или **NC-xxxx** (Netcraze). Архитектура компьютера не влияет на выбор установщика.
Полный проверенный список, ссылки на руководства производителей и архивы:
[Платформы и установщики](docs/platforms.md).

| Платформа | Keenetic: примеры | Netcraze: подтверждённые модели |
| --- | --- | --- |
| `mipsel` | KN-1810, KN-3810, KN-1010/1011 | Viva NC-1913 |
| `mips` | KN-2410, KN-2510, KN-2010, KN-2110, KN-3610 | Подтверждённых моделей NC в списке нет |
| `aarch64` | KN-2710, KN-1811/1812, KN-1012, KN-3811/3812 | Giga NC-1012/1013, Ultra NC-1812, Hopper NC-3811, Hopper SE NC-3812, Hopper 4G+ NC-2312, Hopper DSL NC-3611, Hero 5G NC-4110, Titan SE NC-4210 |

Launcher NC-1221 и Carrier NC-1721 имеют USB только для модемов и не подходят
для установки OPKG на USB-диск. Для неизвестной модели скрипт не назначает
платформу автоматически: проверьте руководство, затем укажите `--arch`.

```bash
./run.sh --list-platforms
sudo ./run.sh --model NC-1812 /dev/sdX
# Только скачать архив: без sudo, Docker и работы с накопителями
./run.sh --model NC-1013 --download-installer ./installers
./run.sh --model KN-2410 --installer-language en --download-installer ./installers-en
```

### Если Docker не установлен

На Linux скрипт автоматически использует системные утилиты, если Docker CLI
или daemon недоступны. Для явного выбора используйте `--backend native`.

```bash
sudo apt install parted e2fsprogs util-linux kpartx curl
sudo ./run.sh --backend native --model NC-1913 /dev/sdX
```

На macOS доступна нативная подготовка без Docker: сначала `bash setup-macos.sh`,
затем `sudo bash run.sh --backend native`. Зависимости проверяются до выбора диска.
`--backend docker` требует Docker и не переключается на другой режим.

Архив скачивается по HTTPS с `bin.entware.net` и проверяется до форматирования.
Неполный архив или ошибка сети останавливают подготовку. На macOS подтверждение
стирания запрашивается до теста ёмкости, который тоже записывает данные.

## Параметры

| Переменная | Описание | По умолчанию |
|---|---|---|
| `MODEL` | KN-xxxx / NC-xxxx | — |
| `BACKEND` | auto / docker / native (Linux/macOS) | `auto` |
| `INSTALLER_LANGUAGE` | ru / en | `ru` |
| `ARCH` | Архитектура роутера: `mipsel`, `mips`, `aarch64` | Выбор модели/платформы |
| `SWAP_SIZE` | Размер swap-раздела в МБ | `1024` |
| `PARTITION_TABLE` | Таблица разделов: `mbr` или `gpt` | `mbr` |
| `SKIP_ENTWARE` | Пропустить установщик Entware (`1` — пропустить) | `0` |

## Примеры

```bash
# Интерактивный выбор флешки
sudo ./run.sh

# Указать устройство напрямую
sudo ./run.sh /dev/disk4          # macOS
sudo ./run.sh /dev/sdb            # Linux

# AArch64 (Peak, Titan, Hopper) с GPT и 512MB swap
sudo ARCH=aarch64 SWAP_SIZE=512 PARTITION_TABLE=gpt ./run.sh

# Только разметка, без Entware
sudo SKIP_ENTWARE=1 ./run.sh
```

## Прямой запуск через Docker (Linux)

```bash
docker run --rm -it --privileged \
  -v /dev/sdb:/dev/target \
  ghcr.io/onepyad/keenetic-entware-flash:main
```

## macOS без Docker: подготовка целиком

Homebrew не входит в стандартную macOS. Если вы уже скачали репозиторий:

```bash
bash setup-macos.sh
sudo bash run.sh --backend native
```

`setup-macos.sh` проверит Homebrew, при необходимости запустит официальный
установщик, затем установит Git, Python и e2fsprogs. Запускайте его без sudo.
Для первого запуска до скачивания репозитория:

```bash
SETUP_FILE="$(mktemp -t keenetic-setup)"
curl -fL https://raw.githubusercontent.com/onepyad/keenetic-entware-flash/main/setup-macos.sh -o "$SETUP_FILE"
bash "$SETUP_FILE"
rm -f "$SETUP_FILE"
git clone https://github.com/onepyad/keenetic-entware-flash.git
cd keenetic-entware-flash
sudo bash run.sh --backend native
```

Скрипт попросит отключить остальные флешки и внешние диски, затем получить
актуальный список устройств. Единственный накопитель выбирается автоматически,
с показом названия и размера. При нуле или нескольких устройствах поиск
повторяется; первый диск из списка не выбирается. Перед записью требуется `yes`.

Создаются два раздела MBR: **1 ГиБ Linux SWAP** (по умолчанию) и **OPKG ext4**
на оставшемся месте. SWAP инициализируется, установщик и S01swap записываются
на ext4 с Mac. Дополнительное копирование по SMB не требуется.

Если установщик уже скачан:

```bash
sudo bash run.sh --backend native --installer-dir ./installers
```

Размер SWAP задаётся в МиБ: `sudo SWAP_SIZE=2048 bash run.sh --backend native`.
Этот нативный режим поддерживает MBR, накопители до 2 ТиБ с секторами 512 байт.
Размер страницы Linux SWAP по умолчанию 4096 байт; для роутера с другим размером
страницы задайте `SWAP_PAGE_SIZE`, например `sudo SWAP_PAGE_SIZE=16384 bash run.sh --backend native`.
Размер страницы Mac не используется. Реальная активация проверяется на роутере.

Для получения пути без root и записи на устройство:

```bash
DISK="$(bash run.sh --detect-usb)"
```

## Как это работает

1. `run.sh` предлагает выбрать модель или платформу и проверяет зависимости
2. После отключения других дисков автоматически выбирает единственную флешку и скачивает установщик
3. На Linux использует системные утилиты или Docker; на macOS использует Homebrew/e2fsprogs либо временный образ для Docker
4. После подтверждения создаёт разметку MBR (для Docker/Linux также доступна GPT):
   - **Раздел 1** — Linux SWAP размером 1 ГиБ по умолчанию
   - **Раздел 2** — EXT4 (метка: OPKG) с установщиком Entware
5. Записывает установщик и SWAP-скрипт; в Docker-режиме macOS записывает готовый образ
6. Готово — вставляйте флешку в роутер

## После записи

### Шаг 1: Установка OPKG

1. Вставьте USB-флешку в Keenetic роутер
2. Откройте веб-интерфейс роутера (обычно http://192.168.1.1)
3. Перейдите в **Управление** → **Общие настройки** → **Обновления и компоненты**
4. Найдите и установите **Менеджер пакетов OPKG**:
   > Позволяет устанавливать пакеты OpenWRT для расширения возможностей интернет-центра.
   > Обсуждение работы интернет-центра с открытыми пакетами ведется на форуме [forum.keenetic.ru](https://forum.keenetic.ru). Техническая поддержка Keenetic такие вопросы не рассматривает.
5. Роутер перезагрузится и начнёт установку Entware автоматически

Процесс установки можно наблюдать в журнале роутера:
**Диагностика** → **Общие** → **Журнал** (`/diagnostics/general/log`)

По завершении вы увидите:
```
[5/5] Установка системы пакетов "Entware" завершена!
Не забудьте сменить пароль и номер порта!
```

### Шаг 2: Смена пароля и настройка SSH

После установки Entware предоставляет собственный SSH-доступ (Dropbear):
- **Логин:** `root`
- **Пароль:** `keenetic`
- **Порт:** `222`

Подключитесь и сразу смените пароль по умолчанию:

```bash
ssh root@192.168.1.1 -p 222

passwd root
# Changing password for root
# New password:
# Retype password:
# passwd: password for root changed by root
```

Обновите список пакетов и установленные пакеты:

```bash
opkg update
opkg upgrade
```

#### Настройка SSH-портов

После установки Entware у вас будет два SSH-сервиса. Рекомендуется перенести встроенный SSH Keenetic на другой порт, чтобы избежать конфликтов:

**Вариант А: Через веб-интерфейс**
1. Откройте веб-интерфейс роутера → **Управление** → **Общие настройки**
2. Найдите раздел **Командная строка** или **Удалённый доступ**
3. Измените порт SSH с `22` на `2222`

**Вариант Б: Через CLI Keenetic**
```bash
ssh admin@192.168.1.1 -p 22

(config)> ip ssh
(config-ssh)> port 2222
(config-ssh)> exit
(config)> system configuration save
```

После настройки у вас будет два раздельных SSH-подключения:

```bash
# CLI Keenetic (управление роутером)
ssh admin@192.168.1.1 -p 2222

# Entware shell (полноценная Linux-среда)
ssh root@192.168.1.1 -p 22
```

> Порт SSH Entware можно изменить в `/opt/etc/config/dropbear.conf` при необходимости.

### Шаг 3: Включение SWAP (рекомендуется)

Swap значительно повышает стабильность при работе нескольких пакетов Entware. SWAP **не активируется автоматически** без init-скрипта — после каждой перезагрузки роутера `free -m` покажет `Swap: 0`.

Скрипт автозапуска уже записан на флешку при прошивке. Он определяет раздел Linux SWAP по метке SWAP и выполняет `swapon`. Раздел уже инициализирован; скрипт не форматирует его и безопасно обрабатывает повторный запуск.

Подключитесь к Entware по SSH и выполните:

Скопируйте скрипт в автозагрузку:

```bash
cp /opt/scripts/S01swap /opt/etc/init.d/S01swap && chmod +x /opt/etc/init.d/S01swap
```

Запустите — скрипт найдёт уже инициализированный раздел и активирует SWAP:

```bash
/opt/etc/init.d/S01swap start
```

Проверьте:

```bash
/opt/etc/init.d/S01swap status
```

```bash
free -m
```

В строке `Swap` должны быть значения (например, `Swap: 1023 MB`).

---



---

После перезагрузки роутера SWAP включится автоматически. Проверка:

```bash
free -m
```

```bash
cat /proc/swaps
```

### Шаг 4: Проверка

```bash
# Проверить работу Entware
opkg update
opkg list-installed

# Проверить, что swap активен
free -m
```

Подробнее: [help.keenetic.com](https://help.keenetic.com/hc/ru/articles/360021888880)

## Локальная сборка

```bash
# Стандартная сборка
docker build --platform linux/amd64 -t keenetic-entware-flash .

# Сборка в России (с доступными зеркалами)
docker build --platform linux/amd64 \
  --build-arg BASE_IMAGE=cr.yandex/mirror/ubuntu:22.04 \
  --build-arg APT_MIRROR=http://mirror.yandex.ru \
  -t keenetic-entware-flash .
```

## Клонирование USB (Backup / Restore)

Флешки в роутерах работают 24/7 и могут выходить из строя. Используйте `clone.sh` для создания полного побайтового слепка флешки и восстановления на новый накопитель.

### Backup (USB → файл)

```bash
# Интерактивный выбор флешки
sudo ./clone.sh backup

# Указать устройство напрямую
sudo ./clone.sh backup /dev/disk4          # macOS
sudo ./clone.sh backup /dev/sdb            # Linux

# Указать путь к файлу
sudo ./clone.sh backup /dev/disk4 ~/backup.img

# Сжатый backup (gzip)
sudo ./clone.sh backup --compress
sudo ./clone.sh backup /dev/disk4 --compress
```

По умолчанию сохраняет в `~/keenetic-backup-YYYY-MM-DD.img`

### Restore (файл → USB)

```bash
# Интерактивный выбор флешки
sudo ./clone.sh restore backup.img

# Указать устройство напрямую
sudo ./clone.sh restore backup.img /dev/disk4

# Восстановить точную исходную разметку без расширения раздела 2
sudo ./clone.sh restore backup.img /dev/disk4 --no-expand
```

- Сжатые образы (`.img.gz`) определяются автоматически
- Прогресс backup и restore выводится одной строкой: сколько сделано, сколько всего, сколько осталось и текущая скорость
- Raw-образы записываются точно, включая нулевые блоки
- Если целевая флешка больше образа, раздел 2 (ext4 / OPKG) расширяется автоматически
- На macOS для автоматического расширения ext4 используется Docker, потому что macOS не умеет менять размер ext4 нативно
- Скрипт проверяет, что образ помещается на целевой диск
- Перед записью требуется подтверждение

## Проверка состояния USB

USB-флешки в роутерах работают 24/7 и со временем выходят из строя. `check.sh`
диагностирует состояние накопителя и проверяет корректность клонированной Entware,
чтобы отличить умирающую флешку от исправной до того, как доверить ей данные.

```bash
# Список всех дисков (без sudo) — найти нужный девайс
./check.sh list

# Быстрая проверка: инфо, пробы чтения (начало/середина/конец), скорость, fsck (RO)
sudo ./check.sh quick /dev/disk4        # macOS
sudo ./check.sh quick /dev/sdb          # Linux

# Полное чтение всего устройства (медленно, ловит битые блоки где угодно)
sudo ./check.sh full /dev/disk4

# Проверка клонированной Entware: разделы, fsck ext4, swap, маркеры Entware
sudo ./check.sh entware /dev/disk4

# Деструктивный тест записи/чтения — СТИРАЕТ ВСЕ ДАННЫЕ, только для подозрительной флешки
sudo ./check.sh write /dev/disk4
```

### Режимы

| Режим | Что делает |
|-------|------------|
| `list` | Перечисляет все диски (внутренние + USB). sudo не нужен. |
| `quick` (по умолчанию) | Инфо об устройстве, пробы чтения в начале/середине/конце, скорость последовательного чтения, проверка ФС в read-only. Сэмплирует ~12 МиБ. |
| `full` | Всё из `quick` плюс полное последовательное чтение всего устройства с live-прогрессом (процент, средняя/мгновенная скорость, ETA). Выявляет битые блоки в любом месте. |
| `entware` | Проверяет восстановленную флешку Keenetic Entware: разметку, магию ext4, целостность `e2fsck`, swap-раздел (по метке тома `SWAP`) и маркеры Entware (`/opt`, `/bin/opkg`, `/etc/opkg.conf`, `/etc/init.d`). |
| `write` | **Деструктивный.** Перезаписывает первые 256 МиБ случайным паттерном и сверяет чтение. Требует ввести `YES`. Только чтобы подтвердить, что флешка умирает. |

### Глубокая проверка (рекомендуется для `entware` и `quick`)

Этапы `entware` и проверки ФС требуют утилит `e2fsprogs` (`e2fsck`, `debugfs`).
На macOS они не входят в систему, а Homebrew ставит их keg-only — `check.sh`
находит их в кеге автоматически, но сначала их надо установить:

```bash
brew install e2fsprogs            # macOS
sudo apt install e2fsprogs        # Debian / Ubuntu / хост-роутер на Linux
```

Без `e2fsprogs` `check.sh` всё равно определит типы разделов по сигнатурам на
диске, но не сможет проверить целостность и показать содержимое ФС.

### Восстановление умирающей флешки

Если `full` или бэкап обрывается с `Input/output error` или
`OSError: [Errno 6] Device not configured` — контроллер флешки умирает, обычный
`dd` останавливается на первом битом секторе. Используйте `ddrescue`: он
пропускает ошибки, повторяет попытки и хранит карту, позволяя продолжить после
передёргивания:

```bash
brew install ddrescue                                            # macOS
sudo ddrescue -d -r0 -b 4096 /dev/rdisk4 rescue.img rescue.map   # быстрый первый проход
sudo ddrescue -d -r3 -R      /dev/rdisk4 rescue.img rescue.map   # повтор по битым зонам
```

Затем починить и восстановить спасённый образ:

```bash
brew install e2fsprogs
sudo ./clone.sh restore rescue.img /dev/diskN
sudo ./check.sh entware /dev/diskN
```

## Решение проблем

**"No external USB devices found"** — вставьте USB-флешку и попробуйте снова.

**"Permission denied"** — запускайте с `sudo`:
```bash
sudo ./run.sh
```

**macOS: "Resource busy"** — скрипт размонтирует диск автоматически, но если не получилось:
```bash
diskutil unmountDisk /dev/diskN
```

**Docker Hub / GHCR недоступен** — скрипт автоматически соберёт образ локально через доступные зеркала.

**Установщик Entware не скачался** — подготовка останавливается до форматирования. Проверьте доступ к `bin.entware.net` и повторите запуск. `SKIP_ENTWARE=1` явно разрешает подготовку без установщика.

## Лицензия

MIT — см. [LICENSE](LICENSE).
