#!/usr/bin/env bash
# `setup:oci-plugin`: migrate the OCI plugin from the legacy asdf backend to
# vfox. Placed by the setup:scripts task in .mise.toml; see the comment there.
set -eo pipefail
vfox_url="https://github.com/jdx/vfox-oci.git"
plugin_url="$(mise plugins ls --urls | awk '$1 == "oci" { print $2; exit }')"
case "$plugin_url" in
    https://github.com/jdx/vfox-oci|https://github.com/jdx/vfox-oci.git|git@github.com:jdx/vfox-oci.git)
        echo "✓ OCI vfox plugin is already installed"
        ;;
    "")
        echo "📦 Installing the OCI vfox plugin..."
        mise plugins install oci "$vfox_url"
        ;;
    *)
        echo "📦 Replacing the non-vfox OCI plugin ($plugin_url)..."
        # `mise plugins install oci` manages asdf plugins and therefore picks
        # the registry's asdf fallback even though vfox is listed first. The
        # explicit URL is what changes the checkout's implementation.
        mise plugins install --force oci "$vfox_url"
        ;;
esac
