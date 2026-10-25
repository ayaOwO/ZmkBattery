#!/usr/bin/env bash

# Legacy keyboard name is used only to preserve existing battery labels.
# All connected devices are discovered regardless of this name.
keyboard_name="${1:-${ZMK_KEYBOARD_NAME:-Corne-ish Zen}}"

readonly battery_uuid="00002a19-0000-1000-8000-00805f9b34fb"
readonly description_uuid="00002901-0000-1000-8000-00805f9b34fb"

# USB batteries are independent of Bluetooth keyboard connections.
usb_batteries='[]'
if command -v python3 >/dev/null; then
    usb_batteries=$(python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/getUsbBatteries.py") || usb_batteries='[]'
fi

print_usb_batteries() {
    printf '%s\n' "$usb_batteries"
}

fail() {
    printf 'getBattery.sh: %s\n' "$1" >&2
    print_usb_batteries
    [[ $usb_batteries != '[]' ]] && exit 0
    exit 1
}

if ! command -v busctl >/dev/null; then
    fail "busctl is required"
fi

if ! command -v jq >/dev/null; then
    fail "jq is required"
fi

objects=$(
    busctl --system --json=short call \
        org.bluez \
        / \
        org.freedesktop.DBus.ObjectManager \
        GetManagedObjects \
        2>/dev/null
) || fail "could not query BlueZ objects"

devices=$(
    jq -r '.data[0] | to_entries[]
        | select(.value["org.bluez.Device1"].Connected.data? == true)
        | [.key, (.value["org.bluez.Device1"].Address.data // (.key | split("dev_") | last)),
           (.value["org.bluez.Device1"].Alias.data // .value["org.bluez.Device1"].Name.data // "Bluetooth device")]
        | @tsv' <<< "$objects"
) || fail "could not parse BlueZ objects"

read_value() {
    local path=$1

    busctl --system --timeout=3s --json=short call \
        org.bluez \
        "$path" \
        org.bluez.GattCharacteristic1 \
        ReadValue \
        'a{sv}' 0 \
        2>/dev/null |
        jq -er '
            .data[0]
            | select(length == 1)
            | .[0]
            | select(. >= 0 and . <= 100)
        '
}

read_description() {
    local path=$1

    busctl --system --timeout=3s --json=short call \
        org.bluez \
        "$path" \
        org.bluez.GattDescriptor1 \
        ReadValue \
        'a{sv}' 0 \
        2>/dev/null |
        jq -jer '
            .data[0]
            | map(select(. != 0))
            | implode
            | select(length > 0)
        '
}

result='[]'
while IFS=$'\t' read -r device_path device_address device_name; do
    [[ -n $device_path ]] || continue
    peripheral_ordinal=0

    characteristics=$(
        jq -r \
            --arg device "$device_path" \
            --arg battery_uuid "$battery_uuid" \
            --arg description_uuid "$description_uuid" '
            .data[0] as $objects
            | $objects
            | to_entries[]
            | select(.key | startswith($device + "/"))
            | select(
                (.value["org.bluez.GattCharacteristic1"].UUID.data? // "")
                == $battery_uuid
            )
            | .key as $characteristic
            | [
                $objects
                | to_entries[]
                | select(
                    (.value["org.bluez.GattDescriptor1"].Characteristic.data? // "")
                    == $characteristic
                )
                | select(
                    (.value["org.bluez.GattDescriptor1"].UUID.data? // "")
                    == $description_uuid
                )
                | .key
            ]
            | [
                $characteristic,
                (first // "")
            ]
            | @tsv
        ' <<< "$objects"
    ) || fail "could not enumerate battery characteristics"

    # Headsets and other devices may expose Battery1 without a GATT service.
    # Prefer GATT when available so ZMK proxy batteries remain separate.
    if [[ -z $characteristics ]]; then
        battery=$(
            jq -c --arg device "$device_path" \
                --arg id "bluetooth:${device_address,,}:battery" \
                --arg name "$device_name" '
                .data[0][$device]["org.bluez.Battery1"].Percentage.data
                | select(type == "number")
                | select(. >= 0 and . <= 100 and floor == .)
                | {id: $id, name: $name, level: ., _order: -1}
            ' <<< "$objects"
        ) || fail "could not parse Bluetooth battery"
        if [[ -n $battery ]]; then
            result=$(jq -c --argjson battery "$battery" '. + [$battery]' <<< "$result")
        fi
    fi

    while IFS=$'\t' read -r characteristic descriptor; do
        [[ -n $characteristic ]] || continue

        level=$(read_value "$characteristic") || level=null

        if [[ -z $descriptor ]]; then
            id=central
            name=Central
            order=-1
        else
            description=$(read_description "$descriptor") || description=
            name="${description:-Peripheral $peripheral_ordinal}"

            if [[ $description =~ ^[Pp]eripheral[[:space:]]+([0-9]+)$ ]]; then
                peripheral_number=${BASH_REMATCH[1]}
                id="peripheral:$peripheral_number"
                order=$peripheral_number
            else
                id="peripheral:${description:-$peripheral_ordinal}"
                order=$((100000 + peripheral_ordinal))
            fi

            ((peripheral_ordinal += 1))
        fi

        legacy_id=
        [[ $device_name == "$keyboard_name" ]] && legacy_id=$id
        id="bluetooth:${device_address,,}:$id"
        name="$device_name · $name"

        result=$(
            jq -c \
                --arg id "$id" \
                --arg name "$name" \
                --arg legacyId "$legacy_id" \
                --argjson level "$level" \
                --argjson order "$order" \
                '. + [{
                    id: $id,
                    name: $name,
                    legacyId: $legacyId,
                    level: $level,
                    _order: $order
                }]' \
                <<< "$result"
        ) || fail "could not build battery result"
    done <<< "$characteristics"
done <<< "$devices"

jq -c --argjson usb "$usb_batteries" 'sort_by((.name | split(" · ") | first), ._order, .name) | map(del(._order)) | . + $usb' <<< "$result"
