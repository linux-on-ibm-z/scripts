// this file has been modified with the assistance of AI Tool [claude 4.6]
// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2016-present Datadog, Inc.

//go:build linux && s390x

package ptracer

import (
	"syscall"

	"golang.org/x/sys/unix"
)

const (
	OpenNr           = unix.SYS_OPEN              // OpenNr defines the syscall ID for s390x
	OpenatNr         = unix.SYS_OPENAT            // OpenatNr defines the syscall ID for s390x
	Openat2Nr        = unix.SYS_OPENAT2           // Openat2Nr defines the syscall ID for s390x
	CreatNr          = unix.SYS_CREAT             // CreatNr defines the syscall ID for s390x
	NameToHandleAtNr = unix.SYS_NAME_TO_HANDLE_AT // NameToHandleAtNr defines the syscall ID for s390x
	OpenByHandleAtNr = unix.SYS_OPEN_BY_HANDLE_AT // OpenByHandleAtNr defines the syscall ID for s390x
	ExecveNr         = unix.SYS_EXECVE            // ExecveNr defines the syscall ID for s390x
	ExecveatNr       = unix.SYS_EXECVEAT          // ExecveatNr defines the syscall ID for s390x
	CloneNr          = unix.SYS_CLONE             // CloneNr defines the syscall ID for s390x
	Clone3Nr         = unix.SYS_CLONE3            // Clone3Nr defines the syscall ID for s390x
	ForkNr           = unix.SYS_FORK              // ForkNr defines the syscall ID for s390x
	VforkNr          = unix.SYS_VFORK             // VforkNr defines the syscall ID for s390x
	ExitNr           = unix.SYS_EXIT              // ExitNr defines the syscall ID for s390x
	FcntlNr          = unix.SYS_FCNTL             // FcntlNr defines the syscall ID for s390x
	DupNr            = unix.SYS_DUP               // DupNr defines the syscall ID for s390x
	Dup2Nr           = unix.SYS_DUP2              // Dup2Nr defines the syscall ID for s390x
	Dup3Nr           = unix.SYS_DUP3              // Dup3Nr defines the syscall ID for s390x
	ChdirNr          = unix.SYS_CHDIR             // ChdirNr defines the syscall ID for s390x
	FchdirNr         = unix.SYS_FCHDIR            // FchdirNr defines the syscall ID for s390x
	SetuidNr         = unix.SYS_SETUID            // SetuidNr defines the syscall ID for s390x
	SetgidNr         = unix.SYS_SETGID            // SetgidNr defines the syscall ID for s390x
	SetreuidNr       = unix.SYS_SETREUID          // SetreuidNr defines the syscall ID for s390x
	SetregidNr       = unix.SYS_SETREGID          // SetregidNr defines the syscall ID for s390x
	SetresuidNr      = unix.SYS_SETRESUID         // SetresuidNr defines the syscall ID for s390x
	SetresgidNr      = unix.SYS_SETRESGID         // SetresgidNr defines the syscall ID for s390x
	SetfsuidNr       = unix.SYS_SETFSUID          // SetfsuidNr defines the syscall ID for s390x
	SetfsgidNr       = unix.SYS_SETFSGID          // SetfsgidNr defines the syscall ID for s390x
	CloseNr          = unix.SYS_CLOSE             // CloseNr defines the syscall ID for s390x
	MemfdCreateNr    = unix.SYS_MEMFD_CREATE      // MemfdCreateNr defines the syscall ID for s390x
	CapsetNr         = unix.SYS_CAPSET            // CapsetNr defines the syscall ID for s390x
	UnlinkNr         = unix.SYS_UNLINK            // UnlinkNr defines the syscall ID for s390x
	UnlinkatNr       = unix.SYS_UNLINKAT          // UnlinkatNr defines the syscall ID for s390x
	RmdirNr          = unix.SYS_RMDIR             // RmdirNr defines the syscall ID for s390x
	RenameNr         = unix.SYS_RENAME            // RenameNr defines the syscall ID for s390x
	RenameAtNr       = unix.SYS_RENAMEAT          // RenameAtNr defines the syscall ID for s390x
	RenameAt2Nr      = unix.SYS_RENAMEAT2         // RenameAt2Nr defines the syscall ID for s390x
	MkdirNr          = unix.SYS_MKDIR             // MkdirNr defines the syscall ID for s390x
	MkdirAtNr        = unix.SYS_MKDIRAT           // MkdirAtNr defines the syscall ID for s390x
	UtimeNr          = unix.SYS_UTIME             // UtimeNr defines the syscall ID for s390x
	UtimesNr         = unix.SYS_UTIMES            // UtimesNr defines the syscall ID for s390x
	UtimensAtNr      = unix.SYS_UTIMENSAT         // UtimensAtNr defines the syscall ID for s390x
	FutimesAtNr      = unix.SYS_FUTIMESAT         // FutimesAtNr defines the syscall ID for s390x
	LinkNr           = unix.SYS_LINK              // LinkNr defines the syscall ID for s390x
	LinkAtNr         = unix.SYS_LINKAT            // LinkAtNr defines the syscall ID for s390x
	SymlinkNr        = unix.SYS_SYMLINK           // SymlinkNr defines the syscall ID for s390x
	SymlinkAtNr      = unix.SYS_SYMLINKAT         // SymlinkAtNr defines the syscall ID for s390x
	ChmodNr          = unix.SYS_CHMOD             // ChmodNr defines the syscall ID for s390x
	FchmodNr         = unix.SYS_FCHMOD            // FchmodNr defines the syscall ID for s390x
	FchmodAtNr       = unix.SYS_FCHMODAT          // FchmodAtNr defines the syscall ID for s390x
	FchmodAt2Nr      = unix.SYS_FCHMODAT2         // FchmodAt2Nr defines the syscall ID for s390x
	ChownNr          = unix.SYS_CHOWN             // ChownNr defines the syscall ID for s390x
	FchownNr         = unix.SYS_FCHOWN            // FchownNr defines the syscall ID for s390x
	FchownAtNr       = unix.SYS_FCHOWNAT          // FchownAtNr defines the syscall ID for s390x
	LchownNr         = unix.SYS_LCHOWN            // LchownNr defines the syscall ID for s390x
	InitModuleNr     = unix.SYS_INIT_MODULE       // InitModuleNr defines the syscall ID for s390x
	FInitModuleNr    = unix.SYS_FINIT_MODULE      // FInitModuleNr defines the syscall ID for s390x
	DeleteModuleNr   = unix.SYS_DELETE_MODULE     // DeleteModuleNr defines the syscall ID for s390x
	IoctlNr          = unix.SYS_IOCTL             // IoctlNr defines the syscall ID for s390x
	MountNr          = unix.SYS_MOUNT             // MountNr defines the syscall ID for s390x
	Umount2Nr        = unix.SYS_UMOUNT2           // Umount2Nr defines the syscall ID for s390x
	PipeNr           = unix.SYS_PIPE              // PipeNr defines the syscall ID for s390x
	Pipe2Nr          = unix.SYS_PIPE2             // Pipe2Nr defines the syscall ID for s390x
	ConnectNr        = unix.SYS_CONNECT           // ConnectNr defines the syscall ID for s390x
	Accept4Nr        = unix.SYS_ACCEPT4           // Accept4Nr defines the syscall ID for s390x
	AcceptNr         = unix.SYS_ACCEPT4           // AcceptNr uses ACCEPT4 on s390x (SYS_ACCEPT not available)
	BindNr           = unix.SYS_BIND              // BindNr defines the syscall ID for s390x
	SocketNr         = unix.SYS_SOCKET            // SocketNr defines the syscall ID for s390x
	SetsockoptNr     = unix.SYS_SETSOCKOPT        // SetsockoptNr defines the syscall ID for s390x
	SetrlimitNr      = unix.SYS_SETRLIMIT         // SetrlimitNr defines the syscall ID for s390x
	Prlimit64Nr      = unix.SYS_PRLIMIT64         // Prlimit64Nr defines the syscall ID for s390x
	PrctlNr          = unix.SYS_PRCTL             // PrctlNr defines the syscall ID for s390x
)

// s390x ptrace register mapping:
//
// Under ptrace SYSCALL-enter-stop on s390x:
//   Gprs[2]    = syscall number (the kernel places it here; overwritten with
//                return value at syscall-exit-stop)
//   orig_gpr2  = first syscall argument (arg0)
//   Gprs[3]    = second argument (arg1)
//   Gprs[4]    = third argument (arg2)
//   Gprs[5]    = fourth argument (arg3)
//   Gprs[6]    = fifth argument (arg4)
//   Gprs[7]    = sixth argument (arg5)
//
// Note: In userspace, Go places the syscall number in R1 and the first
// argument in R2 (via the SVC instruction). The kernel then rearranges
// these for ptrace: it saves the original R2 (first arg) in orig_gpr2
// and puts the syscall number in gprs[2].
//
// References:
//   - strace src/linux/s390/get_scno.c: uses gprs[2] for syscall number
//   - kernel arch/s390/include/asm/syscall.h: orig_gpr2 = args[0]

func (t *Tracer) argToRegValue(regs syscall.PtraceRegs, arg int) uint64 {
	switch arg {
	case 0:
		// First argument is saved in orig_gpr2 by the kernel
		return regs.Orig_gpr2
	case 1:
		return regs.Gprs[3]
	case 2:
		return regs.Gprs[4]
	case 3:
		return regs.Gprs[5]
	case 4:
		return regs.Gprs[6]
	case 5:
		return regs.Gprs[7]
	}
	return 0
}

// ReadRet reads and returns the return value
func (t *Tracer) ReadRet(regs syscall.PtraceRegs) int64 {
	// s390x: return value is in GPR2 (at syscall-exit-stop)
	return int64(regs.Gprs[2])
}

// GetSyscallNr returns the given syscall number
func GetSyscallNr(regs syscall.PtraceRegs) int {
	// s390x: at syscall-enter-stop, the kernel places the syscall number
	// in GPR2. This is consistent with how strace reads it.
	return int(regs.Gprs[2])
}
