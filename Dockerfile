FROM python:3-alpine3.13
LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"


RUN apk add --no-cache --virtual .run-deps git python2 bash curl coreutils bc yarn jq  build-base gcc libffi-dev npm libstdc++\
 && pip install --upgrade pip \ 
 && pip install docutils twine rstcheck \
 && pip install -I wheel==0.31.0 \
 && npm install -g release-it yarn-deduplicate \
 && echo 'source $HOME/.profile;' >> $HOME/.zshrc \
 && touch $HOME/.profile \
 && chmod 755 $HOME/.profile \
 && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash \
 && export NVM_DIR="$HOME/.nvm" \
 && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" \
 && nvm install 16 \
 && nvm use 16


SHELL [ "/bin/bash", "-l", "-c" ]

COPY src/* /

ENTRYPOINT ["/docker-entrypoint.sh"]
