# syntax=docker.io/docker/dockerfile:1

ARG DEBIAN_RELEASE=bookworm
ARG PKG_IMG=ghcr.io/rspamd/rspamd-docker
ARG PKG_TAG=pkg-latest

# `--from=` doesn't support ARG/ENV expansion:
# https://github.com/moby/buildkit/pull/6153
FROM ${PKG_IMG}:${PKG_TAG} AS pkg

FROM debian:${DEBIAN_RELEASE}-slim AS install
SHELL ["/bin/bash", "-eux", "-o", "pipefail", "-c"]
ARG ASAN_TAG

RUN	--mount=type=bind,from=pkg,source=/deb,target=/deb <<"HEREDOC"
	# Extract a list of dependencies from the rspamd packages for this layer to cache:
	RSPAMD_DEPS=$(dpkg --info /deb/rspamd${ASAN_TAG}_*_*.deb | grep '^ Depends:' | perl -p -e 's#Depends: |,|\||\([^)]*\)##g')

	apt-get -qq update
	apt-get -qq install ${RSPAMD_DEPS}

	# Reproducible build support - Remove disposable content
	apt-get -qq clean
	rm -rf \
		/var/cache/ldconfig/aux-cache \
		/var/lib/apt/lists/* \
		/var/log/apt/*.log \
		/var/log/dpkg.log
HEREDOC

RUN	--mount=type=bind,from=pkg,source=/deb,target=/deb <<HEREDOC
	dpkg --install /deb/rspamd${ASAN_TAG}_*_*.deb /deb/rspamd${ASAN_TAG}-dbg_*_*.deb
	rm -rf /var/log/dpkg.log

	# Reproducible build support:
	# Unset the password change date to normalize the `_rspamd` entry in `/etc/shadow`.
	# Afterwards remove backup and related account backup files caused by the package install.
	chage --lastday -1
	rm /etc/passwd- /etc/group- /etc/gshadow- /etc/shadow-
HEREDOC
COPY ./lid.176.ftz /usr/share/rspamd/languages/fasttext_model.ftz

USER	11333:11333
VOLUME  [ "/var/lib/rspamd" ]
CMD     [ "/usr/bin/rspamd", "-f" ]

# https://www.rspamd.com/doc/workers
# 11332 proxy ; 11333 normal ; 11334 controller
EXPOSE  11332 11333 11334
