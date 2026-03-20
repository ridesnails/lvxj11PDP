#!/bin/bash
chmod -R 777 .
docker run --rm -it --name imagebuilder \
    -v ./output:/output \
    -v ./builder-bypass/files:/builder/files \
    -v ./builder-bypass/build.sh:/builder/build.sh \
    openwrt/imagebuilder:x86-64-25.12.1 \
    /bin/bash -c "/builder/build.sh"

# docker run --rm -itd --name imagebuilder -v ./output:/output -v ./builder-bypass/files:/builder/files -v ./builder-bypass/build.sh:/builder/build.sh openwrt/imagebuilder:x86-64-25.12.0 /bin/bash -c "sleep infinity"