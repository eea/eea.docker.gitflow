FROM python:3-alpine3.15
LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"


RUN apk add --no-cache --virtual .run-deps git python2 bash curl coreutils bc yarn jq make runc libseccomp build-base gcc libffi-dev npm libstdc++ \
 && pip install --upgrade pip \ 
 && pip install docutils twine rstcheck zest.pocompile \
 && pip install -I wheel==0.31.0 \
 && npm install -g release-it yarn-deduplicate 


SHELL [ "/bin/bash", "-l", "-c" ]

COPY src/* /

ENTRYPOINT ["/docker-entrypoint.sh"]
