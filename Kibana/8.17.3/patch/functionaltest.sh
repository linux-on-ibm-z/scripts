# Enabled Stateful tests (from .buildkite/ftr_configs_manifests.json)
declare -a stateful=(
    "test/accessibility/config.ts"
    "test/analytics/config.ts"
    "test/api_integration/config.js"
    "test/examples/config.js"
    "test/functional/apps/bundles/config.ts"
    "test/functional/apps/console/config.ts"
    "test/functional/apps/context/config.ts"
    "test/functional/apps/dashboard_elements/controls/common/config.ts"
    "test/functional/apps/dashboard_elements/controls/options_list/config.ts"
    "test/functional/apps/dashboard_elements/image_embeddable/config.ts"
    "test/functional/apps/dashboard_elements/input_control_vis/config.ts"
    "test/functional/apps/dashboard_elements/links/config.ts"
    "test/functional/apps/dashboard_elements/markdown/config.ts"
    "test/functional/apps/dashboard/group1/config.ts"
    "test/functional/apps/dashboard/group2/config.ts"
    "test/functional/apps/dashboard/group3/config.ts"
    "test/functional/apps/dashboard/group4/config.ts"
    "test/functional/apps/dashboard/group5/config.ts"
    "test/functional/apps/dashboard/group6/config.ts"
    "test/functional/apps/discover/ccs_compatibility/config.ts"
    "test/functional/apps/discover/classic/config.ts"
    "test/functional/apps/discover/embeddable/config.ts"
    "test/functional/apps/discover/esql/config.ts"
    "test/functional/apps/discover/group1/config.ts"
    "test/functional/apps/discover/group2_data_grid1/config.ts"
    "test/functional/apps/discover/group2_data_grid2/config.ts"
    "test/functional/apps/discover/group2_data_grid3/config.ts"
    "test/functional/apps/discover/group3/config.ts"
    "test/functional/apps/discover/group4/config.ts"
    "test/functional/apps/discover/group5/config.ts"
    "test/functional/apps/discover/group6/config.ts"
    "test/functional/apps/discover/group7/config.ts"
    "test/functional/apps/discover/group8/config.ts"
    "test/functional/apps/discover/context_awareness/config.ts"
    "test/functional/apps/getting_started/config.ts"
    "test/functional/apps/home/config.ts"
    "test/functional/apps/kibana_overview/config.ts"
    "test/functional/apps/management/config.ts"
    "test/functional/apps/saved_objects_management/config.ts"
    "test/functional/apps/sharing/config.ts"
    "test/functional/apps/status_page/config.ts"
    "test/functional/apps/visualize/group1/config.ts"
    "test/functional/apps/visualize/group2/config.ts"
    "test/functional/apps/visualize/group3/config.ts"
    "test/functional/apps/visualize/group4/config.ts"
    "test/functional/apps/visualize/group5/config.ts"
    "test/functional/apps/visualize/group6/config.ts"
    "test/functional/apps/visualize/replaced_vislib_chart_types/config.ts"
    "test/functional/config.ccs.ts"
    "test/functional/firefox/console.config.ts"
    "test/functional/firefox/dashboard.config.ts"
    "test/functional/firefox/discover.config.ts"
    "test/functional/firefox/home.config.ts"
    "test/functional/firefox/visualize.config.ts"
    "test/health_gateway/config.ts"
    "test/interactive_setup_api_integration/enrollment_flow.config.ts"
    "test/interactive_setup_api_integration/manual_configuration_flow_without_tls.config.ts"
    "test/interactive_setup_api_integration/manual_configuration_flow.config.ts"
    "test/interactive_setup_functional/enrollment_token.config.ts"
    "test/interactive_setup_functional/manual_configuration_without_security.config.ts"
    "test/interactive_setup_functional/manual_configuration_without_tls.config.ts"
    "test/interactive_setup_functional/manual_configuration.config.ts"
    "test/interpreter_functional/config.ts"
    "test/node_roles_functional/all.config.ts"
    "test/node_roles_functional/background_tasks.config.ts"
    "test/node_roles_functional/ui.config.ts"
    "test/plugin_functional/config.ts"
    "test/server_integration/http/platform/config.status.ts"
    "test/server_integration/http/platform/config.ts"
    "test/server_integration/http/ssl_redirect/config.ts"
    "test/server_integration/http/ssl_with_p12_intermediate/config.js"
    "test/server_integration/http/ssl_with_p12/config.js"
    "test/server_integration/http/ssl/config.js"
    "test/ui_capabilities/newsfeed_err/config.ts"
    "x-pack/test/accessibility/apps/group1/config.ts"
    "x-pack/test/accessibility/apps/group2/config.ts"
    "x-pack/test/accessibility/apps/group3/config.ts"
    "x-pack/test/localization/config.ja_jp.ts"
    "x-pack/test/localization/config.fr_fr.ts"
    "x-pack/test/localization/config.zh_cn.ts"
    "x-pack/test/alerting_api_integration/basic/config.ts"
    "x-pack/test/alerting_api_integration/security_and_spaces/group1/config.ts"
    "x-pack/test/alerting_api_integration/security_and_spaces/group2/config.ts"
    "x-pack/test/alerting_api_integration/security_and_spaces/group3/config.ts"
    "x-pack/test/alerting_api_integration/security_and_spaces/group4/config.ts"
    "x-pack/test/alerting_api_integration/security_and_spaces/group3/config_with_schedule_circuit_breaker.ts"
    "x-pack/test/alerting_api_integration/security_and_spaces/group2/config_non_dedicated_task_runner.ts"
    "x-pack/test/alerting_api_integration/security_and_spaces/group4/config_non_dedicated_task_runner.ts"
    "x-pack/test/alerting_api_integration/spaces_only/tests/alerting/group1/config.ts"
    "x-pack/test/alerting_api_integration/spaces_only/tests/alerting/group2/config.ts"
    "x-pack/test/alerting_api_integration/spaces_only/tests/alerting/group3/config.ts"
    "x-pack/test/alerting_api_integration/spaces_only/tests/alerting/group4/config.ts"
    "x-pack/test/alerting_api_integration/spaces_only/tests/actions/config.ts"
    "x-pack/test/alerting_api_integration/spaces_only/tests/action_task_params/config.ts"
    "x-pack/test/api_integration_basic/config.ts"
    "x-pack/test/api_integration/config_security_basic.ts"
    "x-pack/test/api_integration/config_security_trial.ts"
    "x-pack/test/api_integration/apis/aiops/config.ts"
    "x-pack/test/api_integration/apis/cases/config.ts"
    "x-pack/test/api_integration/apis/content_management/config.ts"
    "x-pack/test/api_integration/apis/console/config.ts"
    "x-pack/test/api_integration/apis/es/config.ts"
    "x-pack/test/api_integration/apis/features/config.ts"
    "x-pack/test/api_integration/apis/file_upload/config.ts"
    "x-pack/test/api_integration/apis/grok_debugger/config.ts"
    "x-pack/test/api_integration/apis/kibana/config.ts"
    "x-pack/test/api_integration/apis/lists/config.ts"
    "x-pack/test/api_integration/apis/logs_ui/config.ts"
    "x-pack/test/api_integration/apis/logstash/config.ts"
    "x-pack/test/api_integration/apis/management/config.ts"
    "x-pack/test/api_integration/apis/management/index_management/disabled_data_enrichers/config.ts"
    "x-pack/test/api_integration/apis/maps/config.ts"
    "x-pack/test/api_integration/apis/metrics_ui/config.ts"
    "x-pack/test/api_integration/apis/ml/config.ts"
    "x-pack/test/api_integration/apis/monitoring/config.ts"
    "x-pack/test/api_integration/apis/monitoring_collection/config.ts"
    "x-pack/test/api_integration/apis/osquery/config.ts"
    "x-pack/test/api_integration/apis/search/config.ts"
    "x-pack/test/api_integration/apis/searchprofiler/config.ts"
    "x-pack/test/api_integration/apis/security/config.ts"
    "x-pack/test/api_integration/apis/spaces/config.ts"
    "x-pack/test/api_integration/apis/stats/config.ts"
    "x-pack/test/api_integration/apis/status/config.ts"
    "x-pack/test/api_integration/apis/synthetics/config.ts"
    "x-pack/test/api_integration/apis/telemetry/config.ts"
    "x-pack/test/api_integration/apis/transform/config.ts"
    "x-pack/test/api_integration/apis/upgrade_assistant/config.ts"
    "x-pack/test/api_integration/apis/watcher/config.ts"
    "x-pack/test/banners_functional/config.ts"
    "x-pack/test/cases_api_integration/security_and_spaces/config_basic.ts"
    "x-pack/test/cases_api_integration/security_and_spaces/config_trial.ts"
    "x-pack/test/cases_api_integration/security_and_spaces/config_no_public_base_url.ts"
    "x-pack/test/cases_api_integration/spaces_only/config.ts"
    "x-pack/test/disable_ems/config.ts"
    "x-pack/test/encrypted_saved_objects_api_integration/config.ts"
    "x-pack/test/examples/config.ts"
    "x-pack/test/fleet_api_integration/config.agent.ts"
    "x-pack/test/fleet_api_integration/config.agent_policy.ts"
    "x-pack/test/fleet_api_integration/config.epm.ts"
    "x-pack/test/fleet_api_integration/config.fleet.ts"
    "x-pack/test/fleet_api_integration/config.package_policy.ts"
    "x-pack/test/fleet_api_integration/config.space_awareness.ts"
    "x-pack/test/fleet_functional/config.ts"
    "x-pack/test/ftr_apis/security_and_spaces/config.ts"
    "x-pack/test/functional_basic/apps/ml/permissions/config.ts"
    "x-pack/test/functional_basic/apps/ml/data_visualizer/group1/config.ts"
    "x-pack/test/functional_basic/apps/ml/data_visualizer/group2/config.ts"
    "x-pack/test/functional_basic/apps/ml/data_visualizer/group3/config.ts"
    "x-pack/test/functional_basic/apps/transform/creation/index_pattern/config.ts"
    "x-pack/test/functional_basic/apps/transform/actions/config.ts"
    "x-pack/test/functional_basic/apps/transform/edit_clone/config.ts"
    "x-pack/test/functional_basic/apps/transform/creation/runtime_mappings_saved_search/config.ts"
    "x-pack/test/functional_basic/apps/transform/permissions/config.ts"
    "x-pack/test/functional_basic/apps/transform/feature_controls/config.ts"
    "x-pack/test/functional_cors/config.ts"
    "x-pack/test/functional_embedded/config.ts"
    "x-pack/test/functional_execution_context/config.ts"
    "x-pack/test/functional_with_es_ssl/apps/cases/group1/config.ts"
    "x-pack/test/functional_with_es_ssl/apps/cases/group2/config.ts"
    "x-pack/test/functional_with_es_ssl/apps/discover_ml_uptime/config.ts"
    "x-pack/test/functional_with_es_ssl/apps/triggers_actions_ui/config.ts"
    "x-pack/test/functional_with_es_ssl/apps/triggers_actions_ui/shared/config.ts"
    "x-pack/test/functional/apps/advanced_settings/config.ts"
    "x-pack/test/functional/apps/aiops/config.ts"
    "x-pack/test/functional/apps/api_keys/config.ts"
    "x-pack/test/functional/apps/canvas/config.ts"
    "x-pack/test/functional/apps/cross_cluster_replication/config.ts"
    "x-pack/test/functional/apps/dashboard/group1/config.ts"
    "x-pack/test/functional/apps/dashboard/group2/config.ts"
    "x-pack/test/functional/apps/dashboard/group3/config.ts"
    "x-pack/test/functional/apps/data_views/config.ts"
    "x-pack/test/functional/apps/dev_tools/config.ts"
    "x-pack/test/functional/apps/discover/config.ts"
    "x-pack/test/functional/apps/graph/config.ts"
    "x-pack/test/functional/apps/grok_debugger/config.ts"
    "x-pack/test/functional/apps/home/config.ts"
    "x-pack/test/functional/apps/index_lifecycle_management/config.ts"
    "x-pack/test/functional/apps/index_management/config.ts"
    "x-pack/test/functional/apps/infra/config.ts"
    "x-pack/test/functional/apps/ingest_pipelines/config.ts"
    "x-pack/test/functional/apps/lens/group1/config.ts"
    "x-pack/test/functional/apps/lens/group2/config.ts"
    "x-pack/test/functional/apps/lens/group3/config.ts"
    "x-pack/test/functional/apps/lens/group4/config.ts"
    "x-pack/test/functional/apps/lens/group5/config.ts"
    "x-pack/test/functional/apps/lens/group6/config.ts"
    "x-pack/test/functional/apps/lens/open_in_lens/tsvb/config.ts"
    "x-pack/test/functional/apps/lens/open_in_lens/agg_based/config.ts"
    "x-pack/test/functional/apps/lens/open_in_lens/dashboard/config.ts"
    "x-pack/test/functional/apps/license_management/config.ts"
    "x-pack/test/functional/apps/logstash/config.ts"
    "x-pack/test/functional/apps/managed_content/config.ts"
    "x-pack/test/functional/apps/management/config.ts"
    "x-pack/test/functional/apps/maps/group1/config.ts"
    "x-pack/test/functional/apps/maps/group2/config.ts"
    "x-pack/test/functional/apps/maps/group3/config.ts"
    "x-pack/test/functional/apps/maps/group4/config.ts"
    "x-pack/test/functional/apps/ml/anomaly_detection_jobs/config.ts"
    "x-pack/test/functional/apps/ml/anomaly_detection_integrations/config.ts"
    "x-pack/test/functional/apps/ml/anomaly_detection_result_views/config.ts"
    "x-pack/test/functional/apps/ml/data_frame_analytics/config.ts"
    "x-pack/test/functional/apps/ml/data_visualizer/config.ts"
    "x-pack/test/functional/apps/ml/permissions/config.ts"
    "x-pack/test/functional/apps/ml/short_tests/config.ts"
    "x-pack/test/functional/apps/ml/stack_management_jobs/config.ts"
    "x-pack/test/functional/apps/ml/memory_usage/config.ts"
    "x-pack/test/functional/apps/monitoring/config.ts"
    "x-pack/test/functional/apps/painless_lab/config.ts"
    "x-pack/test/functional/apps/remote_clusters/config.ts"
    "x-pack/test/functional/apps/reporting_management/config.ts"
    "x-pack/test/functional/apps/rollup_job/config.ts"
    "x-pack/test/functional/apps/saved_objects_management/config.ts"
    "x-pack/test/functional/apps/saved_query_management/config.ts"
    "x-pack/test/functional/apps/security/config.ts"
    "x-pack/test/functional/apps/snapshot_restore/config.ts"
    "x-pack/test/functional/apps/spaces/config.ts"
    "x-pack/test/functional/apps/spaces/solution_view_flag_enabled/config.ts"
    "x-pack/test/functional/apps/status_page/config.ts"
    "x-pack/test/functional/apps/transform/creation/index_pattern/config.ts"
    "x-pack/test/functional/apps/transform/creation/runtime_mappings_saved_search/config.ts"
    "x-pack/test/functional/apps/transform/actions/config.ts"
    "x-pack/test/functional/apps/transform/edit_clone/config.ts"
    "x-pack/test/functional/apps/transform/permissions/config.ts"
    "x-pack/test/functional/apps/transform/feature_controls/config.ts"
    "x-pack/test/functional/apps/upgrade_assistant/config.ts"
    "x-pack/test/functional/apps/user_profiles/config.ts"
    "x-pack/test/functional/apps/visualize/config.ts"
    "x-pack/test/functional/apps/watcher/config.ts"
    "x-pack/test/functional/config_security_basic.ts"
    "x-pack/test/functional/config.ccs.ts"
    "x-pack/test/functional/config.firefox.js"
    "x-pack/test/functional/config.upgrade_assistant.ts"
    "x-pack/test/functional_cloud/config.ts"
    "x-pack/test/functional_solution_sidenav/config.ts"
    "x-pack/test/functional_search/config.ts"
    "x-pack/test/kubernetes_security/basic/config.ts"
    "x-pack/test/licensing_plugin/config.public.ts"
    "x-pack/test/licensing_plugin/config.ts"
    "x-pack/test/monitoring_api_integration/config.ts"
    "x-pack/test/plugin_api_integration/config.ts"
    "x-pack/test/plugin_functional/config.ts"
    "x-pack/test/reporting_api_integration/reporting_and_security.config.ts"
    "x-pack/test/reporting_api_integration/reporting_without_security.config.ts"
    "x-pack/test/reporting_functional/reporting_and_deprecated_security.config.ts"
    "x-pack/test/reporting_functional/reporting_and_security.config.ts"
    "x-pack/test/reporting_functional/reporting_without_security.config.ts"
    "x-pack/test/rule_registry/security_and_spaces/config_basic.ts"
    "x-pack/test/rule_registry/security_and_spaces/config_trial.ts"
    "x-pack/test/rule_registry/spaces_only/config_basic.ts"
    "x-pack/test/rule_registry/spaces_only/config_trial.ts"
    "x-pack/test/saved_object_api_integration/security_and_spaces/config_basic.ts"
    "x-pack/test/saved_object_api_integration/security_and_spaces/config_trial.ts"
    "x-pack/test/saved_object_api_integration/spaces_only/config.ts"
    "x-pack/test/saved_object_api_integration/user_profiles/config.ts"
    "x-pack/test/saved_object_tagging/api_integration/security_and_spaces/config.ts"
    "x-pack/test/saved_object_tagging/api_integration/tagging_api/config.ts"
    "x-pack/test/saved_object_tagging/api_integration/tagging_usage_collection/config.ts"
    "x-pack/test/saved_object_tagging/functional/config.ts"
    "x-pack/test/saved_objects_field_count/config.ts"
    "x-pack/test/search_sessions_integration/config.ts"
    "x-pack/test/security_api_integration/anonymous_es_anonymous.config.ts"
    "x-pack/test/security_api_integration/anonymous.config.ts"
    "x-pack/test/security_api_integration/api_keys.config.ts"
    "x-pack/test/security_api_integration/audit.config.ts"
    "x-pack/test/security_api_integration/http_bearer.config.ts"
    "x-pack/test/security_api_integration/http_no_auth_providers.config.ts"
    "x-pack/test/security_api_integration/kerberos_anonymous_access.config.ts"
    "x-pack/test/security_api_integration/kerberos.config.ts"
    "x-pack/test/security_api_integration/login_selector.config.ts"
    "x-pack/test/security_api_integration/oidc_implicit_flow.config.ts"
    "x-pack/test/security_api_integration/oidc.config.ts"
    "x-pack/test/security_api_integration/oidc.http2.config.ts"
    "x-pack/test/security_api_integration/pki.config.ts"
    "x-pack/test/security_api_integration/saml.config.ts"
    "x-pack/test/security_api_integration/saml.http2.config.ts"
    "x-pack/test/security_api_integration/saml_cloud.config.ts"
    "x-pack/test/security_api_integration/chips.config.ts"
    "x-pack/test/security_api_integration/features.config.ts"
    "x-pack/test/security_api_integration/session_idle.config.ts"
    "x-pack/test/security_api_integration/session_invalidate.config.ts"
    "x-pack/test/security_api_integration/session_lifespan.config.ts"
    "x-pack/test/security_api_integration/session_concurrent_limit.config.ts"
    "x-pack/test/security_api_integration/token.config.ts"
    "x-pack/test/security_api_integration/user_profiles.config.ts"
    "x-pack/test/security_functional/login_selector.config.ts"
    "x-pack/test/security_functional/oidc.config.ts"
    "x-pack/test/security_functional/saml.config.ts"
    "x-pack/test/security_functional/saml.http2.config.ts"
    "x-pack/test/security_functional/oidc.http2.config.ts"
    "x-pack/test/security_functional/insecure_cluster_warning.config.ts"
    "x-pack/test/security_functional/user_profiles.config.ts"
    "x-pack/test/security_functional/expired_session.config.ts"
    "x-pack/test/session_view/basic/config.ts"
    "x-pack/test/spaces_api_integration/security_and_spaces/config_basic.ts"
    "x-pack/test/spaces_api_integration/security_and_spaces/copy_to_space_config_basic.ts"
    "x-pack/test/spaces_api_integration/security_and_spaces/config_trial.ts"
    "x-pack/test/spaces_api_integration/security_and_spaces/copy_to_space_config_trial.ts"
    "x-pack/test/spaces_api_integration/spaces_only/config.ts"
    "x-pack/test/task_manager_claimer_update_by_query/config.ts"
    "x-pack/test/ui_capabilities/security_and_spaces/config.ts"
    "x-pack/test/ui_capabilities/spaces_only/config.ts"
    "x-pack/test/upgrade_assistant_integration/config.ts"
    "x-pack/test/usage_collection/config.ts"
    "x-pack/performance/journeys_e2e/aiops_log_rate_analysis.ts"
    "x-pack/performance/journeys_e2e/ecommerce_dashboard.ts"
    "x-pack/performance/journeys_e2e/ecommerce_dashboard_http2.ts"
    "x-pack/performance/journeys_e2e/ecommerce_dashboard_map_only.ts"
    "x-pack/performance/journeys_e2e/flight_dashboard.ts"
    "x-pack/performance/journeys_e2e/login.ts"
    "x-pack/performance/journeys_e2e/many_fields_discover.ts"
    "x-pack/performance/journeys_e2e/many_fields_discover_esql.ts"
    "x-pack/performance/journeys_e2e/many_fields_lens_editor.ts"
    "x-pack/performance/journeys_e2e/many_fields_transform.ts"
    "x-pack/performance/journeys_e2e/tsdb_logs_data_visualizer.ts"
    "x-pack/performance/journeys_e2e/promotion_tracking_dashboard.ts"
    "x-pack/performance/journeys_e2e/web_logs_dashboard.ts"
    "x-pack/performance/journeys_e2e/web_logs_dashboard_esql.ts"
    "x-pack/performance/journeys_e2e/web_logs_dashboard_dataview.ts"
    "x-pack/performance/journeys_e2e/data_stress_test_lens.ts"
    "x-pack/performance/journeys_e2e/data_stress_test_lens_http2.ts"
    "x-pack/performance/journeys_e2e/ecommerce_dashboard_saved_search_only.ts"
    "x-pack/performance/journeys_e2e/ecommerce_dashboard_tsvb_gauge_only.ts"
    "x-pack/performance/journeys_e2e/dashboard_listing_page.ts"
    "x-pack/performance/journeys_e2e/tags_listing_page.ts"
    "x-pack/performance/journeys_e2e/cloud_security_dashboard.ts"
    "x-pack/performance/journeys_e2e/apm_service_inventory.ts"
    "x-pack/performance/journeys_e2e/infra_hosts_view.ts"
    "x-pack/test/custom_branding/config.ts"
    "x-pack/test/api_integration/deployment_agnostic/configs/stateful/platform.stateful.config.ts"
    "x-pack/test/api_integration/apis/cloud/config.ts"
    "x-pack/test/alerting_api_integration/observability/config.ts"
    "x-pack/test/api_integration/apis/logs_ui/config.ts"
    "x-pack/test/api_integration/apis/logs_shared/config.ts"
    "x-pack/test/api_integration/apis/metrics_ui/config.ts"
    "x-pack/test/api_integration/apis/osquery/config.ts"
    "x-pack/test/api_integration/apis/synthetics/config.ts"
    "x-pack/test/api_integration/apis/uptime/config.ts"
    "x-pack/test/api_integration/apis/entity_manager/config.ts"
    "x-pack/test/apm_api_integration/basic/config.ts"
    "x-pack/test/apm_api_integration/cloud/config.ts"
    "x-pack/test/apm_api_integration/rules/config.ts"
    "x-pack/test/apm_api_integration/trial/config.ts"
    "x-pack/test/dataset_quality_api_integration/basic/config.ts"
    "x-pack/test/functional/apps/observability_logs_explorer/config.ts"
    "x-pack/test/functional/apps/dataset_quality/config.ts"
    "x-pack/test/functional/apps/slo/embeddables/config.ts"
    "x-pack/test/functional/apps/uptime/config.ts"
    "x-pack/test/observability_api_integration/basic/config.ts"
    "x-pack/test/observability_api_integration/trial/config.ts"
    "x-pack/test/observability_functional/with_rac_write.config.ts"
    "x-pack/test/observability_onboarding_api_integration/basic/config.ts"
    "x-pack/test/observability_onboarding_api_integration/cloud/config.ts"
    "x-pack/test/observability_ai_assistant_api_integration/enterprise/config.ts"
    "x-pack/test/observability_ai_assistant_functional/enterprise/config.ts"
    "x-pack/test/profiling_api_integration/cloud/config.ts"
    "x-pack/test/functional/apps/apm/config.ts"
    "x-pack/test/api_integration/deployment_agnostic/configs/stateful/oblt.stateful.config.ts"
    "x-pack/test/api_integration/deployment_agnostic/configs/stateful/oblt.apm.stateful.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/actions/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/alerts/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/alerts/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/date_types/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/float/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/integer/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/double/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/ips/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/keyword/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/long/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/text/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/workflows/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/eql/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/esql/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/general_logic/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/indicator_match/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/machine_learning/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/new_terms/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/query/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/threshold/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_gaps/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_creation/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_creation/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_patch/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_patch/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_update/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_update/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/bundled_prebuilt_rules_package/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/large_prebuilt_rules_package/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/management/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/update_prebuilt_rules_package/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/prebuilt_rule_customization/customization_enabled/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/prebuilt_rule_customization/customization_disabled/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_bulk_actions/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_delete/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_delete/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_import_export/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_import_export/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_management/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_management/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_read/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_read/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/telemetry/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/telemetry/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/detections_response/user_roles/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/entity_analytics/risk_engine/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/entity_analytics/risk_engine/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/entity_analytics/entity_store/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/lists_and_exception_lists/exception_lists_items/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/lists_and_exception_lists/lists_items/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/explore/hosts/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/explore/network/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/explore/users/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/explore/overview/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/investigation/saved_objects/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/investigation/saved_objects/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/investigation/timeline/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/investigation/timeline/basic_license_essentials_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/sources/indices/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/edr_workflows/artifacts/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/edr_workflows/authentication/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/edr_workflows/metadata/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/edr_workflows/package/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/edr_workflows/policy_response/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/edr_workflows/resolver/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/edr_workflows/response_actions/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_api_integration/test_suites/edr_workflows/spaces/trial_license_complete_tier/configs/ess.config.ts"
    "x-pack/test/security_solution_endpoint/configs/endpoint.config.ts"
    "x-pack/test/security_solution_endpoint/configs/integrations.config.ts"
    "x-pack/test/api_integration/apis/cloud_security_posture/config.ts"
    "x-pack/test/cloud_security_posture_api/config.ts"
    "x-pack/test/cloud_security_posture_functional/config.ts"
    "x-pack/test/cloud_security_posture_functional/config.agentless.ts"
    "x-pack/test/cloud_security_posture_functional/data_views/config.ts"
)

# === Disabled Stateful tests (from .buildkite/ftr_configs_manifests.json)
# x-pack/test/api_integration/deployment_agnostic/default_configs/stateful.config.base.ts
# test/functional/config.base.js
# test/functional/firefox/config.base.ts
# x-pack/test/functional/config.base.js
# x-pack/test/localization/config.base.ts
# test/server_integration/config.base.js
# x-pack/test/functional_with_es_ssl/config.base.ts
# x-pack/test/api_integration/config.ts
# x-pack/test/fleet_api_integration/config.base.ts
# x-pack/test/functional_basic/apps/ml/config.base.ts
# x-pack/test/functional_basic/apps/transform/config.base.ts
# x-pack/test/stack_functional_integration/configs/config.stack_functional_integration_base.js
# x-pack/test/upgrade/config.ts
# test/functional/config.edge.js
# x-pack/test/functional/config.edge.js
# x-pack/test/alerting_api_integration/security_and_spaces/group2/tests/actions/config.ts
# x-pack/test/alerting_api_integration/security_and_spaces/group2/tests/telemetry/config.ts
# x-pack/test/alerting_api_integration/spaces_only_legacy/config.ts
# x-pack/test/cloud_integration/config.ts
# x-pack/test/load/config.ts
# x-pack/test/plugin_api_perf/config.js
# x-pack/test/screenshot_creation/config.ts
# x-pack/test/fleet_packages/config.ts
# x-pack/test/scalability/config.ts
# x-pack/test/fleet_cypress/cli_config.ts
# x-pack/test/fleet_cypress/cli_config.space_awareness.ts
# x-pack/test/fleet_cypress/config.ts
# x-pack/test/fleet_cypress/config.space_awareness.ts
# x-pack/test/fleet_cypress/visual_config.ts
# x-pack/performance/configs/http2_config.ts
# x-pack/plugins/observability_solution/observability_onboarding/e2e/ftr_config_open.ts
# x-pack/plugins/observability_solution/observability_onboarding/e2e/ftr_config_runner.ts
# x-pack/plugins/observability_solution/observability_onboarding/e2e/ftr_config.ts
# x-pack/plugins/observability_solution/apm/ftr_e2e/ftr_config_run.ts
# x-pack/plugins/observability_solution/apm/ftr_e2e/ftr_config.ts
# x-pack/plugins/observability_solution/inventory/e2e/ftr_config_run.ts
# x-pack/plugins/observability_solution/inventory/e2e/ftr_config.ts
# x-pack/plugins/observability_solution/profiling/e2e/ftr_config_open.ts
# x-pack/plugins/observability_solution/profiling/e2e/ftr_config_runner.ts
# x-pack/plugins/observability_solution/profiling/e2e/ftr_config.ts
# x-pack/plugins/observability_solution/uptime/e2e/config.ts
# x-pack/plugins/observability_solution/uptime/e2e/uptime/synthetics_run.ts
# x-pack/plugins/observability_solution/synthetics/e2e/config.ts
# x-pack/plugins/observability_solution/synthetics/e2e/synthetics/synthetics_run.ts
# x-pack/plugins/observability_solution/exploratory_view/e2e/synthetics_run.ts
# x-pack/plugins/observability_solution/ux/e2e/synthetics_run.ts
# x-pack/plugins/observability_solution/slo/e2e/synthetics_run.ts
# x-pack/test/security_solution_api_integration/config/ess/config.base.ts
# x-pack/test/security_solution_api_integration/config/ess/config.base.basic.ts
# x-pack/test/security_solution_api_integration/config/ess/config.base.edr_workflows.trial.ts
# x-pack/test/security_solution_api_integration/config/ess/config.base.edr_workflows.ts
# x-pack/test/security_solution_api_integration/config/ess/config.base.basic.ts
# x-pack/test/security_solution_api_integration/config/ess/config.base.trial.ts
# x-pack/test/security_solution_endpoint/configs/config.base.ts
# x-pack/test/security_solution_endpoint/config.base.ts
# x-pack/test/security_solution_endpoint_api_int/config.base.ts
# x-pack/test/cloud_security_posture_functional/config.cloud.ts
# x-pack/test/defend_workflows_cypress/cli_config.ts
# x-pack/test/defend_workflows_cypress/config.ts
# x-pack/test/osquery_cypress/cli_config.ts
# x-pack/test/osquery_cypress/config.ts
# x-pack/test/osquery_cypress/visual_config.ts
# x-pack/test/security_solution_cypress/cli_config.ts
# x-pack/test/security_solution_cypress/config.ts
# x-pack/test/security_solution_playwright/playwright.config.ts
# x-pack/test/functional_enterprise_search/base_config.ts
# x-pack/test/functional_enterprise_search/cypress.config.ts
# x-pack/test/functional_enterprise_search/visual_config.ts
# x-pack/test/functional_enterprise_search/cli_config.ts
# x-pack/test/functional/apps/search_playground/config.ts


# Enabled Serverless tests (from .buildkite/ftr_configs_manifests.json)
declare -a serverless=(
)

# === Disabled Serverless tests (from .buildkite/ftr_configs_manifests.json)
# x-pack/test/api_integration/deployment_agnostic/default_configs/serverless.config.base.ts
# x-pack/test_serverless/api_integration/config.base.ts
# x-pack/test_serverless/functional/config.base.ts
# x-pack/test_serverless/shared/config.base.ts
# x-pack/test_serverless/functional/test_suites/observability/cypress/oblt_config.base.ts
# x-pack/test_serverless/functional/test_suites/observability/cypress/config_headless.ts
# x-pack/test_serverless/functional/test_suites/observability/cypress/config_runner.ts
# x-pack/test_serverless/api_integration/test_suites/observability/config.ts
# x-pack/test_serverless/api_integration/test_suites/observability/config.feature_flags.ts
# x-pack/test_serverless/api_integration/test_suites/observability/common_configs/config.group1.ts
# x-pack/test_serverless/api_integration/test_suites/observability/fleet/config.ts
# x-pack/test_serverless/api_integration/test_suites/observability/ai_assistant/config.ts
# x-pack/test_serverless/functional/test_suites/observability/config.ts
# x-pack/test_serverless/functional/test_suites/observability/config.examples.ts
# x-pack/test_serverless/functional/test_suites/observability/config.feature_flags.ts
# x-pack/test_serverless/functional/test_suites/observability/config.saved_objects_management.ts
# x-pack/test_serverless/functional/test_suites/observability/config.context_awareness.ts
# x-pack/test_serverless/functional/test_suites/observability/common_configs/config.group1.ts
# x-pack/test_serverless/functional/test_suites/observability/common_configs/config.group2.ts
# x-pack/test_serverless/functional/test_suites/observability/common_configs/config.group3.ts
# x-pack/test_serverless/functional/test_suites/observability/common_configs/config.group4.ts
# x-pack/test_serverless/functional/test_suites/observability/common_configs/config.group5.ts
# x-pack/test_serverless/functional/test_suites/observability/common_configs/config.group6.ts
# x-pack/test_serverless/functional/test_suites/observability/config.screenshots.ts
# x-pack/test/api_integration/deployment_agnostic/configs/serverless/oblt.serverless.config.ts
# x-pack/test/api_integration/deployment_agnostic/configs/serverless/oblt.apm.serverless.config.ts
# x-pack/test/security_solution_api_integration/config/serverless/config.base.ts
# x-pack/test/security_solution_api_integration/config/serverless/config.base.essentials.ts
# x-pack/test/security_solution_api_integration/config/serverless/config.base.edr_workflows.ts
# x-pack/test/defend_workflows_cypress/serverless_config.base.ts
# x-pack/test/osquery_cypress/serverless_config.base.ts
# x-pack/test/defend_workflows_cypress/serverless_config.ts
# x-pack/test/osquery_cypress/serverless_cli_config.ts
# x-pack/test/security_solution_cypress/serverless_config.ts
# x-pack/test/security_solution_playwright/serverless_config.ts
# x-pack/test_serverless/api_integration/config.base.ts
# x-pack/test_serverless/functional/config.base.ts
# x-pack/test_serverless/shared/config.base.ts
# x-pack/test_serverless/api_integration/test_suites/security/config.ts
# x-pack/test_serverless/api_integration/test_suites/security/config.feature_flags.ts
# x-pack/test_serverless/api_integration/test_suites/security/common_configs/config.group1.ts
# x-pack/test_serverless/api_integration/test_suites/security/fleet/config.ts
# x-pack/test_serverless/functional/test_suites/security/config.screenshots.ts
# x-pack/test_serverless/functional/test_suites/security/config.ts
# x-pack/test_serverless/functional/test_suites/security/config.examples.ts
# x-pack/test_serverless/functional/test_suites/security/config.feature_flags.ts
# x-pack/test_serverless/functional/test_suites/security/config.cloud_security_posture.basic.ts
# x-pack/test_serverless/functional/test_suites/security/config.cloud_security_posture.essentials.ts
# x-pack/test_serverless/functional/test_suites/security/config.cloud_security_posture.agentless.ts
# x-pack/test_serverless/functional/test_suites/security/config.cloud_security_posture.agentless_api.ts
# x-pack/test_serverless/functional/test_suites/security/config.saved_objects_management.ts
# x-pack/test_serverless/functional/test_suites/security/config.context_awareness.ts
# x-pack/test_serverless/functional/test_suites/security/common_configs/config.group1.ts
# x-pack/test_serverless/functional/test_suites/security/common_configs/config.group2.ts
# x-pack/test_serverless/functional/test_suites/security/common_configs/config.group3.ts
# x-pack/test_serverless/functional/test_suites/security/common_configs/config.group4.ts
# x-pack/test_serverless/functional/test_suites/security/common_configs/config.group5.ts
# x-pack/test_serverless/functional/test_suites/security/common_configs/config.group6.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/actions/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/alerts/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/alerts/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/date_types/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/float/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/integer/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/double/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/ips/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/keyword/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/long/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/operators_data_types/text/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/exceptions/workflows/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/eql/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/esql/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/general_logic/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/indicator_match/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/machine_learning/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/new_terms/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/query/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_execution_logic/threshold/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/detection_engine/rule_gaps/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_creation/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_creation/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_patch/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_patch/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_update/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_update/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/bundled_prebuilt_rules_package/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/large_prebuilt_rules_package/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/management/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/update_prebuilt_rules_package/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/prebuilt_rule_customization/customization_enabled/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/prebuilt_rules/prebuilt_rule_customization/customization_disabled/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_bulk_actions/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_delete/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_delete/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_import_export/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_import_export/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_management/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_management/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_read/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/rules_management/rule_read/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/telemetry/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/telemetry/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/detections_response/user_roles/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/genai/nlp_cleanup_task/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/genai/nlp_cleanup_task/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/genai/knowledge_base/entries/trial_license_complete_tier/configs/ess.config.ts
# x-pack/test/security_solution_api_integration/test_suites/genai/knowledge_base/entries/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/entity_analytics/risk_engine/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/entity_analytics/risk_engine/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/entity_analytics/entity_store/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/lists_and_exception_lists/exception_lists_items/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/lists_and_exception_lists/authorization/exceptions/lists/essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/lists_and_exception_lists/authorization/exceptions/common/essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/lists_and_exception_lists/authorization/exceptions/items/essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/lists_and_exception_lists/lists_items/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/explore/hosts/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/explore/network/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/explore/users/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/explore/overview/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/investigation/saved_objects/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/investigation/saved_objects/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/investigation/timeline/basic_license_essentials_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/investigation/timeline/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/sources/indices/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/edr_workflows/artifacts/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/edr_workflows/authentication/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/edr_workflows/metadata/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/edr_workflows/package/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/edr_workflows/policy_response/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/edr_workflows/resolver/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/edr_workflows/response_actions/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_api_integration/test_suites/edr_workflows/spaces/trial_license_complete_tier/configs/serverless.config.ts
# x-pack/test/security_solution_endpoint/configs/serverless.endpoint.config.ts
# x-pack/test/security_solution_endpoint/configs/serverless.integrations.config.ts
# x-pack/test/api_integration/deployment_agnostic/configs/serverless/security.serverless.config.ts
# x-pack/test_serverless/api_integration/test_suites/search/config.ts
# x-pack/test_serverless/api_integration/test_suites/search/config.feature_flags.ts
# x-pack/test_serverless/api_integration/test_suites/search/common_configs/config.group1.ts
# x-pack/test_serverless/functional/test_suites/search/config.ts
# x-pack/test_serverless/functional/test_suites/search/config.examples.ts
# x-pack/test_serverless/functional/test_suites/search/config.feature_flags.ts
# x-pack/test_serverless/functional/test_suites/search/config.screenshots.ts
# x-pack/test_serverless/functional/test_suites/search/config.saved_objects_management.ts
# x-pack/test_serverless/functional/test_suites/search/config.context_awareness.ts
# x-pack/test_serverless/functional/test_suites/search/common_configs/config.group1.ts
# x-pack/test_serverless/functional/test_suites/search/common_configs/config.group2.ts
# x-pack/test_serverless/functional/test_suites/search/common_configs/config.group3.ts
# x-pack/test_serverless/functional/test_suites/search/common_configs/config.group4.ts
# x-pack/test_serverless/functional/test_suites/search/common_configs/config.group5.ts
# x-pack/test_serverless/functional/test_suites/search/common_configs/config.group6.ts
# x-pack/test/api_integration/deployment_agnostic/configs/serverless/search.serverless.config.ts

declare -a failedConfigs=()

set +e;
for config in "${stateful[@]}"
do
    echo "=== ${config}"
    node scripts/functional_tests --bail --config "${config}"
    exitCode=$?
    if [[ $exitCode != 0 ]]; then
        failedConfigs+=("${config}")
        echo "--- FAILED ${config}"
    fi
done

for config in "${serverless[@]}"
do
    echo "=== ${config}"
    node scripts/functional_tests --bail --config "${config}"
    exitCode=$?
    if [[ $exitCode != 0 ]]; then
        failedConfigs+=("${config}")
        echo "--- FAILED ${config}"
    fi
done
set -e

echo "--------------------------------------"
echo "=== Failed Configs"
for failed in "${failedConfigs[@]}"
do
    echo "  ${failed}"
done
