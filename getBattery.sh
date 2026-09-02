#!/usr/bin/env bash

# Override with ZMK_KEYBOARD_NAME or pass the keyboard name as the first argument.
keyboard_name="${1:-${ZMK_KEYBOARD_NAME:-Corne-ish Zen}}"

readonly battery_uuid="00002a19-0000-1000-8000-00805f9b34fb"
readonly description_uuid="00002901-0000-1000-8000-00805f9b34fb"

print_empty() {
    printf '[]\n'
}

fail() {
    printf 'getBattery.sh: %s\n' "$1" >&2
    print_empty
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

device_path=$(
    jq -r --arg name "$keyboard_name" '
        .data[0]
        | [
            to_entries[]
            | select(
                .value["org.bluez.Device1"]? as $device
                | (($device.Alias.data? // "") == $name
                    or ($device.Name.data? // "") == $name)
            )
            | {
                path: .key,
                connected: (.value["org.bluez.Device1"].Connected.data? // false)
            }
            | select(.connected)
        ]
        | last
        | .path // empty
    ' <<< "$objects"
) || fail "could not parse BlueZ objects"

if [[ -z $device_path ]]; then
    print_empty
    exit
fi

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

    result=$(
        jq -c \
            --arg id "$id" \
            --arg name "$name" \
            --argjson level "$level" \
            --argjson order "$order" \
            '. + [{
                id: $id,
                name: $name,
                level: $level,
                _order: $order
            }]' \
            <<< "$result"
    ) || fail "could not build battery result"
done <<< "$characteristics"

jq -c 'sort_by(._order, .name) | map(del(._order))' <<< "$result"
