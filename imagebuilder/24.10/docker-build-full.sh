#!/bin/bash
chmod -R 777 .
docker run --rm -it --name imagebuilder \
    -v ./bin:/home/build/immortalwrt/bin \
    -v ./files-full:/home/build/immortalwrt/files \
    -v ./build.sh:/home/build/immortalwrt/build.sh \
    immortalwrt/imagebuilder:x86-64-openwrt-24.10.2 \
    /bin/bash -c "/home/build/immortalwrt/build.sh"
    
    # /bin/bash -c "/home/build/immortalwrt/build.sh"
    # /bin/bash -c "sleep infinity"