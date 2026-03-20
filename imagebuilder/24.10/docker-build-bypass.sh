#!/bin/bash
chmod -R 777 .
docker run --rm -it --name imagebuilder \
    -v ./bin:/home/build/immortalwrt/bin \
    -v ./files-bypass:/home/build/immortalwrt/files \
    -v ./build-bypass.sh:/home/build/immortalwrt/build.sh \
    immortalwrt/imagebuilder:x86-64-openwrt-24.10.5 \
    /bin/bash -c "/home/build/immortalwrt/build.sh"
    
    # /bin/bash -c "/home/build/immortalwrt/build.sh"
    # /bin/bash -c "sleep infinity"