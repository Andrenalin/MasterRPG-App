#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_ROOT="$ROOT_DIR/Snapshots"
MANAGED_DERIVED_DATA_ROOT="${TMPDIR:-/tmp}/MasterRPGSnapshotDerivedData-$$"

ACTIVE_CANONICAL=""
ACTIVE_STAGING=""
ACTIVE_BACKUP=""
ACTIVE_PROMOTION_STARTED=0
ACTIVE_TRANSACTION_COMMITTED=0

usage() {
    echo "Usage: $0 <verify|record> <26|27|both> [additional xcodebuild arguments...]"
    echo
    echo "  verify  Compares references without writing them."
    echo "  record  Records into a clean staging tree, verifies it, then replaces the reference tree."
}

path_exists() {
    [[ -e "$1" || -L "$1" ]]
}

clear_transaction_state() {
    ACTIVE_CANONICAL=""
    ACTIVE_STAGING=""
    ACTIVE_BACKUP=""
    ACTIVE_PROMOTION_STARTED=0
    ACTIVE_TRANSACTION_COMMITTED=0
}

rollback_active_transaction() {
    if [[ -z "$ACTIVE_CANONICAL" ]]; then
        return
    fi

    if [[ $ACTIVE_TRANSACTION_COMMITTED -eq 1 ]]; then
        rm -rf "$ACTIVE_STAGING" "$ACTIVE_BACKUP"
        clear_transaction_state
        return
    fi

    if [[ $ACTIVE_PROMOTION_STARTED -eq 1 ]]; then
        if path_exists "$ACTIVE_BACKUP"; then
            echo "Restoring the previous baseline at $ACTIVE_CANONICAL" >&2
            rm -rf "$ACTIVE_CANONICAL"
            if ! mv "$ACTIVE_BACKUP" "$ACTIVE_CANONICAL"; then
                echo "Unable to restore $ACTIVE_CANONICAL from $ACTIVE_BACKUP." >&2
            fi
        elif ! path_exists "$ACTIVE_STAGING" && path_exists "$ACTIVE_CANONICAL"; then
            # There was no previous canonical tree and staging was already promoted.
            rm -rf "$ACTIVE_CANONICAL"
        fi
    fi

    rm -rf "$ACTIVE_STAGING"
    clear_transaction_state
}

cleanup_on_exit() {
    local status=$?
    trap - EXIT
    rollback_active_transaction
    rm -rf "$MANAGED_DERIVED_DATA_ROOT"
    exit "$status"
}

exit_for_signal() {
    exit "$1"
}

trap cleanup_on_exit EXIT
trap 'exit_for_signal 130' INT
trap 'exit_for_signal 143' TERM
trap 'exit_for_signal 129' HUP

if [[ $# -lt 2 ]]; then
    usage
    exit 64
fi

ACTION="$1"
TOOLCHAIN="$2"
shift 2

case "$ACTION" in
    verify|record)
        ;;
    *)
        usage
        exit 64
        ;;
esac

case "$TOOLCHAIN" in
    26|27)
        TOOLCHAINS=("$TOOLCHAIN")
        ;;
    both)
        TOOLCHAINS=(26 27)
        ;;
    *)
        usage
        exit 64
        ;;
esac

derived_data_for_major() {
    local major="$1"

    case "$major" in
        26)
            if [[ -n "${SNAPSHOT_DERIVED_DATA_26:-}" ]]; then
                echo "$SNAPSHOT_DERIVED_DATA_26"
            else
                echo "$MANAGED_DERIVED_DATA_ROOT/Xcode26"
            fi
            ;;
        27)
            if [[ -n "${SNAPSHOT_DERIVED_DATA_27:-}" ]]; then
                echo "$SNAPSHOT_DERIVED_DATA_27"
            else
                echo "$MANAGED_DERIVED_DATA_ROOT/Xcode27"
            fi
            ;;
    esac
}

cleanup_managed_derived_data() {
    local major="$1"

    case "$major" in
        26)
            if [[ -z "${SNAPSHOT_DERIVED_DATA_26:-}" ]]; then
                rm -rf "$MANAGED_DERIVED_DATA_ROOT/Xcode26"
            fi
            ;;
        27)
            if [[ -z "${SNAPSHOT_DERIVED_DATA_27:-}" ]]; then
                rm -rf "$MANAGED_DERIVED_DATA_ROOT/Xcode27"
            fi
            ;;
    esac
}

run_tests() {
    local major="$1"
    local record_mode="$2"
    local baseline_variant="$3"
    local xcode_app
    local destination
    local derived_data
    shift 3

    case "$major" in
        26)
            xcode_app="${XCODE26_APP:-/Applications/Xcode-26.6.0.app}"
            destination="${SNAPSHOT_DESTINATION_26:-platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5}"
            ;;
        27)
            xcode_app="${XCODE27_APP:-/Applications/Xcode-27.0.0-Beta.4.app}"
            destination="${SNAPSHOT_DESTINATION_27:-platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0}"
            ;;
    esac
    derived_data="$(derived_data_for_major "$major")"

    if [[ ! -d "$xcode_app/Contents/Developer" ]]; then
        echo "Xcode $major was not found at $xcode_app." >&2
        echo "Set XCODE${major}_APP to its application path." >&2
        return 66
    fi

    echo "Xcode $major: snapshot record mode $record_mode"
    if [[ -n "$baseline_variant" ]]; then
        echo "Baseline variant: $baseline_variant"
    else
        echo "Baseline variant: automatic DTXcode selection"
    fi
    echo "Destination: $destination"
    echo "Derived data: $derived_data"

    # The MasterSnapshot plan expands these build settings into the simulator
    # test process. Shell-prefixed variables are intentionally not used because
    # xcodebuild does not forward arbitrary parent-process variables to tests.
    DEVELOPER_DIR="$xcode_app/Contents/Developer" \
        xcodebuild test \
            -project "$ROOT_DIR/MasterRPG.xcodeproj" \
            -scheme MasterRPG \
            -testPlan MasterSnapshot \
            -configuration Debug \
            -destination "$destination" \
            -derivedDataPath "$derived_data" \
            -parallel-testing-enabled NO \
            -disableAutomaticPackageResolution \
            -enableCodeCoverage NO \
            -collect-test-diagnostics never \
            CODE_SIGNING_ALLOWED=NO \
            COMPILER_INDEX_STORE_ENABLE=NO \
            EAGER_LINKING=NO \
            "$@" \
            "SNAPSHOT_RECORD_MODE_BUILD_SETTING=$record_mode" \
            "SNAPSHOT_BASELINE_VARIANT_BUILD_SETTING=$baseline_variant"
}

png_count() {
    local directory="$1"

    if ! path_exists "$directory"; then
        echo 0
        return
    fi
    find "$directory" -type f -name '*.png' -print | wc -l | tr -d '[:space:]'
}

begin_recording_transaction() {
    local major="$1"

    ACTIVE_CANONICAL="$SNAPSHOT_ROOT/Xcode$major"
    ACTIVE_STAGING="$SNAPSHOT_ROOT/Xcode${major}Recording"
    ACTIVE_BACKUP="$SNAPSHOT_ROOT/.Xcode${major}.backup.$$"
    ACTIVE_PROMOTION_STARTED=0
    ACTIVE_TRANSACTION_COMMITTED=0

    mkdir -p "$SNAPSHOT_ROOT"
    rm -rf "$ACTIVE_STAGING" "$ACTIVE_BACKUP"
}

promote_staged_baseline() {
    ACTIVE_PROMOTION_STARTED=1

    if path_exists "$ACTIVE_CANONICAL"; then
        mv "$ACTIVE_CANONICAL" "$ACTIVE_BACKUP"
    fi
    mv "$ACTIVE_STAGING" "$ACTIVE_CANONICAL"
}

commit_recording_transaction() {
    ACTIVE_TRANSACTION_COMMITTED=1
    rm -rf "$ACTIVE_BACKUP" "$ACTIVE_STAGING"
    clear_transaction_state
}

record_and_verify() {
    local major="$1"
    local staging_variant="Xcode${major}Recording"
    local record_status
    local staged_png_count
    local verify_status
    shift

    begin_recording_transaction "$major"

    echo "Recording a clean staging tree at Snapshots/$staging_variant"
    set +e
    run_tests "$major" all "$staging_variant" "$@"
    record_status=$?
    set -e
    echo "Recording pass exited with status $record_status; SnapshotTesting reports recorded cases as failures."
    if [[ $record_status -eq 0 ]]; then
        echo "Recording unexpectedly passed. No recording assertions were executed; check the test-plan environment." >&2
        return 70
    fi

    staged_png_count="$(png_count "$ACTIVE_STAGING")"
    if [[ $staged_png_count -le 0 ]]; then
        echo "Recording produced no PNG references in $ACTIVE_STAGING." >&2
        return 71
    fi
    echo "Recorded $staged_png_count staged PNG references."

    echo "Verifying the complete staging tree without writes"
    set +e
    run_tests "$major" never "$staging_variant" "$@"
    verify_status=$?
    set -e
    if [[ $verify_status -ne 0 ]]; then
        echo "Staged verification failed; the existing Xcode$major baseline remains unchanged." >&2
        return "$verify_status"
    fi

    echo "Replacing Snapshots/Xcode$major with the verified staging tree"
    promote_staged_baseline

    echo "Verifying automatic DTXcode selection for Snapshots/Xcode$major"
    set +e
    run_tests "$major" never "" "$@"
    verify_status=$?
    set -e
    if [[ $verify_status -ne 0 ]]; then
        echo "Automatic DTXcode verification failed; restoring the previous Xcode$major baseline." >&2
        return "$verify_status"
    fi

    commit_recording_transaction
    echo "Committed $staged_png_count references to Snapshots/Xcode$major."
}

for major in "${TOOLCHAINS[@]}"; do
    if [[ "$ACTION" == "record" ]]; then
        record_and_verify "$major" "$@"
    else
        echo "Verifying Snapshots/Xcode$major without writes"
        run_tests "$major" never "" "$@"
    fi

    # Default DerivedData is script-owned and temporary. Explicit override
    # paths remain untouched so callers can opt into a persistent build cache.
    cleanup_managed_derived_data "$major"
done
