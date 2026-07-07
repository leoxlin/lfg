# Changelog

## [0.5.0](https://github.com/leoxlin/lfg/compare/v0.4.1...v0.5.0) (2026-07-07)


### Features

* create version command ([c1db15d](https://github.com/leoxlin/lfg/commit/c1db15d861ed5f54af295cb86fd08f5cbed01938))

## [0.4.1](https://github.com/leoxlin/lfg/compare/v0.4.0...v0.4.1) (2026-07-06)


### Bug Fixes

* remove dir fish update ([c0e4607](https://github.com/leoxlin/lfg/commit/c0e4607a3c42b1bc0eed43b59e3d006f6a8d12ff))

## [0.4.0](https://github.com/leoxlin/lfg/compare/v0.3.0...v0.4.0) (2026-07-06)


### Features

* add file install logging to install.sh ([f9926fc](https://github.com/leoxlin/lfg/commit/f9926fce4dd8bc3ed4dd2732660461dddf998394))
* **cmd:** improve --help ([fc8fa37](https://github.com/leoxlin/lfg/commit/fc8fa37a4e31e90bec4295eaa27ccbdd1a415758))
* **installer:** better logging ([5afb0b6](https://github.com/leoxlin/lfg/commit/5afb0b626b23f7fa7211330accc6f4ebf96b4342))
* **installer:** dependency install ([a5557d6](https://github.com/leoxlin/lfg/commit/a5557d64d6ff2a517dd5f18310a734c3a59b1e73))
* **installer:** standardize on dash args ([07a25c1](https://github.com/leoxlin/lfg/commit/07a25c131d4e0ac2f849dc4762460c6f38ea3a5a))


### Bug Fixes

* **installer:** install all files ([2fb3d74](https://github.com/leoxlin/lfg/commit/2fb3d74e978d4812bf4899c384bfd553d73e8d89))

## [0.3.0](https://github.com/leoxlin/lfg/compare/v0.2.0...v0.3.0) (2026-07-06)


### Features

* add --help ([d771253](https://github.com/leoxlin/lfg/commit/d771253d5cb91387c85074086cf07129c5485791))
* add support more auto comp ([fc4829a](https://github.com/leoxlin/lfg/commit/fc4829abbde343c77749f75b4ead8ead9a7a67df))
* bundle entrypoint completions ([f96b518](https://github.com/leoxlin/lfg/commit/f96b51856a9e5b9cb849815a50a256747e05306b))
* custom lfg_worktree_setup func ([9246584](https://github.com/leoxlin/lfg/commit/92465848037bfa7e0bf8a52556a203f3349e85f1))
* end worktree path as repo name ([f6d01d6](https://github.com/leoxlin/lfg/commit/f6d01d6e6eed765b2273af3b073e154669b5aa01))
* error on bad LFG_SOURCE_DIR ([28a4df4](https://github.com/leoxlin/lfg/commit/28a4df41ab40d9f959023eefc6086be4388c8314))
* improve tooltip ([bbcb9ca](https://github.com/leoxlin/lfg/commit/bbcb9ca930b2c07de468e1217475efc7288cffcc))
* swap to --update, rm branch arg ([720cc3d](https://github.com/leoxlin/lfg/commit/720cc3dc44f623f51cdc20227a45780c6fd760d5))
* try to discover sources dir ([16f5026](https://github.com/leoxlin/lfg/commit/16f502675b5de8fbe8af13013255d4f3bb8422b5))
* update prune default to 7 days ([ee555a5](https://github.com/leoxlin/lfg/commit/ee555a5a0f03814798c71a5c8d058bf81e2c31f9))


### Bug Fixes

* make update work ([552bd57](https://github.com/leoxlin/lfg/commit/552bd578885dc106e478d868e24f3af56f81e78a))
* pointer color ([8f0fed7](https://github.com/leoxlin/lfg/commit/8f0fed7b1d905cc741e63f63e61f7bf0557f2d0e))

## [0.2.0](https://github.com/leoxlin/lfg/compare/v0.1.0...v0.2.0) (2026-07-06)


### Features

* add update & install from release ([64ccef3](https://github.com/leoxlin/lfg/commit/64ccef3aea85a138e95dc70a465a90e61aa52af4))
* install using tar ([54d80d2](https://github.com/leoxlin/lfg/commit/54d80d2d0e74a1d3ee5d3bf39e686b8ead2e8533))
* only support leoxlin/lfg ([bb7765d](https://github.com/leoxlin/lfg/commit/bb7765d3ab692d19d4d6825b1b60bf87f329f254))

## 0.1.0 (2026-07-06)


### Features

* add install.sh for one-line lfg setup ([4b9766f](https://github.com/leoxlin/lfg/commit/4b9766f8f37784e397e6a84a62bc6a01c1550036))
* add popular coding agents to lfg autocomplete ([fcc23aa](https://github.com/leoxlin/lfg/commit/fcc23aa194e3a71260ac947e211034116269e480))
* add release script ([6ff4071](https://github.com/leoxlin/lfg/commit/6ff4071508611bb9766617d9a5feafbfa60a451a))
* change install strategy ([75befe5](https://github.com/leoxlin/lfg/commit/75befe5dbdad4f6d6e77bf95030af69bd7707d38))
* configurable fzf pointer color via LFG_FZF_POINTER_COLOR ([bf0420c](https://github.com/leoxlin/lfg/commit/bf0420c8715a4c3d736c12504a9261502cc9034c))
* detect running shell for install ([90e1851](https://github.com/leoxlin/lfg/commit/90e185118e3bd0d20114ecc46e898950c4dc29cb))
* importing lfg.zsh ([eaadfcd](https://github.com/leoxlin/lfg/commit/eaadfcdeb4eeed9535d1d7b320d3360e7881b663))
* install skill profile source updates ([d210f9c](https://github.com/leoxlin/lfg/commit/d210f9cd060a3adf5a0d705f40a934707824673f))
* parameterize default agent via LFG_DEFAULT_AGENT_COMMAND ([7d79c41](https://github.com/leoxlin/lfg/commit/7d79c41007f0737252e76cb8a9a9621b21c8ecac))
* parameterize prune age via LFG_PRUNE_OLDER_THAN_DAYS ([37fc040](https://github.com/leoxlin/lfg/commit/37fc04028ca0abd87dab095a2aac3e9989dc7499))
* port to multiple shells ([96a7dd2](https://github.com/leoxlin/lfg/commit/96a7dd2dd54eab2e8a0b4e5dacb6e70094cc001f))
* rename lfgwt back to worktree ([14026b7](https://github.com/leoxlin/lfg/commit/14026b7858dfdcdcd843c5cc5adfcb29ddf0fbcd))
* setup release please ([832dee8](https://github.com/leoxlin/lfg/commit/832dee89f62d6f162cd30125d363fc6ea2ba1b44))
* simplify codebase ([c0b7dc3](https://github.com/leoxlin/lfg/commit/c0b7dc38a6e0a360adfae4965bb01daa14852d42))
* update worktree command to lfgwt ([d0f5508](https://github.com/leoxlin/lfg/commit/d0f5508215822e00939d80e0e80412bc6fbfecc9))
