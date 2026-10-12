# macOS: подготовка флешки без Docker

## 1. Подготовить зависимости

Если репозиторий уже есть, откройте его папку и обновите код:

```bash
git pull --ff-only
bash setup-macos.sh
```

Homebrew не входит в macOS. Скрипт проверит его, при необходимости запустит
официальный установщик, затем установит Git, Python и e2fsprogs.
Запускайте setup без sudo. Если репозитория ещё нет, начните с bootstrap:

```bash
SETUP_FILE="$(mktemp -t keenetic-setup)"
curl -fL https://raw.githubusercontent.com/onepyad/keenetic-entware-flash/main/setup-macos.sh -o "$SETUP_FILE"
bash "$SETUP_FILE"
rm -f "$SETUP_FILE"
git clone https://github.com/onepyad/keenetic-entware-flash.git
cd keenetic-entware-flash
```

## 2. Проверки без записи на устройства

```bash
bash run.sh --list-platforms
bash tests/test_clone.sh
bash tests/test_platforms.sh
bash tests/test_run.sh
bash tests/test_usb.sh
bash tests/test_setup_macos.sh
bash tests/test_macos_prepare.sh
bash tests/test_swap.sh
python3 tests/test_macos_disk.py
```

Тесты используют временные файлы и подмены команд. Они не форматируют диски,
не устанавливают Homebrew и не активируют настоящий swap.

## 3. Найти флешку без форматирования

```bash
bash run.sh --detect-usb
```

Сначала отключите все остальные флешки и внешние диски, оставьте только целевую,
нажмите Enter. Единственная флешка выбирается автоматически с показом названия,
размера и пути. При нуле/нескольких накопителях поиск повторяется. 0 отменяет его.
Для сохранения найденного пути: `DISK="$(bash run.sh --detect-usb)"`.

## 4. Подготовить флешку — стирает данные

```bash
sudo bash run.sh --backend native
```

Выберите точный KN/NC-код роутера или платформу. После выбора единственной
флешки скрипт скачает и проверит установщик, затем запросит подтверждение `yes`.
Создаются два раздела: **1 ГиБ Linux SWAP** и **OPKG ext4 на оставшемся месте**.
Установщик и S01swap записываются на ext4 прямо на Mac; отдельный SMB-шаг не нужен.

Если архив уже скачан предыдущей командой в папку installers:

```bash
sudo bash run.sh --backend native --installer-dir ./installers
```

Используйте одну команду подготовки, не обе. Выбранные архитектура и язык должны
соответствовать архиву. SWAP_SIZE по умолчанию 1024 МиБ; SWAP_PAGE_SIZE по умолчанию
4096 байт для Linux роутера, независимо от процессора Mac. Для другой страницы
роутера задайте SWAP_PAGE_SIZE явно. Размер полезного swap немного меньше 1 ГиБ
из-за страницы заголовка. Нативный режим поддерживает MBR/сектора 512 байт/до 2 ТиБ.

## 5. На роутере

Вставьте флешку, установите компонент поддержки открытых пакетов и выберите
раздел OPKG в настройках менеджера пакетов. После установки Entware войдите по
SSH (обычно порт 222 при встроенном SSH-сервере, иначе 22), смените пароль root.
В оболочке Entware выполните:

```sh
cp /opt/scripts/S01swap /opt/etc/init.d/S01swap
chmod +x /opt/etc/init.d/S01swap
/opt/etc/init.d/S01swap start
cat /proc/swaps
free -m
```

Скрипт активирует уже подготовленный SWAP, не форматирует устройства и не
перезаписывает активный раздел при повторном start. При отсутствии ровно одного
SWAP с нужной меткой он сообщает ошибку.

## При ошибке

Пришлите модель роутера, вывод sw_vers, команду и сообщение об ошибке целиком.
Для выбора накопителя нужен также вывод diskutil list external physical.
Реальная USB-запись и активация swap проверяются вами на устройстве; автоматические
тесты проверяют логику, формат заголовка и отказы на временных файлах/подменах команд.
