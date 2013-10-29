#!/bin/bash

version=${1:-2.1~}
snapshot=$(git show -s --format='%ci' HEAD | cut -d' ' -f1 | tr -d -)
revision=${2:-1}
prefix="click_${version}git${snapshot}-${revision}/"
tarball="click_${version}git${snapshot}.orig.tar.gz"

# create the source tarball
git archive --format=tar --prefix="${prefix}" HEAD | gzip > "${tarball}"

# unpack it
tar -xzf "${tarball}"

# build the .deb binary package
pushd "${prefix}" > /dev/null
debuild -i -us -uc -b
popd > /dev/null

# cleanup
rm -rf "${prefix}" "${tarball}"
git reset --hard HEAD
