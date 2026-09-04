ARG AUTOBDD_VERSION
FROM xyteam/autobdd-nodejs:${AUTOBDD_VERSION}
USER root
ENV DEBIAN_FRONTEND noninteractive

# install AutoBDD
ADD . /root/Projects/AutoBDD

# setup AutoBDD
# NOTE: the build-time `npm test` (download-test via npx degit + test-init) is skipped:
# current `degit` requires Node >= 18 and fails on this Node-14 base, and the smoke is
# redundant here - autobdd-test / AutoBDD-example run the real suites against this image
# in their own repos (dev-mode mounts the working-tree framework anyway).
RUN mkdir -p /root/Downloads && \
    cd /root/Projects/AutoBDD && \
    pip install -r requirement.txt && \
    npm config set script-shell "/bin/bash" && \
    npm cache clean --force && \
    npm --loglevel=error install && \
    npm run --loglevel=error clean && \
    rm -rf /tmp/chrome_profile_* /tmp/download_*

# copy preset ubuntu system env
COPY .docker/autobdd.root /
RUN chmod +x /root/.bash_profile /root/autobdd-run.startup.sh /root/autobdd-dev.startup.sh 
