#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_dir=$(cd -- "$test_dir/.." && pwd)
mock_path="$test_dir/mock-bin:$PATH"

assert_json() {
    local scenario=$1
    local expression=$2
    local output

    output=$(PATH="$mock_path" MOCK_SCENARIO="$scenario" \
        "$plugin_dir/getBattery.sh" "Test Board")
    jq -e "$expression" >/dev/null <<< "$output"
}

assert_json central_only '
    length == 1
    and .[0].id == "bluetooth:test:central" and .[0].level == 79 and .[0].legacyId == "central"
'

assert_json multi '
    map(.id) == ["bluetooth:test:central","bluetooth:test:peripheral:0","bluetooth:test:peripheral:1","bluetooth:test:peripheral:2"]
    and map(.name) == ["Test Board · Central","Test Board · Peripheral 0","Test Board · Peripheral 1","Test Board · Peripheral 2"]
    and map(.level) == [79,77,88,null]
'

assert_json multi_devices 'length == 8 and (map(.id) | unique | length) == 8
    and any(.[]; .id == "bluetooth:other:central" and .legacyId == "")'
assert_json battery1 'length == 1 and .[0].id == "bluetooth:buds:battery" and .[0].name == "Galaxy Buds" and .[0].level == 100'
assert_json battery1_invalid 'length == 0'
assert_json missing 'length == 0'
assert_json disconnected 'length == 0'

export MOCK_USB_BATTERIES='[{"id":"usb:test:mouse:port","name":"Mouse","level":96}]'
assert_json multi 'length == 5 and .[-1].level == 96 and .[0].id == "bluetooth:test:central"'
assert_json disconnected 'length == 1 and .[0].name == "Mouse" and .[0].level == 96'
assert_json bluez_error 'length == 1 and .[0].level == 96'
unset MOCK_USB_BATTERIES

set +e
bluez_error_output=$(PATH="$mock_path" MOCK_SCENARIO=bluez_error \
    "$plugin_dir/getBattery.sh" "Test Board" 2>/dev/null)
bluez_error_status=$?
set -e

[[ $bluez_error_status -ne 0 ]]
jq -e 'length == 0' >/dev/null <<< "$bluez_error_output"

printf 'getBattery tests passed\n'
