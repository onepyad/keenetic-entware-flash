#!/usr/bin/env bash
# Read-only USB detection. Does not mount, unmount or write to a device.

wait_for_usb() {
    if [ ! -t 0 ]; then
        echo "ERROR: USB auto-selection requires a terminal. Specify the device explicitly for scripted flashing." >&2
        return 1
    fi
    local answer
    read -r -p "Когда готово, нажмите Enter (или введите 0 для отмены): " answer >&2 || return 1
    [ "$answer" != 0 ] || return 2
}

list_usb_devices() {
    local output
    case "$1" in
        Darwin)
            output=$(diskutil list external physical) || return 1
            printf '%s\n' "$output" | awk '/^\/dev\/disk[0-9]+ / {print $1}'
            ;;
        Linux)
            output=$(lsblk -dnpo NAME,TYPE,RM,TRAN) || return 1
            printf '%s\n' "$output" | awk '$2=="disk" && ($3=="1" || $4=="usb") {print $1}'
            ;;
        *) echo "ERROR: USB detection supports Linux and macOS." >&2; return 1 ;;
    esac
}

describe_usb_device() {
    if [ "$1" = Darwin ]; then
        diskutil info "$2" | awk '/Media Name:|Disk Size:/ {sub(/^ +/, ""); print "  " $0}' >&2
    else
        lsblk -dnpo NAME,SIZE,MODEL "$2" >&2
    fi
}

auto_select_usb() {
    local os="$1" devices count candidate device rc
    echo "Отключите все остальные флешки и внешние диски." >&2
    echo "Оставьте подключённой только флешку, которую хотите подготовить." >&2
    while true; do
        rc=0
        wait_for_usb || rc=$?
        [ "$rc" = 0 ] || return "$rc"
        devices=$(list_usb_devices "$os") || {
            echo "ERROR: Не удалось получить список накопителей." >&2; return 1;
        }
        count=0
        candidate=""
        while IFS= read -r device; do
            [ -n "$device" ] || continue
            count=$((count + 1))
            candidate="$device"
        done <<< "$devices"
        if [ "$count" = 1 ]; then
            describe_usb_device "$os" "$candidate" || return 1
            DISK="$candidate"
            echo "Автоматически выбрана флешка: $DISK" >&2
            return 0
        fi
        if [ "$count" = 0 ]; then
            echo "Флешка не найдена. Подключите её и повторите поиск." >&2
        else
            echo "Найдено накопителей: $count. Отключите лишние и повторите поиск." >&2
            printf '%s\n' "$devices" >&2
        fi
    done
}
