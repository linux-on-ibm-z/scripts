// this file has been modified with the assistance of AI Tool [claude 4.6]
// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2016-present Datadog, Inc.

//go:build linux

// Package model holds model related files
package model

var (
	// ptraceArchConstants are the supported ptrace commands for the ptrace syscall on s390x
	// generate_constants:Ptrace constants,Ptrace constants are the supported ptrace commands for the ptrace syscall.
	ptraceArchConstants = map[string]uint32{
		// s390x does not define arch-specific ptrace constants beyond the
		// generic ones. PTRACE_SINGLEBLOCK and PTRACE_SYSEMU are available
		// on s390x but are defined generically in the kernel headers.
	}

	// mmapFlagArchConstants are the supported flags for the mmap syscall on s390x
	// generate_constants:MMap flags,MMap flags are the supported flags for the mmap syscall.
	mmapFlagArchConstants = map[string]uint64{}
)
