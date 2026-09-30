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
    and .[0] == {"id":"central","name":"Central","level":79}
'

assert_json multi '
    map(.id) == ["central","peripheral:0","peripheral:1","peripheral:2"]
    and map(.name) == ["Central","Peripheral 0","Peripheral 1","Peripheral 2"]
    and map(.level) == [79,77,88,null]
'

assert_json missing 'length == 0'
assert_json disconnected 'length == 0'

set +e
bluez_error_output=$(PATH="$mock_path" MOCK_SCENARIO=bluez_error \
    "$plugin_dir/getBattery.sh" "Test Board" 2>/dev/null)
bluez_error_status=$?
set -e

[[ $bluez_error_status -ne 0 ]]
jq -e 'length == 0' >/dev/null <<< "$bluez_error_output"

printf 'getBattery tests passed\n'
