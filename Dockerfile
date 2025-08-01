FROM python:3
LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"

ENV YQ_VERSION=v4.44.6
ENV JQ_VERSION=1.6

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends jq bc bash curl gcc bc build-essential git dos2unix \
# .run-deps git bash curl coreutils bc yarn jq make runc libseccomp build-base gcc libffi-dev npm libstdc++\
 && pip install --upgrade pip \ 
 && pip install docutils twine rstcheck zest.pocompile \
 && pip install -I wheel==0.31.0 \
 && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash \
 && curl -L -o /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/jq-linux64 \
 && chmod 755 /usr/bin/jq \
 && wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64.tar.gz -O - | tar xz \
 && mv yq_linux_amd64 /usr/bin/yq \
 && rm -rf /var/lib/apt/lists/* 

RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
 && chmod 700 get_helm.sh \
 && ./get_helm.sh \
 && rm get_helm.sh

RUN export NVM_DIR="$HOME/.nvm" \
 && . "$NVM_DIR/nvm.sh" \
 && nvm install 18 \
 && npm install -g is-ci yarn release-it yarn-deduplicate yo husky rimraf\
 && nvm install 16 \
 && nvm alias default 16 \
 && npm install -g yarn release-it@16 yarn-deduplicate isbinaryfile@4 husky@8\
 # fix gyp that does not work with python 3.11
 && for i in $(find . -type d -name gyp | grep pylib); do sed -i 's/rU/r/' $i/input.py; done

SHELL [ "/bin/bash", "-l", "-c" ]

COPY src/* /

ENTRYPOINT ["/docker-entrypoint.sh"]
