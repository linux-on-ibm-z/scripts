set -x
node scripts/functional_tests --bail --config test/api_integration/config.js
node scripts/functional_tests --bail --config test/functional/apps/dashboard/group5/config.ts
node scripts/functional_tests --bail --config test/functional/apps/dashboard_elements/config.ts
node scripts/functional_tests --bail --config test/functional/apps/visualize/group5/config.ts
node scripts/functional_tests --bail --config test/interactive_setup_api_integration/enrollment_flow.config.ts
node scripts/functional_tests --bail --config test/interactive_setup_api_integration/manual_configuration_flow_without_tls.config.ts
node scripts/functional_tests --bail --config test/interactive_setup_api_integration/manual_configuration_flow.config.ts
node scripts/functional_tests --bail --config test/server_integration/http/platform/config.status.ts
node scripts/functional_tests --bail --config test/server_integration/http/platform/config.ts
node scripts/functional_tests --bail --config test/server_integration/http/ssl/config.js
node scripts/functional_tests --bail --config test/server_integration/http/ssl_redirect/config.js
node scripts/functional_tests --bail --config test/server_integration/http/ssl_with_p12/config.js
node scripts/functional_tests --bail --config test/server_integration/http/ssl_with_p12_intermediate/config.js
