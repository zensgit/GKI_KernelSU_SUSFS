# KernelSU Next 3.4.1 / SUSFS 2.2.0 integration

This recipe targets built-in KernelSU on the existing xuanyuan ARM64 GKI base.
It does not build a generic KernelSU LKM.

## Sources

- Android common: `e56cf6b09cca2151bcee244b3d334fb68685ff57` (unchanged).
- Official KernelSU Next v3.4.1: `8f902aeb16033024143ae36cf711df902cf02fae`;
  full-history revision count 3333, kernel version 33333, UAPI 5.
- SUSFS 2.2.0: `e7b28525f69ca5864bed7db51f77663f5adfe218` (unchanged).
- Legacy WildKernels compatibility reference:
  `757201d983e2549dc7945a21fa6a056eb2e55263`. Its generated v3.3.0 KSU patch
  reproduces SHA256 `944509d27414c9c9c4e728fa17aad447fda4ccd9c50474ee7ce28b6cce5a1476`.
- The post-exec scoped-session mechanism and separate kernel-filename SULog
  adapters follow the maintained integration in
  [pershoot c4653cc4](https://github.com/pershoot/KernelSU-Next/commit/c4653cc4ca61a2160ad819d615ea42811e295192).
  The complete fork, SUSFS 2.3, additional manager signatures, feature-forcing,
  and later unrelated changes are not imported.

## Port boundaries

`ksun341-susfs220.patch` applies directly to the exact official 3.4.1 source.
It retains the established SUSFS 2.2 manual hooks rather than enabling a second
native syscall hook path. It preserves UAPI 5, services events, scoped driver
FD private data and ioctl permission checks, and the 3.4.1 seccomp backport
probe. The ARM64 instruction helper and symbol resolver are built because the
new seccomp probe uses them.

Only a successful allowlist check and root-profile application returns zero
from the manual su pre-hook. Ordinary exec, init-only handling, denied su,
and profile failures cannot qualify as a new su session. Two profile failure
branches now return their errors instead of an accidental zero: the
`TIF_KSU_DISABLE_ESCAPE_WITH_ROOT` denial and `set_cred_ucounts` failure.
Existing-root handling retains the official behavior.

`susfs220-ksun341-post-exec.patch` changes only `common/fs/exec.c`, after the
unchanged original SUSFS 2.2 common patch. It tracks a successful su rewrite,
then calls the paired post-hook immediately after `bprm_execve` and before
cleanup. The scoped FD is installed only when exec returns success. All early
allocation/argument/copy failures skip that hook. This preserves the original
SUSFS 2.2 userspace ABI; the existing matching helper remains compatible.

`ksun-version-pin.patch` supplies the verified release version inside Kleaf's
sandbox, where the external KSU Git directory may not be visible.

## Validation before compilation

- The legacy KSU combined patch was reproduced byte-for-byte before porting.
- The 24 affected original common files were downloaded at the pinned commit
  and their Git blob IDs matched the commit's Gitiles directory trees.
- The pinned common `.gitattributes` (`*.[ch] diff=cpp`) was reproduced. The
  original common combined patch with 9-digit blob abbreviations reproduces
  SHA256 `b21dd46c037ae5f68c8c0d4a36c73dfd4f686cb704190a49f6f579402625fc9c`.
- New combined diffs use `--full-index`, so repository object-count-dependent
  hash abbreviation cannot change their checksums.
- Fresh official KSU worktree: strict `git apply --check`, apply, complete
  combined hash check, version patch check/apply, and patched-tree
  `git diff --check` passed.
- Independent common checkout: original patch dry-run/apply and post-exec
  `git apply --check`/apply passed; 27 common files remain affected, and only
  `fs/exec.c` differs from the original SUSFS 2.2 patched output.

Compilation, strict ABI validation, temporary boot, and live root/SUSFS
checks remain separate required gates. Custom nonzero-UID root profiles and
application-specific hiding are not established by these source checks.
