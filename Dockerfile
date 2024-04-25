FROM python:3-buster
LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"



RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends jq bc bash curl python2 gcc bc build-essential git dos2unix \
# .run-deps git python2 bash curl coreutils bc yarn jq make runc libseccomp build-base gcc libffi-dev npm libstdc++\
 && pip install --upgrade pip \ 
 && pip install docutils twine rstcheck zest.pocompile \
 && pip install -I wheel==0.31.0 \
 && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash \
 && curl -L -o /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 \
 && chmod 755 /usr/bin/jq \
 && rm -rf /var/lib/apt/lists/*
 

RUN export NVM_DIR="$HOME/.nvm" \
 && . "$NVM_DIR/nvm.sh" \
 && nvm install 14 \
 && npm install -g yarn release-it yarn-deduplicate yo husky\
 && nvm install 16 \
 && nvm alias default 16 \
 && npm install -g yarn release-it yarn-deduplicate yo husky\
 # fix gyp that does not work with python 3.11
 && for i in $(find . -type d -name gyp | grep pylib); do sed -i 's/rU/r/' $i/input.py; done

SHELL [ "/bin/bash", "-l", "-c" ]

COPY src/* /

ENTRYPOINT ["/docker-entrypoint.sh"]
