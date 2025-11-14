declare -a configs=(
    "packages/kbn-check-prod-native-modules-cli/jest.integration.config.js"
    "packages/kbn-cli-dev-mode/jest.integration.config.js"
    "packages/kbn-docs-utils/jest.integration.config.js"
    "packages/kbn-plugin-generator/jest.integration.config.js"
    "packages/kbn-plugin-helpers/jest.integration.config.js"
    "src/cli/jest.integration.config.js"
    "src/core/packages/application/browser-internal/jest.integration.config.js"
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
    "src/core/server/integration_tests/pricing/jest.integration.config.js"
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
    "src/platform/packages/private/kbn-import-resolver/jest.integration.config.js"
    "src/platform/packages/shared/kbn-es/jest.integration.config.js"
    "src/platform/packages/shared/kbn-esql-validation-autocomplete/jest.integration.config.js"
    "src/platform/packages/shared/kbn-storage-adapter/jest.integration.config.js"
    "src/platform/packages/shared/kbn-test/jest.integration.config.js"
    "src/platform/plugins/private/kibana_usage_collection/jest.integration.config.js"
    "src/platform/plugins/shared/content_management/jest.integration.config.js"
    "src/platform/plugins/shared/esql/jest.integration.config.js"
    "src/platform/plugins/shared/files/jest.integration.config.js"
    "src/platform/plugins/shared/share/server/jest.integration.config.js"
    "src/platform/plugins/shared/usage_collection/jest.integration.config.js"
    "x-pack/platform/plugins/private/index_lifecycle_management/jest.integration.config.js"
    "x-pack/platform/plugins/private/reporting/jest.integration.config.js"
    "x-pack/platform/plugins/shared/actions/jest.integration.config.js"
    "x-pack/platform/plugins/shared/alerting/jest.integration.config.js"
    "x-pack/platform/plugins/shared/event_log/jest.integration.config.js"
    "x-pack/platform/plugins/shared/fleet/jest.integration.config.js"
    "x-pack/platform/plugins/shared/global_search/jest.integration.config.js"
    "x-pack/platform/plugins/shared/screenshotting/jest.integration.config.js"
    "x-pack/platform/plugins/shared/task_manager/jest.integration.config.js"
    "x-pack/solutions/observability/plugins/slo/jest.integration.config.js"
    "x-pack/solutions/security/plugins/security_solution/jest.integration.config.js"
    "x-pack/solutions/security/plugins/security_solution/public/detection_engine/rule_management_ui/pages/rule_management/__integration_tests__/rules_upgrade/jest.integration.config.js"
    "x-pack/solutions/security/plugins/security_solution/public/detection_engine/rule_management_ui/pages/rule_management/__integration_tests__/rules_upgrade/upgrade_rule_after_preview/common_fields/jest.integration.config.js"
    "x-pack/solutions/security/plugins/security_solution/public/detection_engine/rule_management_ui/pages/rule_management/__integration_tests__/rules_upgrade/upgrade_rule_after_preview/type_specific_fields/jest.integration.config.js"
)

declare -a failedConfigs=()

set +e;
for config in "${configs[@]}"
do
    echo "=== ${config}"
    FORCE_COLOR=1 NODE_OPTIONS="--max-old-space-size=12288 --trace-warnings" node scripts/jest --config "${config}" --coverage=false --passWithNoTests --runInBand --forceExit
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
