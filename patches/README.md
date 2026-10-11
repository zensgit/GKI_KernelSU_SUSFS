# KernelSU Next 3.4.1 / SUSFS 2.3.0 integration

This recipe targets built-in KernelSU on the existing xuanyuan ARM64 GKI base.
It does not build a generic KernelSU LKM.

## Exact sources and checksums

- Android common: `e56cf6b09cca2151bcee244b3d334fb68685ff57` (unchanged).
- Official KernelSU Next v3.4.1: `8f902aeb16033024143ae36cf711df902cf02fae`;
  full-history revision count 3333, kernel version 33333, UAPI 5.
- SUSFS 2.3.0: `a0f9c59e2243f8a5db955f4ad1686d5e0ad26e1a`, branch
  `gki-android15-6.6`.
- `ksun341-susfs230.patch` SHA256:
  `268cc412302504a4ad608bee9426473dfaade3047a3befb2b0438fe516d62f3a`.
- Generated common patch SHA256:
  `094fffbe1eb8201d6ce1ce54807226ed045096946b1037893fb9482eccdc9d37`.
- Matching upstream ARM64 helper SHA256:
  `eb727d479a0ff2d5557369c49a3e7492b5236a7c37499d235260e4ed4d24976d`.
- `ksun-version-pin.patch` SHA256:
  `7f451103f9f86e933cc46f358c9eff160e06211565f98b7d81d1916d2b970cc2`.

The manual-hook lineage includes the reviewed 2.2 port and WildKernels
`757201d983e2549dc7945a21fa6a056eb2e55263`. The scoped post-exec session
mechanism and kernel-filename SULog adapters follow
[pershoot c4653cc4](https://github.com/pershoot/KernelSU-Next/commit/c4653cc4ca61a2160ad819d615ea42811e295192).
The complete fork, additional signatures, and later unrelated features are
not imported.

## Port boundaries

The patch applies directly to official 3.4.1. It uses SUSFS manual hooks without
also enabling the native syscall dispatcher. It preserves UAPI 5, services
events, scoped FD private data and ioctl permissions, `ksu_app_profile_init`,
and the 3.4.1 seccomp backport probe with its ARM64 symbol/instruction helpers.

Only allowlisted su with successful root-profile application qualifies for the
post-exec hook. FD installation also requires successful exec; normal exec,
init-only handling, denied su, and early failures do not install a su FD.
The disable-escape and `set_cred_ucounts` failure paths return their errors.
SUSFS 2.3 common already contains the post-exec hook, so the old separate 2.2
compatibility patch is removed.

The 2.3 interfaces add separate no-su/zygote-next flags, the filename-pointer
faccessat hook, first-zygote bootstrap gating, and safe-mode static-key changes
outside the input spinlock. WebView UID 1053 follows its existing umount policy
explicitly because Next's `is_appuid` excludes it; this does not grant root.

Official profile capabilities remain exact. The upstream expression
`effective | CAP_DAC_READ_SEARCH` is omitted: capability number 2 is not a bit
mask and that expression adds `CAP_DAC_OVERRIDE`. Nonzero-UID profiles without
permission to traverse `/data/adb` may still fail to exec `ksud`. Newly granted
root apps may need force-stop/reopen because the upstream no-su flag is cached.

Stock ARM64 TIF indices are at most 28; SUSFS uses 33/34/35 and KSU uses 63, with
no collision. No config switches, certificates, or ABI allowances are added.
The version patch supplies the exact release identity inside Kleaf's sandbox.

## Helper and verification

Use the pinned 2.3 helper: the ctime mask changed from 1 to 256 despite the kstat
structure retaining its ARM64 376-byte layout. Upstream module version is
v2.3.0 but versionCode remains 202000. Deployment must enable `hide_sus_mnts`
during post-fs-data, before zygote starts, with this matching helper.

The 25 original common files match pinned Gitiles blob IDs; three SUSFS source
files are added. Exact common `.gitattributes` and `--full-index` make the
combined checksum reproducible. Fresh official KSU application, checksum,
version-pin application, and patched-tree whitespace checks passed (24 files).
Common dry-run/apply had no offsets, fuzz, or rejects; a second clean strict
`git apply` reproduced the combined hash and 28-file scope. Seven verbatim
upstream whitespace warnings remain: six in `fs/susfs.c`, one in `mm/memory.c`.

Compilation, strict ABI validation, temporary boot, and live root/SUSFS checks
remain separate gates. These source checks do not establish application hiding
or support for every custom root profile.
