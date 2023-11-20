{
  "maintainer": "Sankalp@ibm.com",
  "package_name": "statsd",
  "github_url": "https://github.com/statsd/statsd",
  "version": "v0.10.2",
  "default_branch": "master",
  "build_script": "build_statsd.sh",
  "docker_build": true,
  "validate_build_script": true,
  "use_non_root_user": true,
  "package_dir": "statsd/statsd/",
  "docker_cmd": "docker build -t ${package_name}:$PACKAGE_VERSION ${dir}",
  "v0.9.0": {
    "dir": "0.9.0",
    "build_script": "build_statsd.sh"
  },
  "v0.8.6": {
    "dir": "0.8.6",
    "build_script": "build_statsd.sh"
  },
  "v0.8.5": {
    "dir": "0.8.5",
    "build_script": "build_statsd.sh"
  },
  "v0.10.1": {
    "dir": "0.10.1",
    "build_script": "build_statsd.sh"
  },
  "v0.10.2": {
    "dir": "0.10.2",
    "build_script": "build_statsd.sh"
  },
  "v7.16.3": {
    "dir": "7.16.3_ubi_8",
    "patches": {
      "PATCH": "https://raw.githubusercontent.com/ppc64le/build-scripts/master/e/elasticsearch/elasticsearch_v7.16.3.patch"
    },
    "build_script": "elasticsearch_v7.16.3_ubi_8.5.sh"
  },
  "v7.17.*": {
    "dir": "7.17.2_ubi_8",
    "patches": {
      "PATCH": "https://raw.githubusercontent.com/ppc64le/build-scripts/master/e/elasticsearch/elasticsearch_v7.17.2.patch"
    },
    "build_script": "elasticsearch_v7.17.2_ubi_8.5.sh"
  },
  "v7.17.10": {
    "dir": "7.17.10_ubi_8",
    "patches": {
      "PATCH": "https://raw.githubusercontent.com/ppc64le/build-scripts/master/e/elasticsearch/elasticsearch_v7.17.10.patch"
    },
    "build_script": "elasticsearch_v7.17.10_ubi_8.5.sh"
  },
  "v7.13.*": {
    "dir": "7.13.0_ubi_8",
    "patches": {
      "PATCH": "https://raw.githubusercontent.com/ppc64le/build-scripts/master/e/elasticsearch/elasticsearch_v7.13.0.patch"
    },
    "build_script": "elasticsearch_v7.13.0_ubi_8.5.sh"
  },
  "v8.1.0": {
    "dir": "8.1.0_ubi_8",
    "patches": {
      "PATCH": "https://raw.githubusercontent.com/ppc64le/build-scripts/master/e/elasticsearch/elasticsearch_v8.1.0.patch"
    },
    "build_script": "elasticsearch_v8.1.0_ubi_8.5.sh"
  },
  "v8.1.*, v8.2.0": {
    "dir": "8.1.0_ubi_8",
    "patches": {
      "PATCH": "https://raw.githubusercontent.com/ppc64le/build-scripts/master/e/elasticsearch/elasticsearch_v8.1.1.patch"
    },
    "build_script": "elasticsearch_v8.1.1_ubi_8.5.sh"
  },
  "v8.2.1": {
    "dir": "8.1.0_ubi_8",
    "patches": {
      "PATCH": "https://raw.githubusercontent.com/ppc64le/build-scripts/master/e/elasticsearch/elasticsearch_v8.2.1.patch"
    },
    "build_script": "elasticsearch_v8.2.1_ubi_8.5.sh"
  },
  "v8.3.*, v8.4.*": {
    "dir": "8.3.2_ubi_8",
    "patches": {
      "PATCH": "https://raw.githubusercontent.com/ppc64le/build-scripts/master/e/elasticsearch/elasticsearch_v8.3.2.patch"
    },
    "build_script": "elasticsearch_v8.3.2_ubi_8.5.sh"
  },
  "v*.*.*": {
    "dir": "/",
    "build_script": "build_statsd.sh"
  }
}
