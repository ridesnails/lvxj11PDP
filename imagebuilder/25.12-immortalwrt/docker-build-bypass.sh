#!/bin/bash
VERSION='x86-64-openwrt-25.12'
LATEST_VERSION=$(curl -s https://hub.docker.com/v2/repositories/immortalwrt/imagebuilder/tags?name=${VERSION} | \
    jq -r '.results[].name' | \
    grep -E '^'${VERSION}'\.[0-9]{1,2}$' | \
    sort -V | \
    tail -n 1)
if [ -n "${LATEST_VERSION}" ]; then
    echo "找到最新版本: ${LATEST_VERSION}"
    VERSION="${LATEST_VERSION}"
else
    echo "未找到最新版本, 使用默认版本: ${VERSION}"
    VERSION="${VERSION}.0"
fi
echo "使用版本: ${VERSION}"

chmod -R 777 .
docker run --rm -it --name imagebuilder \
    -v ./output:/output \
    -v ./builder-bypass/files:/builder/files \
    -v ./builder-bypass/build.sh:/builder/build.sh \
    immortalwrt/imagebuilder:${VERSION} \
    /bin/bash -c "/builder/build.sh"

#     /bin/bash -c "/builder/build.sh"
#     /bin/bash -c "sleep infinity"
