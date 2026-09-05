ARG AUTOBDD_VERSION
FROM xyteam/autobdd-nodejs:${AUTOBDD_VERSION}
USER root
ENV DEBIAN_FRONTEND noninteractive
# BUILD FOR 3.0.0: `docker build --build-arg AUTOBDD_VERSION=2.3.0 -f .docker/autobdd-image.dockerfile .`
# The autobdd-nodejs:2.3.0 base is the released Node 12.22.7 + Chrome 96 runtime that
# phase-0 (wdio7) is verified against; do NOT rebuild it from source (see the note in
# autobdd-nodejs.dockerfile). This layer bakes the phase-0 AutoBDD source + npm install
# (wdio7) on top of that base.

# install AutoBDD
ADD . /root/Projects/AutoBDD

# setup AutoBDD
# NOTE: the build-time `npm test` (download-test via npx degit + test-init) is skipped:
# current `degit` requires Node >= 18 and fails on this Node base, and the smoke is
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
