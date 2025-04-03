declare -a configs=(
    "packages/core/application/core-application-browser-internal/jest.integration.config.js"
    "packages/kbn-check-prod-native-modules-cli/jest.integration.config.js"
    "packages/kbn-cli-dev-mode/jest.integration.config.js"
    "packages/kbn-docs-utils/jest.integration.config.js"
    "packages/kbn-es/jest.integration.config.js"
    "packages/kbn-esql-validation-autocomplete/jest.integration.config.js"
    "packages/kbn-import-resolver/jest.integration.config.js"
    "packages/kbn-plugin-generator/jest.integration.config.js"
    "packages/kbn-plugin-helpers/jest.integration.config.js"
    "packages/kbn-test/jest.integration.config.js"
    "src/cli/jest.integration.config.js"
    "src/core/public/jest.integration.config.js"
    "src/core/server/integration_tests/capabilities/jest.integration.config.js"
    "src/core/server/integration_tests/ci_checks/jest.integration.config.js"
    "src/core/server/integration_tests/config/jest.integration.config.js"
    "src/core/server/integration_tests/core_app/jest.integration.config.js"
    "src/core/server/integration_tests/elasticsearch/jest.integration.config.js"
    "src/core/server/integration_tests/execution_context/jest.integration.config.js"
    "src/core/server/integration_tests/http/jest.integration.config.js"
    "src/core/server/integration_tests/http_resources/jest.integration.config.js"
    "src/core/server/integration_tests/logging/jest.integration.config.js"
    "src/core/server/integration_tests/metrics/jest.integration.config.js"
    "src/core/server/integration_tests/node/jest.integration.config.js"
    "src/core/server/integration_tests/root/jest.integration.config.js"
    "src/core/server/integration_tests/saved_objects/jest.integration.config.js"
    "src/core/server/integration_tests/saved_objects/migrations/group1/jest.integration.config.js"
    "src/core/server/integration_tests/saved_objects/migrations/group2/jest.integration.config.js"
    "src/core/server/integration_tests/saved_objects/migrations/group3/jest.integration.config.js"
    "src/core/server/integration_tests/saved_objects/migrations/group4/jest.integration.config.js"
    "src/core/server/integration_tests/saved_objects/migrations/group5/jest.integration.config.js"
    "src/core/server/integration_tests/saved_objects/migrations/group6/jest.integration.config.js"
    "src/core/server/integration_tests/saved_objects/migrations/zdt_1/jest.integration.config.js"
    "src/core/server/integration_tests/saved_objects/migrations/zdt_2/jest.integration.config.js"
    "src/core/server/integration_tests/saved_objects/migrations/zdt_v2_compat/jest.integration.config.js"
    "src/core/server/integration_tests/status/jest.integration.config.js"
    "src/core/server/integration_tests/ui_settings/jest.integration.config.js"
    "src/dev/jest.integration.config.js"
    "src/plugins/content_management/jest.integration.config.js"
    "src/plugins/files/jest.integration.config.js"
    "src/plugins/kibana_usage_collection/jest.integration.config.js"
    "src/plugins/usage_collection/jest.integration.config.js"
    "x-pack/plugins/actions/jest.integration.config.js"
    "x-pack/plugins/alerting/jest.integration.config.js"
    "x-pack/plugins/event_log/jest.integration.config.js"
    "x-pack/plugins/fleet/jest.integration.config.js"
    "x-pack/plugins/global_search/jest.integration.config.js"
    "x-pack/plugins/index_lifecycle_management/jest.integration.config.js"
    "x-pack/plugins/reporting/jest.integration.config.js"
    "x-pack/plugins/screenshotting/jest.integration.config.js"
    "x-pack/plugins/security_solution/jest.integration.config.js"
    "x-pack/plugins/task_manager/jest.integration.config.js"
)

# === Disabled configs (from .buildkite/disabled_jest_configs.json)
# src/core/server/integration_tests/saved_objects/serverless/migrations/jest.integration.config.js

declare -a failedConfigs=()

set +e;
for config in "${configs[@]}"
do
    echo "=== ${config}"
    NODE_OPTIONS="--max-old-space-size=12288 --trace-warnings" node scripts/jest --config "${config}" --coverage=false --passWithNoTests --runInBand --forceExit
    exitCode=$?
    if [[ $exitCode != 0 ]]; then
        failedConfigs+=("${config}")
        echo "--- FAILED ${config}"
    fi
done
set -e

echo "--------------------------------------"
echo "=== Integration Tests Failed Configs"
for failed in "${failedConfigs[@]}"
do
    echo "  ${failed}"
done
