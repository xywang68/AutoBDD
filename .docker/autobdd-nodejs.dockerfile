ARG AUTOBDD_VERSION
FROM xyteam/autobdd-ubuntu:${AUTOBDD_VERSION}
USER root
ENV DEBIAN_FRONTEND noninteractive

# apt set keys for additional packages
RUN \
    # set apt-key for nodejs 14.x. 16.x breaks fiber, avoid unil fiber provides fix
    curl -fsSL https://deb.nodesource.com/setup_14.x | sudo -E bash - ; \
    # nodesource's setup script writes a signed-by=.../nodesource.gpg keyring that is
    # empty of the current signing key (1655A0AB68576280), so apt cannot verify it.
    # Import the key into trusted.gpg and drop the signed-by override so apt uses it.
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 1655A0AB68576280 ; \
    sed -i "s| \[signed-by=/usr/share/keyrings/nodesource.gpg\]||" /etc/apt/sources.list.d/nodesource.list ; \
    # set apt-key for google-chrome
    rm -f /etc/apt/sources.list.d/google-chrome.list && \
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list && \
    wget -qO- --no-check-certificate https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    mkdir -p /etc/opt/chrome/policies/managed && \
    echo "{\"CommandLineFlagSecurityWarningsEnabled\": false}" > /etc/opt/chrome/policies/managed/managed_policies.json && \
    # set apt-key for k6
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 && \
    echo "deb https://dl.k6.io/deb stable main" | tee /etc/apt/sources.list.d/k6.list && \
    # terraform omitted: HashiCorp no longer publishes it for Ubuntu 20.04/focal,
    # and the phase-0 test suites do not use it.
    # update and install additional packages
    apt update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"  && \
    apt install -q -y --allow-unauthenticated --fix-missing -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    nodejs \
    google-chrome-stable \
    k6