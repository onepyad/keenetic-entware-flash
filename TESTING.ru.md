# Проверка на macOS

Скрипт выполняется на Mac; флешка затем подключается к Keenetic или Netcraze.
Начните с проверок без записи. Команды записи вынесены отдельно.

## 1. Зависимости и код

Если Homebrew ещё нет, установите его по инструкции https://brew.sh/.
Для автоматической подготовки флешки нужны Docker Desktop и Python 3:

```bash
brew install --cask docker
brew install python
open -a Docker
```

Дождитесь запуска Docker Desktop, затем проверьте:

```bash
docker info
python3 --version
```

Получите код и откройте каталог проекта:

```bash
git clone https://github.com/onepyad/keenetic-entware-flash.git
cd keenetic-entware-flash
```

Если каталог уже есть, вместо повторного clone выполните `git pull --ff-only`
в нём, сохранив свои изменения при необходимости.

## 2. Проверки без записи на USB

```bash
bash run.sh --help
bash run.sh --list-platforms
bash tests/test_clone.sh
bash tests/test_platforms.sh
bash tests/test_run.sh
diskutil list external physical
```

Тесты не требуют sudo и используют временные файлы и подмены команд;
тестовые `/dev/fake` и `/dev/disk4` не открываются.

## 3. Скачивание официального установщика без Docker

Вставьте точный KN/NC-код своего роутера вместо NC-xxxx:

```bash
MODEL_CODE='NC-xxxx'
bash run.sh --model "$MODEL_CODE" --download-installer ./test-installers
```

Эта команда не требует Docker или sudo. Проверьте полученный архив:

```bash
find ./test-installers -name '*installer.tar.gz' -exec tar -tzf {} \;
```

Архивы лежат на https://bin.entware.net/. Для англоязычного установщика добавьте
`--installer-language en` и выберите другой каталог, например `./test-installers-en`.
При повторном скачивании существующий файл не перезаписывается.

## 4. Подготовка флешки — стирает её данные

Отсоедините лишние внешние диски. Найдите нужную флешку и перепроверьте её модель
и размер. `/dev/diskN` ниже — шаблон, замените N на номер своей флешки:

```bash
diskutil list external physical
diskutil info /dev/diskN
sudo bash run.sh --backend docker --model "$MODEL_CODE" /dev/diskN
```

Скрипт запросит `yes`. После подтверждения он проверяет ёмкость записью тестовых
секторов, форматирует образ и записывает его на флешку. Используйте флешку без
нужных данных. Для первого полного теста можно включить запись всех блоков:

```bash
sudo FULL_WRITE=1 bash run.sh --backend docker --model "$MODEL_CODE" /dev/diskN
```

Полная запись медленнее; достаточно выбрать одну из двух команд подготовки.
После успешной записи вставьте флешку в роутер, установите компонент поддержки
открытых пакетов и выберите накопитель в настройках OPKG. Начальный SSH-порт
Entware зависит от установленного компонента SSH: обычно 222 при встроенном
SSH-сервере, иначе 22. Смените пароль `root`.

## Что прислать при ошибке

Пришлите точный KN/NC-код, вывод `sw_vers`, `docker info`, команду запуска и
сообщение об ошибке целиком. Для ошибок выбора диска также нужен вывод
`diskutil list external physical`. Уберите пароли, токены и личные данные.
