// this file has been modified with the assistance of AI Tool [claude 4.6]
// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2016-present Datadog, Inc.

//go:build linux && functionaltests && s390x

package tests

var supportedSyscalls = map[string]uintptr{}
